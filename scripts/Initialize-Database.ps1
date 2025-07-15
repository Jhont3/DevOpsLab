#Requires -Version 7.0

<#
.SYNOPSIS
Inicializa las colecciones de CosmosDB con datos de prueba

.DESCRIPTION
Este script inicializa las colecciones 'usuarios' y 'animales' de CosmosDB 
con los datos de prueba requeridos después del despliegue de infraestructura.

.PARAMETER ClientName
Nombre del cliente (elite, jarandes)

.PARAMETER Environment
Ambiente de despliegue (testing, main)

.PARAMETER ConfigPath
Ruta al archivo de configuración de clientes

.EXAMPLE
.\Initialize-Database.ps1 -ClientName "elite" -Environment "testing"

.EXAMPLE
.\Initialize-Database.ps1 -ClientName "jarandes" -Environment "main" -ConfigPath "../config/clients.json"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("elite", "jarandes")]
    [string]$ClientName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "../config/clients.json"
)

# Importar módulos necesarios
Import-Module Az.Accounts -Force
Import-Module Az.CosmosDB -Force

# Función para escribir logs con timestamp
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}

# Función para validar y obtener configuración
function Get-ClientConfig {
    param([string]$ConfigPath, [string]$ClientName, [string]$Environment)
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            throw "Archivo de configuración no encontrado: $ConfigPath"
        }
        
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $clientConfig = $config.clients.$ClientName.environments.$Environment
        
        if (-not $clientConfig) {
            throw "Configuración no encontrada para cliente '$ClientName' en ambiente '$Environment'"
        }
        
        return $clientConfig
    }
    catch {
        Write-Log "Error obteniendo configuración: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Función para crear documento en CosmosDB
function New-CosmosDocument {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$CollectionName,
        [hashtable]$Document,
        [string]$ResourceGroup
    )
    
    try {
        # Obtener la clave de acceso
        $keys = Get-AzCosmosDBAccountKey -ResourceGroupName $ResourceGroup -Name $AccountName
        $primaryKey = $keys.PrimaryMasterKey
        
        # Construir la URI
        $uri = "https://$AccountName.documents.azure.com/dbs/$DatabaseName/colls/$CollectionName/docs"
        
        # Preparar headers
        $date = [DateTime]::UtcNow.ToString("r")
        $headers = @{
            "Authorization" = $primaryKey
            "x-ms-date" = $date
            "x-ms-version" = "2018-12-31"
            "Content-Type" = "application/json"
        }
        
        # Convertir documento a JSON
        $body = $Document | ConvertTo-Json -Depth 10
        
        # Realizar la llamada REST
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        
        Write-Log "Documento creado exitosamente en $CollectionName con ID: $($Document.id)" "SUCCESS"
        return $response
    }
    catch {
        Write-Log "Error creando documento en $CollectionName : $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Función principal
function Initialize-DatabaseCollections {
    param($ClientConfig, [string]$ClientName)
    
    Write-Log "Iniciando inicialización de base de datos para cliente: $ClientName"
    
    $resourceGroup = $ClientConfig.resourceGroup
    $accountName = $ClientConfig.cosmosDb.accountName
    $databaseName = $ClientConfig.cosmosDb.databaseName
    
    Write-Log "Conectando a CosmosDB: $accountName"
    
    # Datos de prueba para usuarios
    $usuariosData = @(
        @{
            id = "1"
            nombre = "usuario1"
            email = "usuario1@$($ClientName.ToLower()).com"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        },
        @{
            id = "2"
            nombre = "usuario2"
            email = "usuario2@$($ClientName.ToLower()).com"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        },
        @{
            id = "3"
            nombre = "usuario3"
            email = "usuario3@$($ClientName.ToLower()).com"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        }
    )
    
    # Datos de prueba para animales
    $animalesData = @(
        @{
            id = "1"
            nombre = "perro"
            tipo = "mamifero"
            caracteristicas = @("domestico", "fiel", "carnivoro")
            fechaRegistro = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        },
        @{
            id = "2"
            nombre = "gato"
            tipo = "mamifero"
            caracteristicas = @("domestico", "independiente", "carnivoro")
            fechaRegistro = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        },
        @{
            id = "3"
            nombre = "ratón"
            tipo = "mamifero"
            caracteristicas = @("pequeño", "roedor", "omnivoro")
            fechaRegistro = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    )
    
    try {
        # Verificar que la cuenta de CosmosDB existe
        $cosmosAccount = Get-AzCosmosDBAccount -ResourceGroupName $resourceGroup -Name $accountName
        if (-not $cosmosAccount) {
            throw "Cuenta de CosmosDB no encontrada: $accountName"
        }
        
        Write-Log "Cuenta de CosmosDB encontrada: $accountName"
        
        # Insertar datos en colección usuarios
        Write-Log "Insertando datos en colección 'usuarios'..."
        foreach ($usuario in $usuariosData) {
            try {
                New-CosmosDocument -AccountName $accountName -DatabaseName $databaseName -CollectionName "usuarios" -Document $usuario -ResourceGroup $resourceGroup
            }
            catch {
                if ($_.Exception.Message -like "*Conflict*" -or $_.Exception.Message -like "*409*") {
                    Write-Log "Usuario con ID $($usuario.id) ya existe, omitiendo..." "WARNING"
                }
                else {
                    throw
                }
            }
        }
        
        # Insertar datos en colección animales
        Write-Log "Insertando datos en colección 'animales'..."
        foreach ($animal in $animalesData) {
            try {
                New-CosmosDocument -AccountName $accountName -DatabaseName $databaseName -CollectionName "animales" -Document $animal -ResourceGroup $resourceGroup
            }
            catch {
                if ($_.Exception.Message -like "*Conflict*" -or $_.Exception.Message -like "*409*") {
                    Write-Log "Animal con ID $($animal.id) ya existe, omitiendo..." "WARNING"
                }
                else {
                    throw
                }
            }
        }
        
        Write-Log "✅ Inicialización de base de datos completada exitosamente" "SUCCESS"
        Write-Log "📊 Datos insertados:" "SUCCESS"
        Write-Log "   - 3 usuarios: usuario1, usuario2, usuario3" "SUCCESS"
        Write-Log "   - 3 animales: perro, gato, ratón" "SUCCESS"
    }
    catch {
        Write-Log "❌ Error durante la inicialización: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Script principal
try {
    Write-Log "🚀 Iniciando script de inicialización de base de datos"
    Write-Log "Cliente: $ClientName | Ambiente: $Environment"
    
    # Verificar autenticación con Azure
    $context = Get-AzContext
    if (-not $context) {
        Write-Log "No hay contexto de Azure activo. Ejecutando autenticación..." "WARNING"
        Connect-AzAccount
    }
    else {
        Write-Log "Contexto de Azure activo: $($context.Account.Id)" "SUCCESS"
    }
    
    # Obtener configuración del cliente
    $clientConfig = Get-ClientConfig -ConfigPath $ConfigPath -ClientName $ClientName -Environment $Environment
    
    # Ejecutar inicialización
    Initialize-DatabaseCollections -ClientConfig $clientConfig -ClientName $ClientName
    
    Write-Log "🎉 Script completado exitosamente" "SUCCESS"
}
catch {
    Write-Log "💥 Error crítico: $($_.Exception.Message)" "ERROR"
    Write-Log "Detalles del error:" "ERROR"
    Write-Log $_.Exception.StackTrace "ERROR"
    exit 1
} 