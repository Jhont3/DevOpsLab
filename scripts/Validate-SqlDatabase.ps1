#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Validates that SQL Server database contains the expected default data.

.DESCRIPTION
    This script validates that the SQL Server database contains the default data
    as specified in the lab requirements:
    - usuarios: usuario1, usuario2, usuario3
    - animales: perro, gato, ratón

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER ConfigFile
    Path to the clients configuration file (default: "config/clients-sqlserver.json")

.PARAMETER SqlAdminPassword
    SQL Server administrator password (will prompt if not provided)

.EXAMPLE
    .\Validate-SqlDatabase.ps1 -ClientName "elite" -Environment "main"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "config/clients-sqlserver.json",
    
    [Parameter(Mandatory = $false)]
    [string]$SqlAdminPassword = ""
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

# Function to execute SQL query
function Invoke-SqlQuery {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$Query
    )
    
    try {
        # Use SqlServer module if available, otherwise use Azure CLI
        if (Get-Module -ListAvailable -Name SqlServer) {
            $connectionString = "Server=$ServerName;Database=$DatabaseName;User ID=$Username;Password=$Password;Encrypt=true;Connection Timeout=30;"
            return Invoke-Sqlcmd -ConnectionString $connectionString -Query $Query
        } else {
            # Fallback to Azure CLI
            $tempFile = [System.IO.Path]::GetTempFileName()
            $Query | Out-File -FilePath $tempFile -Encoding UTF8
            
            $result = az sql query --server $ServerName --database $DatabaseName --username $Username --password $Password --file $tempFile --output json
            Remove-Item $tempFile -Force
            
            return $result | ConvertFrom-Json
        }
    }
    catch {
        Write-ColorOutput "❌ Error executing SQL query: $($_.Exception.Message)" "Red"
        throw
    }
}

# Function to validate table data
function Test-TableData {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$TableName,
        [array]$ExpectedItems
    )
    
    Write-ColorOutput "🔍 Validating data in table: $TableName" "Yellow"
    
    try {
        # Query all records in the table
        $query = "SELECT id FROM $TableName"
        $result = Invoke-SqlQuery -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query $query
        
        if ($result -is [array]) {
            $actualItems = $result | ForEach-Object { $_.id }
        } elseif ($result.id) {
            $actualItems = @($result.id)
        } else {
            $actualItems = @()
        }
        
        Write-ColorOutput "   📊 Found $($actualItems.Count) items in $TableName" "Cyan"
        
        $allFound = $true
        foreach ($expectedItem in $ExpectedItems) {
            if ($actualItems -contains $expectedItem) {
                Write-ColorOutput "   ✅ Found expected item: $expectedItem" "Green"
            } else {
                Write-ColorOutput "   ❌ Missing expected item: $expectedItem" "Red"
                $allFound = $false
            }
        }
        
        return $allFound
        
    } catch {
        Write-ColorOutput "   ❌ Error validating $TableName`: $_" "Red"
        return $false
    }
}

# Function to test database connection
function Test-DatabaseConnection {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password
    )
    
    Write-ColorOutput "🔌 Testing SQL Server connection..." "Yellow"
    
    try {
        Invoke-SqlQuery -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query "SELECT 1 AS test" | Out-Null
        Write-ColorOutput "   ✅ Connection successful" "Green"
        return $true
    }
    catch {
        Write-ColorOutput "   ❌ Connection failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Function to validate table schema
function Test-TableSchema {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$TableName
    )
    
    Write-ColorOutput "🔍 Validating table schema: $TableName" "Yellow"
    
    try {
        $query = "SELECT COUNT(*) as count FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TableName'"
        $result = Invoke-SqlQuery -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query $query
        
        $exists = $result.count -gt 0
        
        if ($exists) {
            Write-ColorOutput "   ✅ Table $TableName exists" "Green"
        } else {
            Write-ColorOutput "   ❌ Table $TableName does not exist" "Red"
        }
        
        return $exists
    }
    catch {
        Write-ColorOutput "   ❌ Error validating table schema: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Main validation logic
Write-ColorOutput "🚀 Starting SQL Server database validation..." "Yellow"

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
    $serverName = $clientConfig.sqlServer.serverName
    $databaseName = $clientConfig.sqlServer.databaseName
    $adminLogin = $clientConfig.sqlServer.adminLogin
    
    Write-ColorOutput "📋 Validation details:" "Cyan"
    Write-ColorOutput "   🏢 Client: $ClientName" "Gray"
    Write-ColorOutput "   🌍 Environment: $Environment" "Gray"
    Write-ColorOutput "   📦 Resource Group: $resourceGroupName" "Gray"
    Write-ColorOutput "   🗄️  Database: $databaseName" "Gray"
    Write-ColorOutput "   🔗 Server: $serverName" "Gray"
    
    # Get SQL admin password if not provided
    if ([string]::IsNullOrEmpty($SqlAdminPassword)) {
        $securePassword = Read-Host "Ingresa la contraseña del administrador de SQL Server" -AsSecureString
        $SqlAdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    }
    
    # Get server FQDN
    $serverFqdn = "$serverName.database.windows.net"
    
    # Test connection
    $connectionValid = Test-DatabaseConnection -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword
    
    if (-not $connectionValid) {
        Write-ColorOutput "❌ Cannot connect to SQL Server database" "Red"
        exit 1
    }
    
    # Validate table schemas
    $usuariosTableExists = Test-TableSchema -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword -TableName "usuarios"
    $animalesTableExists = Test-TableSchema -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword -TableName "animales"
    
    if (-not $usuariosTableExists -or -not $animalesTableExists) {
        Write-ColorOutput "❌ Required tables are missing" "Red"
        exit 1
    }
    
    # Define expected data
    $expectedUsuarios = @("usuario1", "usuario2", "usuario3")
    $expectedAnimales = @("perro", "gato", "raton")
    
    # Validate usuarios table data
    $usuariosValid = Test-TableData -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword -TableName "usuarios" -ExpectedItems $expectedUsuarios
    
    # Validate animales table data
    $animalesValid = Test-TableData -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword -TableName "animales" -ExpectedItems $expectedAnimales
    
    # Summary
    Write-ColorOutput "`n📊 Validation Summary:" "Cyan"
    if ($usuariosValid -and $animalesValid) {
        Write-ColorOutput "🎉 All data validation passed!" "Green"
        Write-ColorOutput "   ✅ usuarios table: $($expectedUsuarios.Count) items verified" "Green"
        Write-ColorOutput "   ✅ animales table: $($expectedAnimales.Count) items verified" "Green"
        Write-ColorOutput "`n💡 Your SQL Server database is ready for use!" "Green"
    } else {
        Write-ColorOutput "❌ Data validation failed!" "Red"
        if (-not $usuariosValid) {
            Write-ColorOutput "   ❌ usuarios table validation failed" "Red"
        }
        if (-not $animalesValid) {
            Write-ColorOutput "   ❌ animales table validation failed" "Red"
        }
        Write-ColorOutput "`n💡 Run Initialize-SqlDatabase.ps1 to populate missing data" "Yellow"
        exit 1
    }
    
} catch {
    Write-ColorOutput "❌ Error during validation: $_" "Red"
    exit 1
}

Write-ColorOutput "`n✅ SQL Server database validation completed successfully!" "Green"
