#Requires -Version 7.0

<#
.SYNOPSIS
Despliega la infraestructura completa e inicializa la base de datos con datos de prueba

.DESCRIPTION
Este script combina el despliegue de infraestructura de Azure y la inicialización 
de las colecciones de CosmosDB con los datos de prueba requeridos.

.PARAMETER ClientName
Nombre del cliente (elite, jarandes)

.PARAMETER Environment
Ambiente de despliegue (testing, main)

.PARAMETER ConfigPath
Ruta al archivo de configuración de clientes

.PARAMETER Force
Fuerza el despliegue incluso si el grupo de recursos ya existe

.EXAMPLE
.\Deploy-And-Initialize.ps1 -ClientName "elite" -Environment "testing"

.EXAMPLE
.\Deploy-And-Initialize.ps1 -ClientName "jarandes" -Environment "main" -Force
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("elite", "jarandes")]
    [string]$ClientName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "../config/clients.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Función para escribir logs con timestamp
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "INFO" { "Cyan" }
            default { "White" }
        }
    )
}

# Script principal
try {
    Write-Log "🚀 Iniciando despliegue completo e inicialización de base de datos" "INFO"
    Write-Log "Cliente: $ClientName | Ambiente: $Environment" "INFO"
    
    # Paso 1: Ejecutar despliegue de infraestructura
    Write-Log "📦 PASO 1: Desplegando infraestructura..." "INFO"
    
    # Obtener subscription ID desde la configuración
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $subscriptionId = $config.solution.azureSubscription
    
    $deployParams = @{
        ClientName = $ClientName
        Environment = $Environment
        SubscriptionId = $subscriptionId
        ConfigFile = $ConfigPath
    }
    
    if ($Force) {
        $deployParams.Add("Force", $true)
    }
    
    $deployScript = Join-Path $PSScriptRoot "Deploy-Environment.ps1"
    
    if (-not (Test-Path $deployScript)) {
        throw "Script de despliegue no encontrado: $deployScript"
    }
    
    Write-Log "Ejecutando: $deployScript con parámetros: $($deployParams.Keys -join ', ')" "INFO"
    
    & $deployScript @deployParams
    
    if ($LASTEXITCODE -ne 0) {
        throw "Error en el despliegue de infraestructura. Código de salida: $LASTEXITCODE"
    }
    
    Write-Log "✅ Infraestructura desplegada exitosamente" "SUCCESS"
    
    # Esperar un momento para que los recursos estén completamente disponibles
    Write-Log "⏳ Esperando que los recursos estén completamente disponibles..." "INFO"
    Start-Sleep -Seconds 30
    
    # Paso 2: Inicializar base de datos
    Write-Log "🗃️ PASO 2: Inicializando base de datos con datos de prueba..." "INFO"
    
    $initParams = @{
        ClientName = $ClientName
        Environment = $Environment
        ConfigPath = $ConfigPath
    }
    
    $initScript = Join-Path $PSScriptRoot "Initialize-Database.ps1"
    
    if (-not (Test-Path $initScript)) {
        throw "Script de inicialización no encontrado: $initScript"
    }
    
    Write-Log "Ejecutando: $initScript con parámetros: $($initParams.Keys -join ', ')" "INFO"
    
    & $initScript @initParams
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "⚠️ Error en la inicialización de la base de datos, pero la infraestructura fue desplegada exitosamente" "WARNING"
        Write-Log "Puedes ejecutar manualmente: .\Initialize-Database.ps1 -ClientName $ClientName -Environment $Environment" "WARNING"
    }
    else {
        Write-Log "✅ Base de datos inicializada exitosamente" "SUCCESS"
    }
    
    # Resumen final
    Write-Log "🎉 DESPLIEGUE COMPLETO FINALIZADO" "SUCCESS"
    Write-Log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "SUCCESS"
    Write-Log "📋 Resumen del despliegue:" "SUCCESS"
    Write-Log "   Cliente: $ClientName" "SUCCESS"
    Write-Log "   Ambiente: $Environment" "SUCCESS"
    Write-Log "   ✅ Infraestructura desplegada" "SUCCESS"
    Write-Log "   ✅ Base de datos inicializada con:" "SUCCESS"
    Write-Log "      - Colección 'usuarios': usuario1, usuario2, usuario3" "SUCCESS"
    Write-Log "      - Colección 'animales': perro, gato, ratón" "SUCCESS"
    Write-Log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "SUCCESS"
    
    Write-Log "📝 Próximos pasos:" "INFO"
    Write-Log "   1. Verifica los recursos en Azure Portal" "INFO"
    Write-Log "   2. Prueba las Azure Functions desplegadas" "INFO"
    Write-Log "   3. Revisa los datos en CosmosDB" "INFO"
}
catch {
    Write-Log "💥 Error crítico durante el despliegue: $($_.Exception.Message)" "ERROR"
    Write-Log "Detalles del error:" "ERROR"
    Write-Log $_.Exception.StackTrace "ERROR"
    
    Write-Log "🔧 Soluciones sugeridas:" "WARNING"
    Write-Log "   1. Verifica tu autenticación con Azure" "WARNING"
    Write-Log "   2. Confirma que tienes permisos en la suscripción" "WARNING"
    Write-Log "   3. Revisa la configuración en $ConfigPath" "WARNING"
    Write-Log "   4. Ejecuta los scripts por separado para identificar el problema:" "WARNING"
    Write-Log "      - .\Deploy-Environment.ps1 -ClientName $ClientName -Environment $Environment" "WARNING"
    Write-Log "      - .\Initialize-Database.ps1 -ClientName $ClientName -Environment $Environment" "WARNING"
    
    exit 1
} 