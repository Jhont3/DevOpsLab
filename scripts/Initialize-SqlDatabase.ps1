#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Initializes SQL Server database with default data and schema.

.DESCRIPTION
    This script creates the necessary tables and initializes a SQL Server database 
    with default data for the DevOps lab:
    - usuarios: usuario1, usuario2, usuario3
    - animales: perro, gato, ratón

.PARAMETER ClientName
    The name of the client (e.g., "elite", "jarandes", "ght")

.PARAMETER Environment
    The environment name ("testing" or "main")

.PARAMETER ConfigPath
    Path to the clients configuration file (default: "config/clients-sqlserver.json")

.PARAMETER SqlAdminPassword
    SQL Server administrator password (will prompt if not provided)

.EXAMPLE
    .\Initialize-SqlDatabase.ps1 -ClientName "elite" -Environment "main"
    
.EXAMPLE
    .\Initialize-SqlDatabase.ps1 -ClientName "elite" -Environment "main" -SqlAdminPassword "MyPassword123!"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("testing", "main")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "config/clients-sqlserver.json",
    
    [Parameter(Mandatory = $false)]
    [string]$SqlAdminPassword = ""
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write logs with timestamp
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}

# Function to validate and get configuration
function Get-ClientConfig {
    param([string]$ConfigPath, [string]$ClientName, [string]$Environment)
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Archivo de configuración no encontrado: $ConfigPath" "ERROR"
        throw "Configuration file not found"
    }
    
    try {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        $clientConfig = $config.clients.$ClientName.environments.$Environment
        
        if (-not $clientConfig) {
            Write-Log "Configuración no encontrada para cliente: $ClientName, ambiente: $Environment" "ERROR"
            throw "Client configuration not found"
        }
        
        return $clientConfig
    }
    catch {
        Write-Log "Error cargando configuración: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Function to execute SQL commands
function Invoke-SqlCommand {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$Query,
        [switch]$ReturnResults
    )
    
    try {
        # Construct connection string with proper quoting for special characters
        $connectionString = "Server=$ServerName;Database=$DatabaseName;User ID=$Username;Password=""$Password"";Encrypt=true;Connection Timeout=30;"
        
        # Use SqlServer module if available, otherwise use Azure CLI
        if (Get-Module -ListAvailable -Name SqlServer) {
            if ($ReturnResults) {
                return Invoke-Sqlcmd -ConnectionString $connectionString -Query $Query
            } else {
                Invoke-Sqlcmd -ConnectionString $connectionString -Query $Query | Out-Null
            }
        } else {
            # Fallback to Azure CLI
            $tempFile = [System.IO.Path]::GetTempFileName()
            $Query | Out-File -FilePath $tempFile -Encoding UTF8
            
            if ($ReturnResults) {
                $result = az sql query --server $ServerName --database $DatabaseName --username $Username --password $Password --file $tempFile --output table
                Remove-Item $tempFile -Force
                return $result
            } else {
                az sql query --server $ServerName --database $DatabaseName --username $Username --password $Password --file $tempFile --output none
                Remove-Item $tempFile -Force
            }
        }
        
        Write-Log "Comando SQL ejecutado exitosamente" "SUCCESS"
    }
    catch {
        Write-Log "Error ejecutando comando SQL: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Function to create database schema
function Initialize-DatabaseSchema {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password
    )
    
    Write-Log "Creando esquema de base de datos..." "INFO"
    
    # Create usuarios table
    $createUsuariosTable = @"
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='usuarios' AND xtype='U')
BEGIN
    CREATE TABLE usuarios (
        id NVARCHAR(50) PRIMARY KEY,
        nombre NVARCHAR(100) NOT NULL,
        email NVARCHAR(100) NOT NULL,
        activo BIT NOT NULL DEFAULT 1,
        fechaCreacion DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    )
END
"@
    
    # Create animales table
    $createAnimalesTable = @"
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='animales' AND xtype='U')
BEGIN
    CREATE TABLE animales (
        id NVARCHAR(50) PRIMARY KEY,
        nombre NVARCHAR(100) NOT NULL,
        tipo NVARCHAR(50) NOT NULL,
        sonido NVARCHAR(50) NOT NULL,
        activo BIT NOT NULL DEFAULT 1,
        fechaCreacion DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    )
