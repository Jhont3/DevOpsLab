#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Post-deployment verification script for GitHub Actions.

.DESCRIPTION
    This script provides a comprehensive verification of the deployed infrastructure
    and data after a GitHub Actions deployment. It generates a detailed report
    that can be used to confirm successful deployment.

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER ConfigFile
    Path to the clients configuration file (default: "config/clients.json")

.PARAMETER OutputFormat
    Output format: "console" or "json" (default: "console")

.EXAMPLE
    .\Verify-Deployment.ps1 -ClientName "elite" -Environment "main"
    
.EXAMPLE
    .\Verify-Deployment.ps1 -ClientName "elite" -Environment "main" -OutputFormat "json"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "config/clients.json",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("console", "json")]
    [string]$OutputFormat = "console"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output (only in console mode)
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    if ($OutputFormat -eq "console") {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Function to test resource existence
function Test-AzureResource {
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
                id = $resourceObj.id
            }
        } else {
            return @{
                exists = $false
                status = "Not Found"
                location = ""
                id = ""
            }
        }
    } catch {
        return @{
            exists = $false
            status = "Error"
            location = ""
            id = ""
            error = $_.Exception.Message
        }
    }
}

# Function to test Cosmos DB data
function Test-CosmosData {
    param(
        [string]$AccountName,
        [string]$DatabaseName,
        [string]$ContainerName,
        [array]$ExpectedItems
    )
    
    try {
        $query = "SELECT c.id FROM c"
        $result = az cosmosdb sql query --account-name $AccountName --database-name $DatabaseName --container-name $ContainerName --query-text $query --output json 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $result) {
            $actualItems = ($result | ConvertFrom-Json) | ForEach-Object { $_.id }
            $foundItems = @()
            $missingItems = @()
            
            foreach ($expected in $ExpectedItems) {
                if ($actualItems -contains $expected) {
                    $foundItems += $expected
                } else {
                    $missingItems += $expected
                }
            }
            
            return @{
                success = $missingItems.Count -eq 0
                totalFound = $actualItems.Count
                expectedFound = $foundItems.Count
                expectedMissing = $missingItems.Count
                foundItems = $foundItems
                missingItems = $missingItems
                allItems = $actualItems
            }
        } else {
            return @{
                success = $false
                error = "Unable to query container"
                totalFound = 0
                expectedFound = 0
                expectedMissing = $ExpectedItems.Count
                foundItems = @()
                missingItems = $ExpectedItems
                allItems = @()
            }
        }
    } catch {
        return @{
            success = $false
            error = $_.Exception.Message
            totalFound = 0
            expectedFound = 0
            expectedMissing = $ExpectedItems.Count
            foundItems = @()
            missingItems = $ExpectedItems
            allItems = @()
        }
    }
}

# Main verification process
$startTime = Get-Date
$verificationResults = @{
    client = $ClientName
    environment = $Environment
    timestamp = $startTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    location = ""
    resources = @{}
    cosmosData = @{}
    summary = @{
        totalResources = 0
        successfulResources = 0
        failedResources = 0
        dataValidation = $false
        overallSuccess = $false
    }
    duration = ""
}

