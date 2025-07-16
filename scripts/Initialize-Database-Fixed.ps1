#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Initializes Cosmos DB with default data using only Azure CLI commands.

.DESCRIPTION
    This script initializes a Cosmos DB database with default data
    using only Azure CLI commands, making it compatible with GitHub Actions.

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER ConfigPath
    Path to the clients configuration file (default: "config/clients.json")

.EXAMPLE
    .\Initialize-Database-Fixed.ps1 -ClientName "elite" -Environment "main"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "config/clients.json"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write logs with timestamp
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

# Function to validate and get configuration
function Get-ClientConfig {
    param([string]$ConfigPath, [string]$ClientName, [string]$Environment)
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Archivo de configuración no encontrado: $ConfigPath" "ERROR"
        throw "Configuration file not found"
    }
    
    try {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        $clientConfig = $config.clients.$ClientName.environments.$Environment
        
        if (-not $clientConfig) {
            Write-Log "Configuración no encontrada para cliente: $ClientName, ambiente: $Environment" "ERROR"
            throw "Client configuration not found"
        }
        
        return $clientConfig
    }
    catch {
        Write-Log "Error cargando configuración: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Function to create document in CosmosDB using REST API
function New-CosmosDocument {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$CollectionName,
        [hashtable]$Document,
        [string]$ResourceGroup
    )
    
    try {
        # Get access key using Azure CLI
        $keysJson = az cosmosdb keys list --resource-group $ResourceGroup --name $AccountName --output json
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get Cosmos DB keys"
        }
        $keys = $keysJson | ConvertFrom-Json
        $primaryKey = $keys.primaryMasterKey
        
        # Build the URI
        $uri = "https://$AccountName.documents.azure.com/dbs/$DatabaseName/colls/$CollectionName/docs"
        
        # Prepare headers for REST API
        $date = [DateTime]::UtcNow.ToString("r")
        $verb = "POST"
        $resourceType = "docs"
        $resourceLink = "dbs/$DatabaseName/colls/$CollectionName"
        
        # Create authorization signature
        $keyBytes = [System.Convert]::FromBase64String($primaryKey)
        $sigClearText = "$verb`n$resourceType`n$resourceLink`n$date`n`n"
        $bytesSigClear = [System.Text.Encoding]::UTF8.GetBytes($sigClearText)
        $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
        $hmacsha.Key = $keyBytes
        $sigHash = $hmacsha.ComputeHash($bytesSigClear)
        $signature = [System.Convert]::ToBase64String($sigHash)
        $authHeader = [System.Web.HttpUtility]::UrlEncode("type=master&ver=1.0&sig=$signature")
        
        $headers = @{
            "Authorization" = $authHeader
            "x-ms-date" = $date
            "x-ms-version" = "2018-12-31"
            "Content-Type" = "application/json"
            "x-ms-documentdb-partitionkey" = "[`"$($Document.id)`"]"
        }
        
        # Convert document to JSON
        $body = $Document | ConvertTo-Json -Depth 10
        
        # Make the REST call
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
            Write-Log "Documento creado exitosamente en $CollectionName con ID: $($Document.id)" "SUCCESS"
            return $response
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 409) {
                Write-Log "Documento ya existe en $CollectionName con ID: $($Document.id)" "WARNING"
                return $null
            }
            else {
                throw
            }
        }
    }
    catch {
        Write-Log "Error creando documento en $CollectionName : $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Function to initialize container with default data
function Initialize-CosmosContainer {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$CollectionName,
        [array]$DefaultData,
        [string]$ResourceGroup
    )
    
    Write-Log "Inicializando contenedor: $CollectionName" "INFO"
    
    $successCount = 0
    $skippedCount = 0
    
    foreach ($item in $DefaultData) {
        try {
            $result = New-CosmosDocument -AccountName $AccountName -DatabaseName $DatabaseName -CollectionName $CollectionName -Document $item -ResourceGroup $ResourceGroup
            if ($result) {
                $successCount++
            } else {
                $skippedCount++
            }
        }
        catch {
            Write-Log "Error procesando item $($item.id): $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-Log "Contenedor $CollectionName procesado: $successCount creados, $skippedCount ya existían" "INFO"
    return $successCount + $skippedCount -eq $DefaultData.Count
}

# Main execution
try {
    Write-Log "🚀 Iniciando script de inicialización de base de datos"
    Write-Log "Cliente: $ClientName | Ambiente: $Environment"
    
    # Verify Azure CLI authentication
    $accountInfo = az account show --output json 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "No hay contexto de Azure activo. Ejecutando autenticación..." "WARNING"
        az login
    }
    else {
        $account = $accountInfo | ConvertFrom-Json
        Write-Log "Conectado a Azure con la cuenta: $($account.user.name)" "SUCCESS"
    }
    
    # Get client configuration
    $clientConfig = Get-ClientConfig -ConfigPath $ConfigPath -ClientName $ClientName -Environment $Environment
    
    $resourceGroup = $clientConfig.resourceGroup
    $accountName = $clientConfig.cosmosDb.accountName
    $databaseName = $clientConfig.cosmosDb.databaseName
    
    Write-Log "Configuración cargada:" "INFO"
    Write-Log "  Resource Group: $resourceGroup" "INFO"
    Write-Log "  Account Name: $accountName" "INFO"
    Write-Log "  Database Name: $databaseName" "INFO"
    
    # Verify Cosmos DB account exists
    $cosmosAccountJson = az cosmosdb show --resource-group $resourceGroup --name $accountName --output json 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Cuenta de CosmosDB no encontrada: $accountName"
    }
    
    Write-Log "Cuenta de CosmosDB verificada: $accountName" "SUCCESS"
    
    # Define default data for usuarios
    $defaultUsuarios = @(
        @{
            id = "usuario1"
            nombre = "Usuario Uno"
            email = "usuario1@$($ClientName.ToLower()).com"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        },
        @{
            id = "usuario2"
            nombre = "Usuario Dos"
            email = "usuario2@$($ClientName.ToLower()).com"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        },
        @{
            id = "usuario3"
            nombre = "Usuario Tres"
            email = "usuario3@$($ClientName.ToLower()).com"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        }
    )
    
    # Define default data for animales
    $defaultAnimales = @(
        @{
            id = "perro"
            nombre = "Perro"
            tipo = "mamifero"
            sonido = "guau"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        },
        @{
            id = "gato"
            nombre = "Gato"
            tipo = "mamifero"
            sonido = "miau"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        },
        @{
            id = "raton"
            nombre = "Ratón"
            tipo = "mamifero"
            sonido = "squeak"
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            activo = $true
        }
    )
    
    # Initialize usuarios container
    Write-Log "Inicializando datos de usuarios..." "INFO"
    $usuariosSuccess = Initialize-CosmosContainer -AccountName $accountName -DatabaseName $databaseName -CollectionName "usuarios" -DefaultData $defaultUsuarios -ResourceGroup $resourceGroup
    
    # Initialize animales container
    Write-Log "Inicializando datos de animales..." "INFO"
    $animalesSuccess = Initialize-CosmosContainer -AccountName $accountName -DatabaseName $databaseName -CollectionName "animales" -DefaultData $defaultAnimales -ResourceGroup $resourceGroup
    
    # Summary
    if ($usuariosSuccess -and $animalesSuccess) {
        Write-Log "🎉 Inicialización completada exitosamente!" "SUCCESS"
        Write-Log "  ✅ usuarios: 3 documentos procesados" "SUCCESS"
        Write-Log "  ✅ animales: 3 documentos procesados" "SUCCESS"
        Write-Log "💡 Base de datos lista para usar!" "SUCCESS"
    } else {
        Write-Log "❌ Inicialización falló parcialmente" "ERROR"
        if (-not $usuariosSuccess) {
            Write-Log "  ❌ Falló inicialización de usuarios" "ERROR"
        }
        if (-not $animalesSuccess) {
            Write-Log "  ❌ Falló inicialización de animales" "ERROR"
        }
        exit 1
    }
    
} catch {
    Write-Log "💥 Error crítico: $($_.Exception.Message)" "ERROR"
    Write-Log "Detalles del error:" "ERROR"
    Write-Log "   $($_.Exception.StackTrace)" "ERROR"
    exit 1
}

Write-Log "✅ Script de inicialización completado exitosamente!" "SUCCESS"
