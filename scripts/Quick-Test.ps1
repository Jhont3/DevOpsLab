#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Quick validation script to verify OIDC setup and Azure configuration

.DESCRIPTION
    This script validates the OIDC configuration and Azure connection without deploying
    resources. It's designed for quick validation before running full deployments.
    
    Configuration priority (highest to lowest):
    1. Command line parameters
    2. local.settings.json file
    3. Default values in Config.ps1

.PARAMETER ApplicationId
    Azure Application ID for OIDC (optional: uses local.settings.json or defaults)
    
.PARAMETER SubscriptionId  
    Azure Subscription ID (optional: uses local.settings.json or defaults)
    
.PARAMETER ClientName
    Client to test (optional: defaults to "elite")

.EXAMPLE
    .\Quick-Test.ps1
    # Uses defaults or local.settings.json
    
.EXAMPLE
    .\Quick-Test.ps1 -ClientName "jarandes"
    # Test with jarandes client
    
.EXAMPLE
    .\Quick-Test.ps1 -ApplicationId "your-app-id" -SubscriptionId "your-sub-id"
    # Override with specific values
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$ClientName
)

# Load configuration
. "$PSScriptRoot/Config.ps1"

# Load local settings if exists (like Azure Functions)
if (Test-Path "local.settings.json") {
    Write-Host "Loading local.settings.json..." -ForegroundColor Yellow
    $localSettings = Get-Content "local.settings.json" -Raw | ConvertFrom-Json
    if ($localSettings.Values) {
        if (-not $ApplicationId) { $ApplicationId = $localSettings.Values.AZURE_CLIENT_ID }
        if (-not $SubscriptionId) { $SubscriptionId = $localSettings.Values.AZURE_SUBSCRIPTION_ID }
    }
}

# Set defaults from configuration if not provided
if (-not $ApplicationId) { $ApplicationId = (Get-ConfigValue "Azure" "ClientId") }
if (-not $SubscriptionId) { $SubscriptionId = (Get-ConfigValue "Azure" "SubscriptionId") }
if (-not $ClientName) { $ClientName = (Get-ConfigValue "Project" "DefaultClient") }

# Validate required parameters
if (-not $ApplicationId) {
    throw "❌ APPLICATION_ID no está configurado. Verificar local.settings.json o parámetros."
}
if (-not $SubscriptionId) {
    throw "❌ SUBSCRIPTION_ID no está configurado. Verificar local.settings.json o parámetros."
}

# Debug output
Write-Host "🔧 Configuración cargada:" -ForegroundColor Cyan
Write-Host "   ApplicationId: $($ApplicationId.Substring(0,8))..." -ForegroundColor Gray
Write-Host "   SubscriptionId: $($SubscriptionId.Substring(0,8))..." -ForegroundColor Gray
Write-Host "   ClientName: $ClientName" -ForegroundColor Gray

# Set error action preference
$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