Write-ColorOutput "🔍 Starting deployment verification..." "Yellow"
Write-ColorOutput "   🏢 Client: $ClientName" "Gray"
Write-ColorOutput "   🌍 Environment: $Environment" "Gray"

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
    $location = $clientConfig.location
    
    $verificationResults.location = $location
    
    Write-ColorOutput "   📦 Resource Group: $resourceGroupName" "Gray"
    Write-ColorOutput "   🔗 Cosmos Account: $accountName" "Gray"
    Write-ColorOutput "   🗄️  Database: $databaseName" "Gray"
    Write-ColorOutput "   📍 Location: $location" "Gray"
    
    # Test Resource Group
    Write-ColorOutput "`n🔍 Verifying Resource Group..." "Yellow"
    $rgTest = Test-AzureResource -ResourceGroupName $resourceGroupName -ResourceName $resourceGroupName -ResourceType "Microsoft.Resources/resourceGroups"
    $verificationResults.resources.resourceGroup = $rgTest
    
    if ($rgTest.exists) {
        Write-ColorOutput "   ✅ Resource Group exists and is $($rgTest.status)" "Green"
    } else {
        Write-ColorOutput "   ❌ Resource Group not found" "Red"
    }
    
    # Test Cosmos DB Account
    Write-ColorOutput "`n🔍 Verifying Cosmos DB Account..." "Yellow"
    $cosmosTest = Test-AzureResource -ResourceGroupName $resourceGroupName -ResourceName $accountName -ResourceType "Microsoft.DocumentDB/databaseAccounts"
    $verificationResults.resources.cosmosAccount = $cosmosTest
    
    if ($cosmosTest.exists) {
        Write-ColorOutput "   ✅ Cosmos DB Account exists and is $($cosmosTest.status)" "Green"
    } else {
        Write-ColorOutput "   ❌ Cosmos DB Account not found" "Red"
    }
    
    # Test Storage Account
    Write-ColorOutput "`n🔍 Verifying Storage Account..." "Yellow"
    $storageAccountName = "stwitag$($ClientName)$($Environment)"
    $storageTest = Test-AzureResource -ResourceGroupName $resourceGroupName -ResourceName $storageAccountName -ResourceType "Microsoft.Storage/storageAccounts"
    $verificationResults.resources.storageAccount = $storageTest
    
    if ($storageTest.exists) {
        Write-ColorOutput "   ✅ Storage Account exists and is $($storageTest.status)" "Green"
    } else {
        Write-ColorOutput "   ❌ Storage Account not found" "Red"
    }
    
    # Test App Service Plan
    Write-ColorOutput "`n🔍 Verifying App Service Plan..." "Yellow"
    $appServicePlanName = "asp-witag-$ClientName-$Environment"
    $aspTest = Test-AzureResource -ResourceGroupName $resourceGroupName -ResourceName $appServicePlanName -ResourceType "Microsoft.Web/serverfarms"
    $verificationResults.resources.appServicePlan = $aspTest
    
    if ($aspTest.exists) {
        Write-ColorOutput "   ✅ App Service Plan exists and is $($aspTest.status)" "Green"
    } else {
        Write-ColorOutput "   ❌ App Service Plan not found" "Red"
    }
    
    # Test Function Apps
    Write-ColorOutput "`n🔍 Verifying Function Apps..." "Yellow"
    $coreFunctions = $clientConfig.functions.core
    $functionResults = @{}
    
    foreach ($functionName in $coreFunctions) {
        $functionAppName = "$functionName-$ClientName-$Environment"
        $functionTest = Test-AzureResource -ResourceGroupName $resourceGroupName -ResourceName $functionAppName -ResourceType "Microsoft.Web/sites"
        $functionResults[$functionName] = $functionTest
        
        if ($functionTest.exists) {
            Write-ColorOutput "   ✅ Function App $functionName exists and is $($functionTest.status)" "Green"
        } else {
            Write-ColorOutput "   ❌ Function App $functionName not found" "Red"
        }
    }
    
    $verificationResults.resources.functionApps = $functionResults
    
    # Test Cosmos DB Data
    if ($cosmosTest.exists -and $cosmosTest.status -eq "Succeeded") {
        Write-ColorOutput "`n🔍 Verifying Cosmos DB Data..." "Yellow"
        
        # Test usuarios data
        $expectedUsuarios = @("usuario1", "usuario2", "usuario3")
        $usuariosTest = Test-CosmosData -AccountName $accountName -DatabaseName $databaseName -ContainerName "usuarios" -ExpectedItems $expectedUsuarios
        $verificationResults.cosmosData.usuarios = $usuariosTest
        
        if ($usuariosTest.success) {
            Write-ColorOutput "   ✅ usuarios collection: $($usuariosTest.expectedFound)/$($expectedUsuarios.Count) expected items found" "Green"
        } else {
            Write-ColorOutput "   ❌ usuarios collection: $($usuariosTest.expectedMissing) items missing" "Red"
        }
        
        # Test animales data
        $expectedAnimales = @("perro", "gato", "raton")
        $animalesTest = Test-CosmosData -AccountName $accountName -DatabaseName $databaseName -ContainerName "animales" -ExpectedItems $expectedAnimales
        $verificationResults.cosmosData.animales = $animalesTest
        
        if ($animalesTest.success) {
            Write-ColorOutput "   ✅ animales collection: $($animalesTest.expectedFound)/$($expectedAnimales.Count) expected items found" "Green"
        } else {
            Write-ColorOutput "   ❌ animales collection: $($animalesTest.expectedMissing) items missing" "Red"
        }
        
        $verificationResults.summary.dataValidation = $usuariosTest.success -and $animalesTest.success
    } else {
        Write-ColorOutput "`n⏭️  Skipping Cosmos DB data verification (account not ready)" "Yellow"
    }
    
    # Calculate summary
    $allResources = @($rgTest, $cosmosTest, $storageTest, $aspTest) + $functionResults.Values
    $successfulResources = ($allResources | Where-Object { $_.exists -and $_.status -eq "Succeeded" }).Count
    $totalResources = $allResources.Count
    
    $verificationResults.summary.totalResources = $totalResources
    $verificationResults.summary.successfulResources = $successfulResources
    $verificationResults.summary.failedResources = $totalResources - $successfulResources
    $verificationResults.summary.overallSuccess = ($successfulResources -eq $totalResources) -and $verificationResults.summary.dataValidation
    
    # Calculate duration
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $verificationResults.duration = "$($duration.Minutes)m $($duration.Seconds)s"
    
    # Output results
    if ($OutputFormat -eq "json") {
        $verificationResults | ConvertTo-Json -Depth 10
    } else {
        # Console summary
        Write-ColorOutput "`n📊 Verification Summary:" "Cyan"
        Write-ColorOutput "   ⏱️  Duration: $($verificationResults.duration)" "Gray"
        Write-ColorOutput "   📦 Resources: $successfulResources/$totalResources successful" "Gray"
        Write-ColorOutput "   🗄️  Data: $(if ($verificationResults.summary.dataValidation) { "✅ Valid" } else { "❌ Invalid" })" "Gray"
        
        if ($verificationResults.summary.overallSuccess) {
            Write-ColorOutput "`n🎉 Deployment verification PASSED!" "Green"
            Write-ColorOutput "   All resources are deployed and data is initialized correctly." "Green"
        } else {
            Write-ColorOutput "`n❌ Deployment verification FAILED!" "Red"
            Write-ColorOutput "   Some resources or data validation failed." "Red"
            exit 1
        }
    }
    
} catch {
    Write-ColorOutput "❌ Error during verification: $_" "Red"
    exit 1
}

if ($OutputFormat -eq "console") {
    Write-ColorOutput "`n✅ Verification completed!" "Green"
}
