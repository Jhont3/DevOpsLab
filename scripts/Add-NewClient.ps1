#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Adds a new client to the configuration and optionally deploys their environment.

.DESCRIPTION
    This script adds a new client to the clients.json configuration file and
    optionally deploys their testing and/or production environments.

.PARAMETER ClientName
    The name of the new client (e.g., "colflores")

.PARAMETER DisplayName
    The display name for the client (e.g., "Colflores Client")

.PARAMETER Environment
    The environment to deploy ("testing", "main", or "both")

.PARAMETER SubscriptionId
    Azure subscription ID (required if deploying)

.PARAMETER Location
    Azure region for deployment (default: "East US")

.PARAMETER ConfigFile
Path to the clients configuration file (default: "../config/clients.json")

.PARAMETER PluginFunctions
    Array of plugin functions to add to the client

.PARAMETER DeployNow
    Switch to deploy the environment immediately after adding the client

.EXAMPLE
    .\Add-NewClient.ps1 -ClientName "colflores" -DisplayName "Colflores Client" -Environment "testing" -DeployNow -SubscriptionId "your-subscription-id"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientName,

    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [Parameter(Mandatory = $false)]
    [ValidateSet("testing", "main", "both")]
    [string]$Environment = "testing",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$Location = "East US",

    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "../config/clients.json",

    [Parameter(Mandatory = $false)]
    [string[]]$PluginFunctions = @(),

    [Parameter(Mandatory = $false)]
    [switch]$DeployNow
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

# Function to validate client name
function Test-ClientName {
    param([string]$Name)
    
    if ($Name -notmatch '^[a-z][a-z0-9]*$') {
        throw "Client name must start with a letter and contain only lowercase letters and numbers"
    }
    
    if ($Name.Length -gt 15) {
        throw "Client name must be 15 characters or less"
    }
}

# Function to create client configuration
function New-ClientConfiguration {
    param(
        [string]$Name,
        [string]$Display,
        [string]$Loc,
        [string[]]$Plugins
    )
    
    $clientConfig = @{
        displayName = $Display
        environments = @{
            testing = @{
                resourceGroup = "rg-witag-$Name-testing"
                location = $Loc
                cosmosDb = @{
                    accountName = "cosmos-witag-$Name-testing"
                    databaseName = "witag-db"
                    collections = @(
                        @{
                            name = "usuarios"
                            partitionKey = "/id"
                            defaultData = @(
                                @{id = "1"; nombre = "usuario1"; email = "usuario1@$Name.com"},
                                @{id = "2"; nombre = "usuario2"; email = "usuario2@$Name.com"},
                                @{id = "3"; nombre = "usuario3"; email = "usuario3@$Name.com"}
                            )
                        },
                        @{
                            name = "animales"
                            partitionKey = "/id"
                            defaultData = @(
                                @{id = "1"; nombre = "perro"; tipo = "mamifero"},
                                @{id = "2"; nombre = "gato"; tipo = "mamifero"},
                                @{id = "3"; nombre = "ratón"; tipo = "mamifero"}
                            )
                        }
                    )
                }
                functions = @{
                    core = @("functionUsuarios", "functionAnimales")
                    plugins = $Plugins
                }
            }
            main = @{
                resourceGroup = "rg-witag-$Name-main"
                location = $Loc
                cosmosDb = @{
                    accountName = "cosmos-witag-$Name-main"
                    databaseName = "witag-db"
                    collections = @(
                        @{
                            name = "usuarios"
                            partitionKey = "/id"
                            defaultData = @(
                                @{id = "1"; nombre = "usuario1"; email = "usuario1@$Name.com"},
                                @{id = "2"; nombre = "usuario2"; email = "usuario2@$Name.com"},
                                @{id = "3"; nombre = "usuario3"; email = "usuario3@$Name.com"}
                            )
                        },
                        @{
                            name = "animales"
                            partitionKey = "/id"
                            defaultData = @(
                                @{id = "1"; nombre = "perro"; tipo = "mamifero"},
                                @{id = "2"; nombre = "gato"; tipo = "mamifero"},
                                @{id = "3"; nombre = "ratón"; tipo = "mamifero"}
                            )
                        }
                    )
                }
                functions = @{
                    core = @("functionUsuarios", "functionAnimales")
                    plugins = $Plugins
                }
            }
        }
    }
    
    return $clientConfig
}

# Function to add client to configuration
function Add-ClientToConfig {
    param(
        [string]$ConfigPath,
        [string]$Name,
        [object]$ClientConfig
    )
    
    Write-ColorOutput "Adding client '$Name' to configuration..." "Yellow"
    
    # Load existing configuration
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    
    # Check if client already exists
    if ($config.clients.$Name) {
        throw "Client '$Name' already exists in configuration"
    }
    
    # Add new client
    $config.clients | Add-Member -NotePropertyName $Name -NotePropertyValue $ClientConfig
    
    # Save updated configuration
    $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath -Encoding UTF8
    
    Write-ColorOutput "Client '$Name' added to configuration successfully!" "Green"
}

# Function to deploy client environment
function Deploy-ClientEnvironment {
    param(
        [string]$Name,
        [string]$Env,
        [string]$SubId
    )
    
    Write-ColorOutput "Deploying environment '$Env' for client '$Name'..." "Yellow"
    
    $deployScript = Join-Path $PSScriptRoot "Deploy-Environment.ps1"
    
    if (-not (Test-Path $deployScript)) {
        throw "Deployment script not found: $deployScript"
    }
    
    & $deployScript -ClientName $Name -Environment $Env -SubscriptionId $SubId -Location $Location
    
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed for client '$Name' environment '$Env'"
    }
}

# Main execution
try {
    Write-ColorOutput "Adding new client '$ClientName'..." "Blue"
    
    # Validate client name
    Test-ClientName -Name $ClientName
    
    # Create client configuration
    $clientConfig = New-ClientConfiguration -Name $ClientName -Display $DisplayName -Loc $Location -Plugins $PluginFunctions
    
    # Add client to configuration
    Add-ClientToConfig -ConfigPath $ConfigFile -Name $ClientName -ClientConfig $clientConfig
    
    # Deploy environment if requested
    if ($DeployNow) {
        if (-not $SubscriptionId) {
            throw "SubscriptionId is required when DeployNow is specified"
        }
        
        Write-ColorOutput "Deploying environments..." "Yellow"
        
        switch ($Environment) {
            "testing" {
                Deploy-ClientEnvironment -Name $ClientName -Env "testing" -SubId $SubscriptionId
            }
            "main" {
                Deploy-ClientEnvironment -Name $ClientName -Env "main" -SubId $SubscriptionId
            }
            "both" {
                Deploy-ClientEnvironment -Name $ClientName -Env "testing" -SubId $SubscriptionId
                Deploy-ClientEnvironment -Name $ClientName -Env "main" -SubId $SubscriptionId
            }
        }
    }
    
    Write-ColorOutput "Client '$ClientName' added successfully!" "Green"
    
    if ($DeployNow) {
        Write-ColorOutput "Environment(s) deployed successfully!" "Green"
    } else {
        Write-ColorOutput "To deploy the environment, run:" "Cyan"
        Write-ColorOutput "  .\Deploy-Environment.ps1 -ClientName '$ClientName' -Environment '$Environment' -SubscriptionId 'your-subscription-id'" "Gray"
    }
    
} catch {
    Write-ColorOutput "Failed to add client: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" "Red"
    exit 1
} 