#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploys infrastructure and initializes SQL Server database for a specific client and environment.

.DESCRIPTION
    This script deploys the complete infrastructure using Bicep templates and initializes
    the SQL Server database with default data for the DevOps lab.

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER SubscriptionId
    Azure subscription ID

.PARAMETER SqlAdminPassword
    SQL Server administrator password (will prompt if not provided)

.PARAMETER ConfigFile
    Path to the clients configuration file (default: "config/clients-sqlserver.json")

.PARAMETER SkipInfrastructure
    Skip infrastructure deployment (only initialize database)

.PARAMETER SkipInitialization
    Skip database initialization (only deploy infrastructure)

.EXAMPLE
    .\Deploy-SqlServer-Environment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id"
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
    [string]$SqlAdminPassword = "",
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "config/clients-sqlserver.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipInfrastructure,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipInitialization
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

# Function to check prerequisites
function Test-Prerequisites {
    Write-ColorOutput "Checking prerequisites..." "Yellow"
    
    # Check Azure CLI
    try {
        az --version | Out-Null
        Write-ColorOutput "✅ Azure CLI is available" "Green"
    }
    catch {
        Write-ColorOutput "❌ Azure CLI not found. Please install Azure CLI." "Red"
        exit 1
    }
    
    # Check Bicep
    try {
        az bicep version | Out-Null
        Write-ColorOutput "✅ Bicep is available" "Green"
    }
    catch {
        Write-ColorOutput "Installing Bicep..." "Yellow"
        az bicep install
        Write-ColorOutput "✅ Bicep installed successfully" "Green"
    }
    
    Write-ColorOutput "Prerequisites check passed" "Green"
}

# Function to set Azure context
function Set-AzureContext {
    param([string]$SubscriptionId)
    
    Write-ColorOutput "Setting Azure subscription and CLI defaults..." "Yellow"
    
    # Set subscription
    az account set --subscription $SubscriptionId
    
    # Set default subscription
    az configure --defaults group= location=
    
    Write-ColorOutput "✅ Azure CLI configured with defaults" "Green"
}

# Function to load client configuration
function Get-ClientConfiguration {
    param([string]$ConfigFile, [string]$ClientName, [string]$Environment)
    
    Write-ColorOutput "Loading client configuration..." "Yellow"
    
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
        
        return $clientConfig
    }
    catch {
        Write-ColorOutput "❌ Error loading configuration: $($_.Exception.Message)" "Red"
        exit 1
    }
}

# Function to deploy infrastructure
function Deploy-Infrastructure {
    param(
        [object]$ClientConfig,
        [string]$ClientName,
        [string]$Environment,
        [string]$SqlAdminPassword
    )
    
    Write-ColorOutput "Deploying infrastructure using Bicep..." "Yellow"
    
    # Generate secure password if not provided
    if ([string]::IsNullOrEmpty($SqlAdminPassword)) {
        $SqlAdminPassword = -join ((33..126) | Get-Random -Count 16 | % {[char]$_})
        Write-ColorOutput "Generated secure password for SQL Server" "Yellow"
    }
    
    # Prepare deployment parameters
    $parameters = @{
        clientName = $ClientName
        environmentName = $Environment
        location = $ClientConfig.location
        resourceGroupName = $ClientConfig.resourceGroup
        sqlServerName = $ClientConfig.sqlServer.serverName
        sqlDatabaseName = $ClientConfig.sqlServer.databaseName
        sqlAdminLogin = $ClientConfig.sqlServer.adminLogin
        sqlAdminPassword = $SqlAdminPassword
        coreFunctions = $ClientConfig.functions.core
        pluginFunctions = $ClientConfig.functions.plugins
        functionMappings = @{
            "UsersFunction" = @{
                "path" = "UsersFunction"
                "type" = "backend"
            }
            "AnimalsFunction" = @{
                "path" = "AnimalsFunction"
                "type" = "backend"
            }
        }
    }
    
    # Create temporary parameters file
    $tempParamsFile = [System.IO.Path]::GetTempFileName() + ".json"
    $parametersForFile = @{
        '$schema' = "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#"
        contentVersion = "1.0.0.0"
        parameters = @{}
    }
    
    foreach ($key in $parameters.Keys) {
        $parametersForFile.parameters[$key] = @{ value = $parameters[$key] }
    }
    
    $parametersForFile | ConvertTo-Json -Depth 10 | Out-File $tempParamsFile
    
    Write-ColorOutput "Created temporary parameters file: $tempParamsFile" "Gray"
    Write-ColorOutput "Parameters file content:" "Gray"
    Get-Content $tempParamsFile | Write-Host
    
    try {
        # Deploy using Bicep
        $deploymentName = "deployment-$ClientName-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"
        
        Write-ColorOutput "Starting Bicep deployment..." "Yellow"
        az deployment sub create `
            --name $deploymentName `
            --location $ClientConfig.location `
            --template-file "infrastructure/bicep/main-sqlserver.bicep" `
            --parameters "@$tempParamsFile"
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✅ Infrastructure deployment completed successfully!" "Green"
        } else {
            throw "Bicep deployment failed"
        }
        
        # Get deployment outputs
        $outputs = az deployment sub show --name $deploymentName --query properties.outputs --output json | ConvertFrom-Json
        
        Write-ColorOutput "Deployment outputs:" "Cyan"
        $outputs | ConvertTo-Json -Depth 3 | Write-Host
        
        return @{
            SqlAdminPassword = $SqlAdminPassword
            Outputs = $outputs
        }
    }
    catch {
        Write-ColorOutput "❌ Infrastructure deployment failed: $($_.Exception.Message)" "Red"
        throw
    }
    finally {
        # Clean up temporary file
        if (Test-Path $tempParamsFile) {
            Remove-Item $tempParamsFile -Force
            Write-ColorOutput "Cleaned up temporary parameters file" "Gray"
        }
    }
}