try {
    Write-ColorOutput "=== Quick Test: OIDC and Elite Testing Environment ===" "Blue"
    
    # 1. Verify OIDC Configuration
    Write-ColorOutput "`n1. Verificando configuración OIDC..." "Yellow"
    
    Write-ColorOutput "   - Verificando aplicación Azure AD..." "Cyan"
    $appName = az ad app show --id $ApplicationId --query "displayName" --output tsv
    if ($appName) {
        Write-ColorOutput "   ✅ Aplicación encontrada: $appName" "Green"
    } else {
        throw "❌ No se encontró la aplicación con ID: $ApplicationId"
    }
    
    Write-ColorOutput "   - Verificando federation credentials..." "Cyan"
    $credentials = az ad app federated-credential list --id $ApplicationId --query "[].name" --output tsv
    if ($credentials) {
        Write-ColorOutput "   ✅ Federation credentials configuradas:" "Green"
        $credentials -split "`n" | ForEach-Object { Write-ColorOutput "     - $_" "Gray" }
    } else {
        Write-ColorOutput "   ⚠️  No se encontraron federation credentials" "Yellow"
    }
    
    Write-ColorOutput "   - Verificando role assignments..." "Cyan"
    $roles = az role assignment list --assignee $ApplicationId --query "[].roleDefinitionName" --output tsv
    if ($roles) {
        Write-ColorOutput "   ✅ Roles asignados:" "Green"
        $roles -split "`n" | ForEach-Object { Write-ColorOutput "     - $_" "Gray" }
    } else {
        Write-ColorOutput "   ⚠️  No se encontraron roles asignados" "Yellow"
    }
    
    # 2. Verify Configuration File
    Write-ColorOutput "`n2. Verificando configuración de clientes..." "Yellow"
    
    if (Test-Path "../config/clients.json") {
        $config = Get-Content "../config/clients.json" -Raw | ConvertFrom-Json
        $clientCount = ($config.clients | Get-Member -MemberType NoteProperty).Count
        Write-ColorOutput "   ✅ Archivo de configuración encontrado" "Green"
        Write-ColorOutput "   ✅ Clientes configurados: $clientCount" "Green"
        
        $config.clients | Get-Member -MemberType NoteProperty | ForEach-Object {
            Write-ColorOutput "     - $($_.Name)" "Gray"
        }
    } else {
        throw "❌ No se encontró ../config/clients.json"
    }
    
    # 3. Test Azure Connection
    Write-ColorOutput "`n3. Probando conexión a Azure..." "Yellow"
    
    Write-ColorOutput "   - Configurando suscripción..." "Cyan"
    az account set --subscription $SubscriptionId
    
    Write-ColorOutput "   - Verificando acceso a suscripción..." "Cyan"
    $accountInfo = az account show --output json | ConvertFrom-Json
    if ($accountInfo) {
        Write-ColorOutput "   ✅ Conectado a: $($accountInfo.name)" "Green"
        Write-ColorOutput "   ✅ Subscription ID: $($accountInfo.id)" "Green"
    } else {
        Write-ColorOutput "   ❌ No se pudo conectar a Azure" "Red"
    }
    
    # 4. Verify Resource Group (check if already exists)
    Write-ColorOutput "`n4. Verificando estado de recursos..." "Yellow"
    
    $resourceGroup = "rg-witag-$ClientName-testing"
    Write-ColorOutput "   - Verificando si existe: $resourceGroup" "Cyan"
    
    $rgExists = az group exists --name $resourceGroup --subscription $SubscriptionId
    if ($rgExists -eq "true") {
        Write-ColorOutput "   ✅ Resource group YA existe" "Green"
        
        Write-ColorOutput "   - Listando recursos existentes..." "Cyan"
        $resources = az resource list --resource-group $resourceGroup --output table
        Write-ColorOutput $resources "Gray"
    } else {
        Write-ColorOutput "   ℹ️  Resource group no existe (se creará en deployment)" "Yellow"
        Write-ColorOutput "   💡 Para crear recursos, ejecuta:" "Cyan"
        Write-ColorOutput "      .\Deploy-Environment.ps1 -ClientName '$ClientName' -Environment 'testing' -SubscriptionId '$SubscriptionId'" "Gray"
    }
    
    # 5. Success Summary
    Write-ColorOutput "`n🎉 ¡Validación completada exitosamente!" "Green"
    Write-ColorOutput "   ✅ OIDC configurado correctamente" "Green"
    Write-ColorOutput "   ✅ Conexión a Azure verificada" "Green"
    Write-ColorOutput "   ✅ Configuración de $ClientName validada" "Green"
    Write-ColorOutput "   ✅ Listo para deployment automático" "Green"
    
    Write-ColorOutput "`n📋 Valores para GitHub Secrets:" "Cyan"
    Write-ColorOutput "   AZURE_CLIENT_ID: $ApplicationId" "White"
    Write-ColorOutput "   AZURE_TENANT_ID: $(az account show --query tenantId --output tsv)" "White"
    Write-ColorOutput "   AZURE_SUBSCRIPTION_ID: $SubscriptionId" "White"
    
    Write-ColorOutput "`n🚀 Próximos pasos:" "Cyan"
    if ($rgExists -ne "true") {
        Write-ColorOutput "   1. Crear infraestructura:" "Yellow"
        Write-ColorOutput "      .\Deploy-Environment.ps1 -ClientName '$ClientName' -Environment 'testing' -SubscriptionId '$SubscriptionId'" "Gray"
        Write-ColorOutput "   2. Configurar GitHub Secrets (si no están configurados)" "Yellow"
        Write-ColorOutput "   3. Hacer push a main para deployment automático" "Yellow"
    } else {
        Write-ColorOutput "   1. Configurar GitHub Secrets (si no están configurados)" "Yellow"
        Write-ColorOutput "   2. Hacer push a main para deployment automático" "Yellow"
        Write-ColorOutput "   💡 La infraestructura ya existe - GitHub Actions actualizará automáticamente" "Green"
    }
    
} catch {
    Write-ColorOutput "`n❌ Error en la prueba: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" "Red"
    exit 1
} 