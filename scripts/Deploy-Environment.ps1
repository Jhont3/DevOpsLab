#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploys a complete environment for a specific client using Bicep templates.

.DESCRIPTION
    This script deploys all necessary Azure resources for a client environment,
    including resource groups, Cosmos DB, Function Apps, and storage accounts.

.PARAMETER ClientName
    The name of the client to deploy (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment to deploy ("testing" or "main")

.PARAMETER SubscriptionId
    Azure subscription ID

.PARAMETER Location
    Azure region for deployment (default: "East US")

.PARAMETER ConfigFile
Path to the clients configuration file (default: "config/clients.json")

.EXAMPLE
    .\Deploy-Environment.ps1 -ClientName "elite" -Environment "testing" -SubscriptionId "your-subscription-id"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$Location = "East US",

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

# Function to validate prerequisites
function Test-Prerequisites {
    Write-ColorOutput "Checking prerequisites..." "Yellow"
    
    # Check if Azure CLI is installed
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        throw "Azure CLI is not installed or not in PATH"
    }
    
    # Check if Bicep is installed
    if (-not (Get-Command "bicep" -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "Installing Bicep..." "Yellow"
        az bicep install
    }
    
    # Check if config file exists
    if (-not (Test-Path $ConfigFile)) {
        throw "Configuration file not found: $ConfigFile"
    }
    
    Write-ColorOutput "Prerequisites check passed" "Green"
}

# Function to load client configuration
function Get-ClientConfig {
    param([string]$ConfigPath)
    
    Write-ColorOutput "Loading client configuration..." "Yellow"
    
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    
    if (-not $config.clients.$ClientName) {
        throw "Client '$ClientName' not found in configuration"
    }
    
    if (-not $config.clients.$ClientName.environments.$Environment) {
        throw "Environment '$Environment' not found for client '$ClientName'"
    }
    
    return $config
}

# Function to deploy environment
function Deploy-ClientEnvironment {
    param(
        [object]$Config,
        [string]$Client,
        [string]$Env
    )
    
    $clientConfig = $Config.clients.$Client
    $envConfig = $clientConfig.environments.$Env
    
    Write-ColorOutput "Deploying environment '$Env' for client '$Client'..." "Yellow"
    
    # Prepare parameters
    $deploymentName = "witag-$Client-$Env-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $parametersObject = @{
        clientName = $Client
        environmentName = $Env
        location = $envConfig.location
        resourceGroupName = $envConfig.resourceGroup
        cosmosDbAccountName = $envConfig.cosmosDb.accountName
        cosmosDbName = $envConfig.cosmosDb.databaseName
        coreFunctions = $envConfig.functions.core
        pluginFunctions = $envConfig.functions.plugins
        functionMappings = $Config.functionMappings
        cosmosCollections = $envConfig.cosmosDb.collections
    }
    
    # Convert to JSON for Azure CLI
    $parametersJson = $parametersObject | ConvertTo-Json -Depth 10 -Compress
    
    Write-ColorOutput "Deployment parameters:" "Cyan"
    Write-ColorOutput ($parametersObject | ConvertTo-Json -Depth 3) "Gray"
    
    # Deploy using Azure CLI with temporary parameters file
    Write-ColorOutput "Starting Bicep deployment..." "Yellow"
    
    # Create temporary parameters file to avoid PowerShell JSON serialization issues
    $tempParamsFile = [System.IO.Path]::GetTempFileName() + ".json"
    
    try {
        # Create ARM parameters file format
        $armParametersObject = @{
            '$schema' = 'https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#'
            contentVersion = '1.0.0.0'
            parameters = @{}
        }
        
        # Convert our parameters to ARM format
        # Use the original $parametersObject instead of converting from JSON
        foreach ($param in $parametersObject.PSObject.Properties) {
            $armParametersObject.parameters[$param.Name] = @{
                value = $param.Value
            }
        }
        
        # Write to temporary file
        $armParametersObject | ConvertTo-Json -Depth 10 | Set-Content -Path $tempParamsFile -Encoding UTF8
        
        Write-ColorOutput "Created temporary parameters file: $tempParamsFile" "Gray"
        
        # Deploy using the parameters file
    $deploymentCommand = @(
        "az", "deployment", "sub", "create"
        "--name", $deploymentName
        "--location", $Location
            "--template-file", "infrastructure/bicep/main.bicep"
            "--parameters", "@$tempParamsFile"
        "--subscription", $SubscriptionId
        "--only-show-errors"
    )
    
    $result = & $deploymentCommand[0] $deploymentCommand[1..($deploymentCommand.Length - 1)]
    }
    finally {
        # Clean up temporary file
        if (Test-Path $tempParamsFile) {
            Remove-Item $tempParamsFile -Force
            Write-ColorOutput "Cleaned up temporary parameters file" "Gray"
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Bicep deployment failed with exit code: $LASTEXITCODE"
    }
    
    Write-ColorOutput "Deployment completed successfully!" "Green"
    
    # Parse and display outputs
    $deploymentOutput = $result | ConvertFrom-Json
    if ($deploymentOutput.properties.outputs) {
        Write-ColorOutput "Deployment outputs:" "Cyan"
        $deploymentOutput.properties.outputs | ConvertTo-Json -Depth 3 | Write-Host
    }
    
    return $deploymentOutput
}

# Function to populate Cosmos DB with default data
function Initialize-CosmosData {
    param(
        [object]$Config,
        [string]$Client,
        [string]$Env
    )
    
    $envConfig = $Config.clients.$Client.environments.$Env
    $cosmosConfig = $envConfig.cosmosDb
    
    Write-ColorOutput "Initializing Cosmos DB with default data..." "Yellow"
    
    foreach ($collection in $cosmosConfig.collections) {
        if ($collection.defaultData -and $collection.defaultData.Count -gt 0) {
            Write-ColorOutput "Populating collection: $($collection.name)" "Cyan"
            
            foreach ($item in $collection.defaultData) {
                $itemJson = $item | ConvertTo-Json -Compress
                
                $insertCommand = @(
                    "az", "cosmosdb", "sql", "container", "create-update-item"
                    "--account-name", $cosmosConfig.accountName
                    "--database-name", $cosmosConfig.databaseName
                    "--container-name", $collection.name
                    "--body", $itemJson
                    "--subscription", $SubscriptionId
                )
                
                try {
                    & $insertCommand[0] $insertCommand[1..($insertCommand.Length - 1)] | Out-Null
                    Write-ColorOutput "  - Added item with ID: $($item.id)" "Green"
                } catch {
                    Write-ColorOutput "  - Warning: Could not add item with ID: $($item.id) (may already exist)" "Yellow"
                }
            }
        }
    }
}

# Main execution
try {
    Write-ColorOutput "Starting deployment for client '$ClientName' in environment '$Environment'" "Blue"
    
    # Test prerequisites
    Test-Prerequisites
    
    # Set Azure subscription and configure defaults to avoid CLI caching issues
    Write-ColorOutput "Setting Azure subscription and CLI defaults..." "Yellow"
    az account set --subscription $SubscriptionId
    
    # Configure Azure CLI defaults to prevent "content already consumed" error
    az configure --defaults location="$Location"
    
    Write-ColorOutput "✅ Azure CLI configured with defaults" "Green"
    
    # Load configuration
    $config = Get-ClientConfig -ConfigPath $ConfigFile
    
    # Deploy environment
    $deploymentResult = Deploy-ClientEnvironment -Config $config -Client $ClientName -Env $Environment
    
    # Initialize Cosmos DB data
    Initialize-CosmosData -Config $config -Client $ClientName -Env $Environment
    
    Write-ColorOutput "Deployment completed successfully!" "Green"
    Write-ColorOutput "Environment '$Environment' for client '$ClientName' is ready to use." "Green"
    
} catch {
    Write-ColorOutput "Deployment failed: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" "Red"
    exit 1
} 