# Main execution
try {
    Write-ColorOutput "🚀 Starting SQL Server deployment for client '$ClientName' in environment '$Environment'" "Yellow"
    
    # Check prerequisites
    if (-not $SkipInfrastructure) {
        Test-Prerequisites
        Set-AzureContext -SubscriptionId $SubscriptionId
    }
    
    # Load configuration
    $clientConfig = Get-ClientConfiguration -ConfigFile $ConfigFile -ClientName $ClientName -Environment $Environment
    
    Write-ColorOutput "Deploying environment '$Environment' for client '$ClientName'..." "Yellow"
    Write-ColorOutput "Configuration loaded:" "Cyan"
    $clientConfig | ConvertTo-Json -Depth 3 | Write-Host
    
    # Deploy infrastructure
    $deploymentResult = $null
    if (-not $SkipInfrastructure) {
        $deploymentResult = Deploy-Infrastructure -ClientConfig $clientConfig -ClientName $ClientName -Environment $Environment -SqlAdminPassword $SqlAdminPassword
        $SqlAdminPassword = $deploymentResult.SqlAdminPassword
    }
    
    # Initialize database
    if (-not $SkipInitialization) {
        Write-ColorOutput "Initializing SQL Server database..." "Yellow"
        
        # Wait for SQL Server to be ready
        Write-ColorOutput "⏳ Waiting for SQL Server to be fully ready..." "Yellow"
        Start-Sleep -Seconds 60
        
        # Run database initialization
        $initParams = @{
            ClientName = $ClientName
            Environment = $Environment
            ConfigPath = $ConfigFile
        }
        
        if (-not [string]::IsNullOrEmpty($SqlAdminPassword)) {
            $initParams.SqlAdminPassword = $SqlAdminPassword
        }
        
        & "scripts/Initialize-SqlDatabase.ps1" @initParams
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✅ Database initialization completed successfully!" "Green"
        } else {
            Write-ColorOutput "❌ Database initialization failed!" "Red"
            exit 1
        }
    }
    
    # Summary
    Write-ColorOutput "`n📊 Deployment Summary:" "Cyan"
    Write-ColorOutput "  🏢 Client: $ClientName" "White"
    Write-ColorOutput "  🌍 Environment: $Environment" "White"
    Write-ColorOutput "  📦 Resource Group: $($clientConfig.resourceGroup)" "White"
    Write-ColorOutput "  🗄️ SQL Server: $($clientConfig.sqlServer.serverName)" "White"
    Write-ColorOutput "  💾 Database: $($clientConfig.sqlServer.databaseName)" "White"
    
    if ($deploymentResult -and $deploymentResult.Outputs) {
        Write-ColorOutput "  📋 Deployment Outputs:" "White"
        $deploymentResult.Outputs | ConvertTo-Json -Depth 2 | Write-Host
    }
    
    Write-ColorOutput "`n🎉 Deployment completed successfully!" "Green"
    Write-ColorOutput "Environment '$Environment' for client '$ClientName' is ready to use." "Green"
    
} catch {
    Write-ColorOutput "❌ Deployment failed: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack trace:" "Red"
    Write-ColorOutput $_.Exception.StackTrace "Red"
    exit 1
}
