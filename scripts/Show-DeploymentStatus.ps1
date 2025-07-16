#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Show deployment status and resource summary for all clients and environments.

.DESCRIPTION
    This script provides a comprehensive overview of all deployed resources
    across all clients and environments. It's useful for getting a quick
    status check of the entire infrastructure.

.PARAMETER ConfigFile
    Path to the clients configuration file (default: "config/clients.json")

.PARAMETER OutputFormat
    Output format: "table", "json", or "detailed" (default: "table")

.PARAMETER Client
    Filter by specific client (optional)

.PARAMETER Environment
    Filter by specific environment (optional)

.EXAMPLE
    .\Show-DeploymentStatus.ps1
    
.EXAMPLE
    .\Show-DeploymentStatus.ps1 -Client "elite" -Environment "main"
    
.EXAMPLE
    .\Show-DeploymentStatus.ps1 -OutputFormat "json"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "config/clients.json",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("table", "json", "detailed")]
    [string]$OutputFormat = "table",
    
    [Parameter(Mandatory = $false)]
    [string]$Client = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = ""
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    if ($OutputFormat -ne "json") {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Function to get resource status
function Get-ResourceStatus {
    param(
        [string]$ResourceGroupName,
        [string]$ResourceName,
        [string]$ResourceType
    )
    
    try {
        $resource = az resource show --resource-group $ResourceGroupName --name $ResourceName --resource-type $ResourceType --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $resource) {
            $resourceObj = $resource | ConvertFrom-Json
            return @{
                exists = $true
                status = $resourceObj.properties.provisioningState
                location = $resourceObj.location
                sku = $resourceObj.sku
                kind = $resourceObj.kind
            }
        } else {
            return @{
                exists = $false
                status = "Not Found"
                location = ""
                sku = $null
                kind = $null
            }
        }
    } catch {
        return @{
            exists = $false
            status = "Error"
            location = ""
            sku = $null
            kind = $null
        }
    }
}

# Function to get Cosmos DB containers
function Get-CosmosContainers {
    param(
        [string]$AccountName,
        [string]$DatabaseName
    )
    
    try {
        $containers = az cosmosdb sql container list --account-name $AccountName --database-name $DatabaseName --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $containers) {
            $containerObjs = $containers | ConvertFrom-Json
            return $containerObjs | ForEach-Object { 
                @{
                    name = $_.name
                    throughput = $_.resource.throughput
                    partitionKey = $_.resource.partitionKey.paths[0]
                }
            }
        }
    } catch {
        return @()
    }
    return @()
}

# Function to get status emoji
function Get-StatusEmoji {
    param([string]$Status, [bool]$Exists)
    
    if (-not $Exists) {
        return "❌"
    }
    
    switch ($Status) {
        "Succeeded" { return "✅" }
        "Failed" { return "❌" }
        "Running" { return "🔄" }
        "Updating" { return "⚠️" }
        default { return "❓" }
    }
}

# Main process
$statusData = @{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    clients = @{}
    summary = @{
        totalClients = 0
        totalEnvironments = 0
        totalResources = 0
        healthyResources = 0
        unhealthyResources = 0
    }
}

Write-ColorOutput "📊 DevOps Lab Deployment Status" "Yellow"
Write-ColorOutput "===============================" "Yellow"

