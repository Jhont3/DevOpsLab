#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Initializes Cosmos DB with default data using Azure CLI.

.DESCRIPTION
    This script initializes a Cosmos DB database with default data
    using Azure CLI commands. It's designed to work in GitHub Actions
    environments where Azure PowerShell modules are not available.

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER ConfigPath
    Path to the clients configuration file (default: "config/clients.json")

.EXAMPLE
    .\Initialize-CosmosData-CLI.ps1 -ClientName "elite" -Environment "main"
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

# Function to create document in CosmosDB using Azure CLI
function New-CosmosDocument {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$ContainerName,
        [hashtable]$Document
    )
    
    try {
        # Convert document to JSON
        $documentJson = $Document | ConvertTo-Json -Depth 10 -Compress
        
        # Use Azure CLI to create document
        Write-Log "Creando documento con ID: $($Document.id) en container: $ContainerName" "INFO"
        
        $result = az cosmosdb sql item create `
            --account-name $AccountName `
            --database-name $DatabaseName `
            --container-name $ContainerName `
            --body $documentJson `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Documento creado exitosamente en $ContainerName con ID: $($Document.id)" "SUCCESS"
            return $true
        } else {
            # Check if document already exists
            if ($result -match "Conflict.*already exists") {
                Write-Log "Documento ya existe en $ContainerName con ID: $($Document.id)" "WARNING"
                return $true
            } else {
                Write-Log "Error creando documento: $result" "ERROR"
                return $false
            }
        }
    }
    catch {
        Write-Log "Error creando documento en $ContainerName : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to initialize container with default data
function Initialize-CosmosContainer {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$ContainerName,
        [array]$DefaultData
    )
    
    Write-Log "Inicializando container: $ContainerName" "INFO"
    
    $successCount = 0
    $totalCount = $DefaultData.Count
    
    foreach ($item in $DefaultData) {
        $success = New-CosmosDocument -AccountName $AccountName -DatabaseName $DatabaseName -ContainerName $ContainerName -Document $item
        if ($success) {
            $successCount++
        }
    }
    
    Write-Log "Container $ContainerName inicializado: $successCount/$totalCount documentos procesados" "INFO"
    return $successCount -eq $totalCount
}

# Main execution
try {
    Write-Log "🚀 Iniciando script de inicialización de base de datos" "INFO"
    Write-Log "Cliente: $ClientName | Ambiente: $Environment" "INFO"
    
    # Get client configuration
    $clientConfig = Get-ClientConfig -ConfigPath $ConfigPath -ClientName $ClientName -Environment $Environment
    
    $resourceGroupName = $clientConfig.resourceGroup
    $accountName = $clientConfig.cosmosDb.accountName
    $databaseName = $clientConfig.cosmosDb.databaseName
    
    Write-Log "Configuración cargada:" "INFO"
    Write-Log "  Resource Group: $resourceGroupName" "INFO"
    Write-Log "  Account Name: $accountName" "INFO"
    Write-Log "  Database Name: $databaseName" "INFO"
    
    # Check if Cosmos DB account exists and is accessible
    Write-Log "Verificando acceso a Cosmos DB..." "INFO"
    $dbCheck = az cosmosdb sql database show `
        --account-name $accountName `
        --name $databaseName `
        --resource-group $resourceGroupName `
        --output json 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "No se puede acceder a la base de datos. Verifica que el deployment haya terminado." "ERROR"
        throw "Cannot access Cosmos DB database"
    }
    
    Write-Log "Acceso a Cosmos DB verificado exitosamente" "SUCCESS"
    
    # Define default data for usuarios
    $defaultUsuarios = @(
        @{
            id = "usuario1"
            nombre = "Usuario Uno"
            email = "usuario1@$ClientName.com"
            activo = $true
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        },
        @{
            id = "usuario2"
            nombre = "Usuario Dos"
            email = "usuario2@$ClientName.com"
            activo = $true
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        },
        @{
            id = "usuario3"
            nombre = "Usuario Tres"
            email = "usuario3@$ClientName.com"
            activo = $true
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    )
    
    # Define default data for animales
    $defaultAnimales = @(
        @{
            id = "perro"
            nombre = "Perro"
            tipo = "mamifero"
            sonido = "guau"
            activo = $true
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        },
        @{
            id = "gato"
            nombre = "Gato"
            tipo = "mamifero"
            sonido = "miau"
            activo = $true
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        },
        @{
            id = "raton"
            nombre = "Ratón"
            tipo = "mamifero"
            sonido = "squeak"
            activo = $true
            fechaCreacion = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
    )
    
    # Initialize usuarios container
    Write-Log "Inicializando datos de usuarios..." "INFO"
    $usuariosSuccess = Initialize-CosmosContainer -AccountName $accountName -DatabaseName $databaseName -ContainerName "usuarios" -DefaultData $defaultUsuarios
    
    # Initialize animales container
    Write-Log "Inicializando datos de animales..." "INFO"
    $animalesSuccess = Initialize-CosmosContainer -AccountName $accountName -DatabaseName $databaseName -ContainerName "animales" -DefaultData $defaultAnimales
    
    # Summary
    if ($usuariosSuccess -and $animalesSuccess) {
        Write-Log "🎉 Inicialización completada exitosamente!" "SUCCESS"
        Write-Log "  ✅ usuarios: 3 documentos procesados" "SUCCESS"
        Write-Log "  ✅ animales: 3 documentos procesados" "SUCCESS"
        
        # Verify data was created
        Write-Log "Verificando datos creados..." "INFO"
        
        $usuariosCount = az cosmosdb sql item list `
            --account-name $accountName `
            --database-name $databaseName `
            --container-name "usuarios" `
            --query "length(@)" `
            --output tsv 2>$null
        
        $animalesCount = az cosmosdb sql item list `
            --account-name $accountName `
            --database-name $databaseName `
            --container-name "animales" `
            --query "length(@)" `
            --output tsv 2>$null
        
        Write-Log "Verificación completada:" "INFO"
        Write-Log "  📊 usuarios: $usuariosCount documentos" "INFO"
        Write-Log "  📊 animales: $animalesCount documentos" "INFO"
        
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
