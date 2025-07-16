#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Validates that Cosmos DB contains the expected default data.

.DESCRIPTION
    This script validates that the Cosmos DB database contains the default data
    as specified in the lab requirements:
    - usuarios: usuario1, usuario2, usuario3
    - animales: perro, gato, ratón

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER ConfigFile
    Path to the clients configuration file (default: "config/clients.json")

.EXAMPLE
    .\Validate-CosmosData.ps1 -ClientName "elite" -Environment "main"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "config/clients.json"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to validate container data using Azure CLI
function Test-CosmosContainerData {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$ContainerName,
        [array]$ExpectedItems
    )
    
    Write-ColorOutput "🔍 Validating data in container: $ContainerName" "Yellow"
    
    try {
        # Query all documents in the container
        $query = "SELECT c.id FROM c"
        $result = az cosmosdb sql query `
            --account-name $AccountName `
            --database-name $DatabaseName `
            --container-name $ContainerName `
            --query-text $query `
            --output json
        
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "   ❌ Error querying container: $ContainerName" "Red"
            return $false
        }
        
        $actualItems = ($result | ConvertFrom-Json) | ForEach-Object { $_.id }
        
        Write-ColorOutput "   📊 Found $($actualItems.Count) items in $ContainerName" "Cyan"
        
        $allFound = $true
        foreach ($expectedItem in $ExpectedItems) {
            if ($actualItems -contains $expectedItem) {
                Write-ColorOutput "   ✅ Found expected item: $expectedItem" "Green"
            } else {
                Write-ColorOutput "   ❌ Missing expected item: $expectedItem" "Red"
                $allFound = $false
            }
        }
        
        return $allFound
        
    } catch {
        Write-ColorOutput "   ❌ Error validating $ContainerName`: $_" "Red"
        return $false
    }
}

# Main validation logic
Write-ColorOutput "🚀 Starting Cosmos DB data validation..." "Yellow"

# Load client configuration
if (-not (Test-Path $ConfigFile)) {
    Write-ColorOutput "❌ Configuration file not found: $ConfigFile" "Red"
    exit 1
}

try {
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    $clientConfig = $config.clients.$ClientName.environments.$Environment
    
    if (-not $clientConfig) {
        Write-ColorOutput "❌ Client configuration not found for: $ClientName-$Environment" "Red"
        exit 1
    }
    
    $resourceGroupName = $clientConfig.resourceGroup
    $accountName = $clientConfig.cosmosDb.accountName
    $databaseName = $clientConfig.cosmosDb.databaseName
    
    Write-ColorOutput "📋 Validation details:" "Cyan"
    Write-ColorOutput "   🏢 Client: $ClientName" "Gray"
    Write-ColorOutput "   🌍 Environment: $Environment" "Gray"
    Write-ColorOutput "   📦 Resource Group: $resourceGroupName" "Gray"
    Write-ColorOutput "   🗄️  Database: $databaseName" "Gray"
    Write-ColorOutput "   🔗 Account: $accountName" "Gray"
    
    # Test connection to Cosmos DB
    Write-ColorOutput "🔌 Testing Cosmos DB connection..." "Yellow"
    $dbInfo = az cosmosdb sql database show `
        --account-name $accountName `
        --name $databaseName `
        --resource-group $resourceGroupName `
        --output json 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Cannot connect to Cosmos DB or database not found" "Red"
        exit 1
    }
    
    Write-ColorOutput "   ✅ Connection successful" "Green"
    
    # Define expected data
    $expectedUsuarios = @("usuario1", "usuario2", "usuario3")
    $expectedAnimales = @("perro", "gato", "raton")
    
    # Validate usuarios container
    $usuariosValid = Test-CosmosContainerData -AccountName $accountName -DatabaseName $databaseName -ContainerName "usuarios" -ExpectedItems $expectedUsuarios
    
    # Validate animales container
    $animalesValid = Test-CosmosContainerData -AccountName $accountName -DatabaseName $databaseName -ContainerName "animales" -ExpectedItems $expectedAnimales
    
    # Summary
    Write-ColorOutput "`n📊 Validation Summary:" "Cyan"
    if ($usuariosValid -and $animalesValid) {
        Write-ColorOutput "🎉 All data validation passed!" "Green"
        Write-ColorOutput "   ✅ usuarios collection: $($expectedUsuarios.Count) items verified" "Green"
        Write-ColorOutput "   ✅ animales collection: $($expectedAnimales.Count) items verified" "Green"
        Write-ColorOutput "`n💡 Your Cosmos DB is ready for use!" "Green"
    } else {
        Write-ColorOutput "❌ Data validation failed!" "Red"
        if (-not $usuariosValid) {
            Write-ColorOutput "   ❌ usuarios collection validation failed" "Red"
        }
        if (-not $animalesValid) {
            Write-ColorOutput "   ❌ animales collection validation failed" "Red"
        }
        Write-ColorOutput "`n💡 Run Initialize-CosmosData.ps1 to populate missing data" "Yellow"
        exit 1
    }
    
} catch {
    Write-ColorOutput "❌ Error during validation: $_" "Red"
    exit 1
}

Write-ColorOutput "`n✅ Cosmos DB data validation completed successfully!" "Green"
