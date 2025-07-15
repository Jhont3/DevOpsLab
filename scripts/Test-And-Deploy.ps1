#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Validates configuration and deploys infrastructure for a client environment

.DESCRIPTION
    This script first validates OIDC configuration, then deploys infrastructure.
    It combines Quick-Test validation with full deployment in one command.

.PARAMETER ClientName
    Client to deploy (optional: defaults to "elite")
    
.PARAMETER Environment
    Environment to deploy ("testing" or "main", default: "testing")

.PARAMETER ApplicationId
    Azure Application ID for OIDC (optional: uses local.settings.json or defaults)
    
.PARAMETER SubscriptionId  
    Azure Subscription ID (optional: uses local.settings.json or defaults)
    
.PARAMETER SkipValidation
    Skip validation and go directly to deployment

.EXAMPLE
    .\Test-And-Deploy.ps1
    # Validate and deploy elite testing
    
.EXAMPLE
    .\Test-And-Deploy.ps1 -ClientName "jarandes" -Environment "main"
    # Validate and deploy jarandes production
    
.EXAMPLE
    .\Test-And-Deploy.ps1 -SkipValidation
    # Skip validation, deploy directly
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ClientName,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("testing", "main")]
    [string]$Environment = "testing",
    
    [Parameter(Mandatory = $false)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipValidation
)

# Set error action preference
$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

try {
    Write-ColorOutput "=== Test and Deploy: Full Infrastructure Deployment ===" "Blue"
    
    # 1. Validation Phase
    if (-not $SkipValidation) {
        Write-ColorOutput "`n🔍 Fase 1: Validación de configuración..." "Yellow"
        
        $validationParams = @()
        if ($ApplicationId) { $validationParams += "-ApplicationId", $ApplicationId }
        if ($SubscriptionId) { $validationParams += "-SubscriptionId", $SubscriptionId }
        if ($ClientName) { $validationParams += "-ClientName", $ClientName }
        
        Write-ColorOutput "   Ejecutando Quick-Test..." "Cyan"
        & "$PSScriptRoot\Quick-Test.ps1" @validationParams
        
        Write-ColorOutput "`n✅ Validación completada. Continuando con deployment..." "Green"
        Start-Sleep -Seconds 2
    } else {
        Write-ColorOutput "`n⏭️  Saltando validación por solicitud del usuario..." "Yellow"
    }
    
    # 2. Load Configuration
    Write-ColorOutput "`n⚙️  Fase 2: Cargando configuración..." "Yellow"
    
    # Load configuration similar to Quick-Test
    . "$PSScriptRoot/Config.ps1"
    
    if (Test-Path "local.settings.json") {
        Write-Host "Loading local.settings.json..." -ForegroundColor Yellow
        $localSettings = Get-Content "local.settings.json" -Raw | ConvertFrom-Json
        if ($localSettings.Values) {
            if (-not $ApplicationId) { $ApplicationId = $localSettings.Values.AZURE_CLIENT_ID }
            if (-not $SubscriptionId) { $SubscriptionId = $localSettings.Values.AZURE_SUBSCRIPTION_ID }
        }
    }
    
    if (-not $ApplicationId) { $ApplicationId = (Get-ConfigValue "Azure" "ClientId") }
    if (-not $SubscriptionId) { $SubscriptionId = (Get-ConfigValue "Azure" "SubscriptionId") }
    if (-not $ClientName) { $ClientName = (Get-ConfigValue "Project" "DefaultClient") }
    
    Write-ColorOutput "   Cliente: $ClientName" "Gray"
    Write-ColorOutput "   Ambiente: $Environment" "Gray"
    
    # 3. Deployment Phase
    Write-ColorOutput "`n🚀 Fase 3: Desplegando infraestructura..." "Yellow"
    
    Write-ColorOutput "   Ejecutando Deploy-Environment..." "Cyan"
    & "$PSScriptRoot\Deploy-Environment.ps1" -ClientName $ClientName -Environment $Environment -SubscriptionId $SubscriptionId
    
    # 4. Verification Phase
    Write-ColorOutput "`n✅ Fase 4: Verificación post-deployment..." "Yellow"
    
    $resourceGroup = "rg-witag-$ClientName-$Environment"
    Write-ColorOutput "   Verificando resource group: $resourceGroup" "Cyan"
    
    $rgExists = az group exists --name $resourceGroup --subscription $SubscriptionId
    if ($rgExists -eq "true") {
        Write-ColorOutput "   ✅ Resource group existe" "Green"
        
        Write-ColorOutput "   Listando recursos creados..." "Cyan"
        $resources = az resource list --resource-group $resourceGroup --output table
        Write-ColorOutput $resources "Gray"
        
        # Check specific resources
        Write-ColorOutput "`n   Verificando recursos específicos:" "Cyan"
        
        # Cosmos DB
        $cosmosName = "cosmos-witag-$ClientName-$Environment"
        $cosmosExists = az cosmosdb show --name $cosmosName --resource-group $resourceGroup --subscription $SubscriptionId --output tsv --query "name" 2>$null
        if ($cosmosExists) {
            Write-ColorOutput "   ✅ Cosmos DB: $cosmosName" "Green"
        } else {
            Write-ColorOutput "   ⚠️  Cosmos DB no encontrada" "Yellow"
        }
        
        # Storage Account
        $storageName = "stwitag$ClientName$Environment"
        $storageExists = az storage account show --name $storageName --resource-group $resourceGroup --subscription $SubscriptionId --output tsv --query "name" 2>$null
        if ($storageExists) {
            Write-ColorOutput "   ✅ Storage Account: $storageName" "Green"
        } else {
            Write-ColorOutput "   ⚠️  Storage Account no encontrada" "Yellow"
        }
        
    } else {
        Write-ColorOutput "   ❌ Resource group no existe después del deployment" "Red"
        throw "Deployment falló - resource group no creado"
    }
    
    # 5. Success Summary
    Write-ColorOutput "`n🎉 ¡Deployment completado exitosamente!" "Green"
    Write-ColorOutput "   ✅ Cliente: $ClientName" "Green"
    Write-ColorOutput "   ✅ Ambiente: $Environment" "Green"
    Write-ColorOutput "   ✅ Resource Group: $resourceGroup" "Green"
    Write-ColorOutput "   ✅ Todos los recursos creados" "Green"
    
    Write-ColorOutput "`n🌐 Acceso a recursos:" "Cyan"
    Write-ColorOutput "   Portal Azure: https://portal.azure.com/#@/resource/subscriptions/$SubscriptionId/resourceGroups/$resourceGroup" "Blue"
    
} catch {
    Write-ColorOutput "`n❌ Error en deployment: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" "Red"
    exit 1
} 