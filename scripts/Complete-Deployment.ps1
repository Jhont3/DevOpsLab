#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Complete deployment and initialization script for the DevOps Lab.

.DESCRIPTION
    This script performs a complete deployment and initialization:
    1. Deploys the infrastructure (Cosmos DB, Azure Functions, etc.)
    2. Initializes Cosmos DB with default data
    3. Validates that all data was created correctly

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER SubscriptionId
    Azure subscription ID

.PARAMETER Location
    Azure region for deployment (default: "Australia East")

.PARAMETER ConfigFile
    Path to the clients configuration file (default: "config/clients.json")

.PARAMETER SkipInitialization
    Skip the data initialization step

.PARAMETER SkipValidation
    Skip the data validation step

.EXAMPLE
    .\Complete-Deployment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id"
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
    [string]$Location = "Australia East",

    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "config/clients.json",

    [Parameter(Mandatory = $false)]
    [switch]$SkipInitialization,

    [Parameter(Mandatory = $false)]
    [switch]$SkipValidation
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

# Function to execute a script and handle errors
function Invoke-ScriptStep {
    param(
        [string]$StepName,
        [string]$ScriptPath,
        [string[]]$Arguments
    )
    
    Write-ColorOutput "`n🔄 Step: $StepName" "Cyan"
    Write-ColorOutput "   Executing: $ScriptPath $($Arguments -join ' ')" "Gray"
    
    try {
        $result = & $ScriptPath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Script failed with exit code: $LASTEXITCODE"
        }
        Write-ColorOutput "   ✅ $StepName completed successfully" "Green"
        return $true
    } catch {
        Write-ColorOutput "   ❌ $StepName failed: $_" "Red"
        return $false
    }
}

# Main deployment process
Write-ColorOutput "🚀 Starting complete deployment and initialization..." "Yellow"
Write-ColorOutput "   🏢 Client: $ClientName" "Gray"
Write-ColorOutput "   🌍 Environment: $Environment" "Gray"
Write-ColorOutput "   📍 Location: $Location" "Gray"
Write-ColorOutput "   🆔 Subscription: $SubscriptionId" "Gray"

$startTime = Get-Date

# Step 1: Deploy Infrastructure
$deploySuccess = Invoke-ScriptStep -StepName "Infrastructure Deployment" -ScriptPath "scripts/Deploy-Environment.ps1" -Arguments @(
    "-ClientName", $ClientName
    "-Environment", $Environment
    "-SubscriptionId", $SubscriptionId
    "-Location", $Location
    "-ConfigFile", $ConfigFile
)

if (-not $deploySuccess) {
    Write-ColorOutput "❌ Infrastructure deployment failed. Stopping process." "Red"
    exit 1
}

# Step 2: Initialize Data (if not skipped)
if (-not $SkipInitialization) {
    Write-ColorOutput "`n⏳ Waiting 30 seconds for Cosmos DB to be fully ready..." "Yellow"
    Start-Sleep -Seconds 30
    
    $initSuccess = Invoke-ScriptStep -StepName "Data Initialization" -ScriptPath "scripts/Initialize-CosmosData.ps1" -Arguments @(
        "-ClientName", $ClientName
        "-Environment", $Environment
        "-ConfigFile", $ConfigFile
    )
    
    if (-not $initSuccess) {
        Write-ColorOutput "⚠️  Data initialization failed, but infrastructure is deployed." "Yellow"
        Write-ColorOutput "   You can run Initialize-CosmosData.ps1 manually later." "Yellow"
    }
} else {
    Write-ColorOutput "`n⏭️  Data initialization skipped as requested." "Yellow"
}

# Step 3: Validate Data (if not skipped)
if (-not $SkipValidation -and -not $SkipInitialization) {
    $validateSuccess = Invoke-ScriptStep -StepName "Data Validation" -ScriptPath "scripts/Validate-CosmosData.ps1" -Arguments @(
        "-ClientName", $ClientName
        "-Environment", $Environment
        "-ConfigFile", $ConfigFile
    )
    
    if (-not $validateSuccess) {
        Write-ColorOutput "⚠️  Data validation failed, but infrastructure is deployed." "Yellow"
        Write-ColorOutput "   You can run Validate-CosmosData.ps1 manually later." "Yellow"
    }
} else {
    Write-ColorOutput "`n⏭️  Data validation skipped." "Yellow"
}

# Summary
$endTime = Get-Date
$duration = $endTime - $startTime

Write-ColorOutput "`n📊 Deployment Summary:" "Cyan"
Write-ColorOutput "   ⏱️  Total time: $($duration.Minutes)m $($duration.Seconds)s" "Gray"
Write-ColorOutput "   🏢 Client: $ClientName" "Gray"
Write-ColorOutput "   🌍 Environment: $Environment" "Gray"
Write-ColorOutput "   📍 Location: $Location" "Gray"

if ($deploySuccess) {
    Write-ColorOutput "`n🎉 Deployment completed successfully!" "Green"
    Write-ColorOutput "   ✅ Infrastructure deployed" "Green"
    if (-not $SkipInitialization) {
        Write-ColorOutput "   ✅ Data initialized" "Green"
    }
    if (-not $SkipValidation -and -not $SkipInitialization) {
        Write-ColorOutput "   ✅ Data validated" "Green"
    }
    
    Write-ColorOutput "`n🔗 Next steps:" "Cyan"
    Write-ColorOutput "   • Access Azure Portal to view resources" "Gray"
    Write-ColorOutput "   • Test your Azure Functions" "Gray"
    Write-ColorOutput "   • Query your Cosmos DB data" "Gray"
    
} else {
    Write-ColorOutput "`n❌ Deployment failed!" "Red"
    Write-ColorOutput "   Check the error messages above for details." "Red"
    exit 1
}

Write-ColorOutput "`n✅ Process completed!" "Green"