# Load configuration
if (-not (Test-Path $ConfigFile)) {
    Write-ColorOutput "❌ Configuration file not found: $ConfigFile" "Red"
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json

# Filter clients if specified
$clientsToProcess = if ($Client) { @($Client) } else { $config.clients.PSObject.Properties.Name }
$environmentsToProcess = if ($Environment) { @($Environment) } else { @("testing", "main") }

foreach ($clientName in $clientsToProcess) {
    $clientConfig = $config.clients.$clientName
    if (-not $clientConfig) {
        Write-ColorOutput "⚠️  Client '$clientName' not found in configuration" "Yellow"
        continue
    }
    
    $statusData.clients[$clientName] = @{
        environments = @{}
    }
    
    foreach ($envName in $environmentsToProcess) {
        $envConfig = $clientConfig.environments.$envName
        if (-not $envConfig) {
            continue
        }
        
        $statusData.summary.totalEnvironments++
        
        Write-ColorOutput "`n🏢 Client: $clientName | 🌍 Environment: $envName" "Cyan"
        
        $resourceGroupName = $envConfig.resourceGroup
        $accountName = $envConfig.cosmosDb.accountName
        $databaseName = $envConfig.cosmosDb.databaseName
        
        $envStatus = @{
            resourceGroup = $resourceGroupName
            location = $envConfig.location
            resources = @{}
            cosmosContainers = @()
            summary = @{
                totalResources = 0
                healthyResources = 0
                unhealthyResources = 0
            }
        }
        
        # Check Resource Group
        $rgStatus = Get-ResourceStatus -ResourceGroupName $resourceGroupName -ResourceName $resourceGroupName -ResourceType "Microsoft.Resources/resourceGroups"
        $envStatus.resources.resourceGroup = $rgStatus
        $envStatus.summary.totalResources++
        if ($rgStatus.exists -and $rgStatus.status -eq "Succeeded") {
            $envStatus.summary.healthyResources++
        } else {
            $envStatus.summary.unhealthyResources++
        }
        
        if ($OutputFormat -eq "detailed") {
            $emoji = Get-StatusEmoji -Status $rgStatus.status -Exists $rgStatus.exists
            Write-ColorOutput "   $emoji Resource Group: $resourceGroupName ($($rgStatus.status))" "Gray"
        }
        
        # Check Cosmos DB Account
        $cosmosStatus = Get-ResourceStatus -ResourceGroupName $resourceGroupName -ResourceName $accountName -ResourceType "Microsoft.DocumentDB/databaseAccounts"
        $envStatus.resources.cosmosAccount = $cosmosStatus
        $envStatus.summary.totalResources++
        if ($cosmosStatus.exists -and $cosmosStatus.status -eq "Succeeded") {
            $envStatus.summary.healthyResources++
            
            # Get containers if Cosmos DB is healthy
            $containers = Get-CosmosContainers -AccountName $accountName -DatabaseName $databaseName
            $envStatus.cosmosContainers = $containers
        } else {
            $envStatus.summary.unhealthyResources++
        }
        
        if ($OutputFormat -eq "detailed") {
            $emoji = Get-StatusEmoji -Status $cosmosStatus.status -Exists $cosmosStatus.exists
            Write-ColorOutput "   $emoji Cosmos DB: $accountName ($($cosmosStatus.status))" "Gray"
            
            if ($containers.Count -gt 0) {
                Write-ColorOutput "      📦 Containers: $($containers.Count)" "Gray"
                foreach ($container in $containers) {
                    Write-ColorOutput "         • $($container.name)" "Gray"
                }
            }
        }
        
        # Check Storage Account
        $storageAccountName = "stwitag$($clientName)$($envName)"
        $storageStatus = Get-ResourceStatus -ResourceGroupName $resourceGroupName -ResourceName $storageAccountName -ResourceType "Microsoft.Storage/storageAccounts"
        $envStatus.resources.storageAccount = $storageStatus
        $envStatus.summary.totalResources++
        if ($storageStatus.exists -and $storageStatus.status -eq "Succeeded") {
            $envStatus.summary.healthyResources++
        } else {
            $envStatus.summary.unhealthyResources++
        }
        
        if ($OutputFormat -eq "detailed") {
            $emoji = Get-StatusEmoji -Status $storageStatus.status -Exists $storageStatus.exists
            Write-ColorOutput "   $emoji Storage Account: $storageAccountName ($($storageStatus.status))" "Gray"
        }
        
        # Check App Service Plan
        $appServicePlanName = "asp-witag-$clientName-$envName"
        $aspStatus = Get-ResourceStatus -ResourceGroupName $resourceGroupName -ResourceName $appServicePlanName -ResourceType "Microsoft.Web/serverfarms"
        $envStatus.resources.appServicePlan = $aspStatus
        $envStatus.summary.totalResources++
        if ($aspStatus.exists -and $aspStatus.status -eq "Succeeded") {
            $envStatus.summary.healthyResources++
        } else {
            $envStatus.summary.unhealthyResources++
        }
        
        if ($OutputFormat -eq "detailed") {
            $emoji = Get-StatusEmoji -Status $aspStatus.status -Exists $aspStatus.exists
            Write-ColorOutput "   $emoji App Service Plan: $appServicePlanName ($($aspStatus.status))" "Gray"
        }
        
        # Check Function Apps
        $functionApps = @{}
        foreach ($functionName in $envConfig.functions.core) {
            $functionAppName = "$functionName-$clientName-$envName"
            $functionStatus = Get-ResourceStatus -ResourceGroupName $resourceGroupName -ResourceName $functionAppName -ResourceType "Microsoft.Web/sites"
            $functionApps[$functionName] = $functionStatus
            $envStatus.summary.totalResources++
            if ($functionStatus.exists -and $functionStatus.status -eq "Succeeded") {
                $envStatus.summary.healthyResources++
            } else {
                $envStatus.summary.unhealthyResources++
            }
            
            if ($OutputFormat -eq "detailed") {
                $emoji = Get-StatusEmoji -Status $functionStatus.status -Exists $functionStatus.exists
                Write-ColorOutput "   $emoji Function App: $functionAppName ($($functionStatus.status))" "Gray"
            }
        }
        $envStatus.resources.functionApps = $functionApps
        
        # Update global summary
        $statusData.summary.totalResources += $envStatus.summary.totalResources
        $statusData.summary.healthyResources += $envStatus.summary.healthyResources
        $statusData.summary.unhealthyResources += $envStatus.summary.unhealthyResources
        
        $statusData.clients[$clientName].environments[$envName] = $envStatus
        
        if ($OutputFormat -eq "table") {
            $healthPercent = if ($envStatus.summary.totalResources -gt 0) { 
                [math]::Round(($envStatus.summary.healthyResources / $envStatus.summary.totalResources) * 100, 1)
            } else { 0 }
            
            $healthEmoji = if ($healthPercent -eq 100) { "✅" } elseif ($healthPercent -ge 80) { "⚠️" } else { "❌" }
            Write-ColorOutput "   $healthEmoji $($envStatus.summary.healthyResources)/$($envStatus.summary.totalResources) resources healthy ($healthPercent%)" "White"
        }
    }
    
    $statusData.summary.totalClients++
}

# Output results
if ($OutputFormat -eq "json") {
    $statusData | ConvertTo-Json -Depth 10
} else {
    # Summary
    Write-ColorOutput "`n📈 Overall Summary:" "Yellow"
    Write-ColorOutput "   🏢 Clients: $($statusData.summary.totalClients)" "Gray"
    Write-ColorOutput "   🌍 Environments: $($statusData.summary.totalEnvironments)" "Gray"
    Write-ColorOutput "   📦 Total Resources: $($statusData.summary.totalResources)" "Gray"
    Write-ColorOutput "   ✅ Healthy: $($statusData.summary.healthyResources)" "Green"
    Write-ColorOutput "   ❌ Unhealthy: $($statusData.summary.unhealthyResources)" "Red"
    
    if ($statusData.summary.totalResources -gt 0) {
        $overallHealth = [math]::Round(($statusData.summary.healthyResources / $statusData.summary.totalResources) * 100, 1)
        Write-ColorOutput "   📊 Overall Health: $overallHealth%" "White"
    }
    
    # Quick actions
    Write-ColorOutput "`n💡 Quick Actions:" "Cyan"
    Write-ColorOutput "   🔍 Monitor deployment: .\scripts\Monitor-Deployment.ps1" "Gray"
    Write-ColorOutput "   ✅ Verify deployment: .\scripts\Verify-Deployment.ps1 -ClientName <client> -Environment <env>" "Gray"
    Write-ColorOutput "   🚀 Deploy: .\scripts\Complete-Deployment.ps1 -ClientName <client> -Environment <env>" "Gray"
    
    Write-ColorOutput "`n✅ Status report completed!" "Green"
}
