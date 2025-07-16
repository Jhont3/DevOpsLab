#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Initializes Cosmos DB with default data for usuarios and animales collections.

.DESCRIPTION
    This script populates the Cosmos DB database with default data as specified in the lab requirements:
    - usuarios: usuario1, usuario2, usuario3
    - animales: perro, gato, ratón

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER ConfigFile
    Path to the clients configuration file (default: "config/clients.json")

.EXAMPLE
    .\Initialize-CosmosData.ps1 -ClientName "elite" -Environment "main"
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

# Function to create document in Cosmos DB using Azure CLI
function New-CosmosDocument {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$ContainerName,
        [hashtable]$Document
    )
    
    $documentJson = $Document | ConvertTo-Json -Depth 10 -Compress
    $documentId = $Document.id
    
    Write-ColorOutput "   Creating document with ID: $documentId" "Gray"
    
    try {
        # Use Azure CLI to create the document
        $result = az cosmosdb sql container create-item `
            --account-name $AccountName `
            --database-name $DatabaseName `
            --container-name $ContainerName `
            --body $documentJson `
            --output json 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "   ✅ Created: $documentId" "Green"
            return $true
        } else {
            # Check if it's a conflict (document already exists)
            if ($LASTEXITCODE -eq 1) {
                Write-ColorOutput "   ℹ️  Already exists: $documentId" "Yellow"
                return $true
            } else {
                Write-ColorOutput "   ❌ Error creating $documentId" "Red"
                return $false
            }
        }
    } catch {
        Write-ColorOutput "   ❌ Error creating $documentId`: $_" "Red"
        return $false
    }
}

# Function to initialize container with data
function Initialize-CosmosContainer {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$ContainerName,
        [array]$Items
    )
    
    Write-ColorOutput "🔄 Initializing container: $ContainerName" "Yellow"
    
    $successCount = 0
    foreach ($item in $Items) {
        if (New-CosmosDocument -AccountName $AccountName -DatabaseName $DatabaseName -ContainerName $ContainerName -Document $item) {
            $successCount++
        }
    }
    
    Write-ColorOutput "   📊 Successfully processed $successCount/$($Items.Count) items in $ContainerName" "Cyan"
    return $successCount -eq $Items.Count
}

Write-ColorOutput "🚀 Starting Cosmos DB data initialization..." "Yellow"

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
    
    Write-ColorOutput "📋 Initialization details:" "Cyan"
    Write-ColorOutput "   🏢 Client: $ClientName" "Gray"
    Write-ColorOutput "   🌍 Environment: $Environment" "Gray"
    Write-ColorOutput "   📦 Resource Group: $resourceGroupName" "Gray"
    Write-ColorOutput "   🗄️  Database: $databaseName" "Gray"
    Write-ColorOutput "   🔗 Account: $accountName" "Gray"
    
    # Test connection to Cosmos DB
    Write-ColorOutput "🔌 Testing Cosmos DB connection..." "Yellow"
    az cosmosdb sql database show `
        --account-name $accountName `
        --name $databaseName `
        --resource-group $resourceGroupName `
        --output json >$null 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Cannot connect to Cosmos DB or database not found" "Red"
        exit 1
    }
    
    Write-ColorOutput "   ✅ Connection successful" "Green"

    # Define initial data for usuarios collection
    $usuariosData = @(
        @{
            id = "usuario1"
            name = "Usuario Uno"
            email = "usuario1@$($ClientName.ToLower()).com"
            role = "admin"
            active = $true
            created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            client = $ClientName
            environment = $Environment
        },
        @{
            id = "usuario2"
            name = "Usuario Dos"
            email = "usuario2@$($ClientName.ToLower()).com"
            role = "user"
            active = $true
            created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            client = $ClientName
            environment = $Environment
        },
        @{
            id = "usuario3"
            name = "Usuario Tres"
            email = "usuario3@$($ClientName.ToLower()).com"
            role = "user"
            active = $true
            created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            client = $ClientName
            environment = $Environment
        }
    )

    # Define initial data for animales collection
    $animalesData = @(
        @{
            id = "perro"
            name = "Perro"
            tipo = "Mamífero"
            categoria = "Doméstico"
            habitat = "Casa"
            descripcion = "Animal doméstico leal y cariñoso"
            created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            client = $ClientName
            environment = $Environment
        },
        @{
            id = "gato"
            name = "Gato"
            tipo = "Mamífero"
            categoria = "Doméstico"
            habitat = "Casa"
            descripcion = "Animal doméstico independiente y ágil"
            created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            client = $ClientName
            environment = $Environment
        },
        @{
            id = "raton"
            name = "Ratón"
            tipo = "Mamífero"
            categoria = "Silvestre"
            habitat = "Campo"
            descripcion = "Pequeño roedor muy adaptable"
            created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            client = $ClientName
            environment = $Environment
        }
    )

    # Initialize containers
    Write-ColorOutput "`n📋 Initializing data collections..." "Cyan"
    
    $usuariosSuccess = Initialize-CosmosContainer -AccountName $accountName -DatabaseName $databaseName -ContainerName "usuarios" -Items $usuariosData
    $animalesSuccess = Initialize-CosmosContainer -AccountName $accountName -DatabaseName $databaseName -ContainerName "animales" -Items $animalesData
    
    # Summary
    Write-ColorOutput "`n📊 Initialization Summary:" "Cyan"
    if ($usuariosSuccess -and $animalesSuccess) {
        Write-ColorOutput "🎉 Cosmos DB data initialization completed successfully!" "Green"
        Write-ColorOutput "   ✅ usuarios collection: $($usuariosData.Count) items initialized" "Green"
        Write-ColorOutput "   ✅ animales collection: $($animalesData.Count) items initialized" "Green"
        Write-ColorOutput "`n💡 Your Cosmos DB is now ready with default data!" "Green"
    } else {
        Write-ColorOutput "❌ Some initialization steps failed!" "Red"
        if (-not $usuariosSuccess) {
            Write-ColorOutput "   ❌ usuarios collection initialization failed" "Red"
        }
        if (-not $animalesSuccess) {
            Write-ColorOutput "   ❌ animales collection initialization failed" "Red"
        }
        exit 1
    }
    
} catch {
    Write-ColorOutput "❌ Error during initialization: $_" "Red"
    exit 1
}

Write-ColorOutput "`n✅ Cosmos DB data initialization completed successfully!" "Green"