END
"@
    
    try {
        Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query $createUsuariosTable
        Write-Log "Tabla 'usuarios' creada exitosamente" "SUCCESS"
        
        Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query $createAnimalesTable
        Write-Log "Tabla 'animales' creada exitosamente" "SUCCESS"
    }
    catch {
        Write-Log "Error creando esquema: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Function to insert default data
function Initialize-DefaultData {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password,
        [string]$ClientName
    )
    
    Write-Log "Insertando datos por defecto..." "INFO"
    
    # Insert usuarios data
    $insertUsuarios = @"
MERGE usuarios AS target
USING (
    VALUES 
        ('usuario1', 'Usuario Uno', 'usuario1@$($ClientName.ToLower()).com', 1, GETUTCDATE()),
        ('usuario2', 'Usuario Dos', 'usuario2@$($ClientName.ToLower()).com', 1, GETUTCDATE()),
        ('usuario3', 'Usuario Tres', 'usuario3@$($ClientName.ToLower()).com', 1, GETUTCDATE())
) AS source (id, nombre, email, activo, fechaCreacion)
ON target.id = source.id
WHEN NOT MATCHED THEN
    INSERT (id, nombre, email, activo, fechaCreacion)
    VALUES (source.id, source.nombre, source.email, source.activo, source.fechaCreacion);
"@
    
    # Insert animales data
    $insertAnimales = @"
MERGE animales AS target
USING (
    VALUES 
        ('perro', 'Perro', 'mamifero', 'guau', 1, GETUTCDATE()),
        ('gato', 'Gato', 'mamifero', 'miau', 1, GETUTCDATE()),
        ('raton', 'Ratón', 'mamifero', 'squeak', 1, GETUTCDATE())
) AS source (id, nombre, tipo, sonido, activo, fechaCreacion)
ON target.id = source.id
WHEN NOT MATCHED THEN
    INSERT (id, nombre, tipo, sonido, activo, fechaCreacion)
    VALUES (source.id, source.nombre, source.tipo, source.sonido, source.activo, source.fechaCreacion);
"@
    
    try {
        Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query $insertUsuarios
        Write-Log "Datos de usuarios insertados exitosamente" "SUCCESS"
        
        Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query $insertAnimales
        Write-Log "Datos de animales insertados exitosamente" "SUCCESS"
    }
    catch {
        Write-Log "Error insertando datos: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Function to validate data
function Test-DatabaseData {
    param(
        [string]$ServerName,
        [string]$DatabaseName,
        [string]$Username,
        [string]$Password
    )
    
    Write-Log "Validando datos insertados..." "INFO"
    
    try {
        # Count usuarios
        $usuariosCount = Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query "SELECT COUNT(*) as count FROM usuarios" -ReturnResults
        
        # Count animales
        $animalesCount = Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Username $Username -Password $Password -Query "SELECT COUNT(*) as count FROM animales" -ReturnResults
        
        Write-Log "Validación completada:" "INFO"
        Write-Log "  📊 usuarios: $($usuariosCount.count) registros" "INFO"
        Write-Log "  📊 animales: $($animalesCount.count) registros" "INFO"
        
        return ($usuariosCount.count -ge 3) -and ($animalesCount.count -ge 3)
    }
    catch {
        Write-Log "Error validando datos: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main execution
try {
    Write-Log "🚀 Iniciando script de inicialización de SQL Server"
    Write-Log "Cliente: $ClientName | Ambiente: $Environment"
    
    # Get SQL admin password if not provided
    if ([string]::IsNullOrEmpty($SqlAdminPassword)) {
        $securePassword = Read-Host "Ingresa la contraseña del administrador de SQL Server" -AsSecureString
        $SqlAdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    }
    
    # Get client configuration
    $clientConfig = Get-ClientConfig -ConfigPath $ConfigPath -ClientName $ClientName -Environment $Environment
    
    $resourceGroup = $clientConfig.resourceGroup
    $serverName = $clientConfig.sqlServer.serverName
    $databaseName = $clientConfig.sqlServer.databaseName
    $adminLogin = $clientConfig.sqlServer.adminLogin
    
    Write-Log "Configuración cargada:" "INFO"
    Write-Log "  Resource Group: $resourceGroup" "INFO"
    Write-Log "  Server Name: $serverName" "INFO"
    Write-Log "  Database Name: $databaseName" "INFO"
    Write-Log "  Admin Login: $adminLogin" "INFO"
    
    # Get server FQDN
    $serverFqdn = "$serverName.database.windows.net"
    
    # Test connection
    Write-Log "Probando conexión a SQL Server..." "INFO"
    try {
        Invoke-SqlCommand -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword -Query "SELECT 1" | Out-Null
        Write-Log "Conexión exitosa a SQL Server" "SUCCESS"
    }
    catch {
        Write-Log "Error conectando a SQL Server: $($_.Exception.Message)" "ERROR"
        throw
    }
    
    # Initialize database schema
    Initialize-DatabaseSchema -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword
    
    # Initialize default data
    Initialize-DefaultData -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword -ClientName $ClientName
    
    # Validate data
    $dataValid = Test-DatabaseData -ServerName $serverFqdn -DatabaseName $databaseName -Username $adminLogin -Password $SqlAdminPassword
    
    if ($dataValid) {
        Write-Log "🎉 Inicialización completada exitosamente!" "SUCCESS"
        Write-Log "  ✅ Esquema de base de datos creado" "SUCCESS"
        Write-Log "  ✅ Datos por defecto insertados" "SUCCESS"
        Write-Log "  ✅ Validación exitosa" "SUCCESS"
        Write-Log "💡 Base de datos SQL Server lista para usar!" "SUCCESS"
    } else {
        Write-Log "❌ Validación de datos falló" "ERROR"
        exit 1
    }
    
} catch {
    Write-Log "💥 Error crítico: $($_.Exception.Message)" "ERROR"
    Write-Log "Detalles del error:" "ERROR"
    Write-Log "   $($_.Exception.StackTrace)" "ERROR"
    exit 1
}

Write-Log "✅ Script de inicialización SQL Server completado exitosamente!" "SUCCESS"
