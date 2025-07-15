#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Tests the Bicep deployment templates without actually deploying resources.

.DESCRIPTION
    This script validates the Bicep templates syntax and structure to catch issues early.

.PARAMETER ClientName
    The name of the client to test (default: "elite")

.EXAMPLE
    .\Test-Deployment.ps1 -ClientName "elite"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ClientName = "elite"
)

# Set error action preference
$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Test-BicepSyntax {
    Write-ColorOutput "🔍 Testing Bicep syntax..." "Yellow"
    
    try {
        # Test main template build
        $buildResult = bicep build infrastructure/bicep/main.bicep --stdout
        Write-ColorOutput "✅ Main template syntax is valid" "Green"
        
        # Test individual modules
        $modules = @(
            "infrastructure/bicep/modules/appserviceplan.bicep",
            "infrastructure/bicep/modules/cosmosdb.bicep", 
            "infrastructure/bicep/modules/functionapp.bicep",
            "infrastructure/bicep/modules/storage.bicep"
        )
        
        foreach ($module in $modules) {
            if (Test-Path $module) {
                bicep build $module --stdout | Out-Null
                Write-ColorOutput "✅ $(Split-Path $module -Leaf) syntax is valid" "Green"
            }
        }
        
        return $true
    }
    catch {
        Write-ColorOutput "❌ Bicep syntax validation failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Test-Configuration {
    Write-ColorOutput "🔍 Testing configuration..." "Yellow"
    
    $configFile = "config/clients.json"
    
    if (-not (Test-Path $configFile)) {
        Write-ColorOutput "❌ Configuration file not found: $configFile" "Red"
        return $false
    }
    
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        
        if (-not $config.clients.$ClientName) {
            Write-ColorOutput "❌ Client '$ClientName' not found in configuration" "Red"
            return $false
        }
        
        if (-not $config.clients.$ClientName.environments.testing) {
            Write-ColorOutput "❌ Testing environment not found for client '$ClientName'" "Red"
            return $false
        }
        
        Write-ColorOutput "✅ Configuration is valid for client '$ClientName'" "Green"
        return $true
    }
    catch {
        Write-ColorOutput "❌ Configuration validation failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Test-Prerequisites {
    Write-ColorOutput "🔍 Testing prerequisites..." "Yellow"
    
    # Check if Bicep CLI is available
    if (-not (Get-Command "bicep" -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "❌ Bicep CLI is not installed or not in PATH" "Red"
        return $false
    }
    
    # Check if Azure CLI is available
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "❌ Azure CLI is not installed or not in PATH" "Red"
        return $false
    }
    
    Write-ColorOutput "✅ Prerequisites are available" "Green"
    return $true
}

# Main execution
try {
    Write-ColorOutput "🚀 Starting deployment tests for client '$ClientName'" "Blue"
    
    $allTestsPassed = $true
    
    # Test prerequisites
    if (-not (Test-Prerequisites)) {
        $allTestsPassed = $false
    }
    
    # Test configuration
    if (-not (Test-Configuration)) {
        $allTestsPassed = $false
    }
    
    # Test Bicep syntax
    if (-not (Test-BicepSyntax)) {
        $allTestsPassed = $false
    }
    
    if ($allTestsPassed) {
        Write-ColorOutput "🎉 All tests passed! Templates are ready for deployment." "Green"
        exit 0
    } else {
        Write-ColorOutput "❌ Some tests failed. Please fix the issues before deploying." "Red"
        exit 1
    }
    
} catch {
    Write-ColorOutput "💥 Test execution failed: $($_.Exception.Message)" "Red"
    exit 1
} 