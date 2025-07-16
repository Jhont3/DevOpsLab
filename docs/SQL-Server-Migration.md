# 🔄 Migración a SQL Server Database

## 📋 **Resumen de Cambios**

Se ha implementado la migración completa de **Cosmos DB** a **SQL Server Database** manteniendo el enfoque de Infrastructure as Code con Bicep.

## 🗂️ **Archivos Creados/Modificados**

### 🏗️ **Infrastructure as Code (Bicep)**
- `infrastructure/bicep/modules/sqlserver.bicep` - Módulo para SQL Server y SQL Database
- `infrastructure/bicep/main-sqlserver.bicep` - Template principal actualizado para SQL Server
- `config/clients-sqlserver.json` - Configuración de clientes actualizada para SQL Server

### 🛠️ **Scripts de Deployment**
- `scripts/Deploy-SqlServer-Environment.ps1` - Script principal de deployment para SQL Server
- `scripts/Initialize-SqlDatabase.ps1` - Inicialización de base de datos SQL Server
- `scripts/Validate-SqlDatabase.ps1` - Validación de datos en SQL Server

## 🚀 **Cómo Usar el Nuevo Sistema**

### 1. **Deployment Completo**
```powershell
# Deployment de infraestructura + inicialización de datos
.\scripts\Deploy-SqlServer-Environment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id"
```

### 2. **Solo Infraestructura**
```powershell
# Solo deployment de infraestructura (sin inicialización)
.\scripts\Deploy-SqlServer-Environment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id" -SkipInitialization
```

### 3. **Solo Inicialización de Datos**
```powershell
# Solo inicialización de base de datos (infraestructura ya existe)
.\scripts\Initialize-SqlDatabase.ps1 -ClientName "elite" -Environment "main"
```

### 4. **Validación de Datos**
```powershell
# Validar que los datos estén correctamente insertados
.\scripts\Validate-SqlDatabase.ps1 -ClientName "elite" -Environment "main"
```

## 🔧 **Configuración SQL Server**

### **Estructura de Base de Datos**
```sql
-- Tabla usuarios
CREATE TABLE usuarios (
    id NVARCHAR(50) PRIMARY KEY,
    nombre NVARCHAR(100) NOT NULL,
    email NVARCHAR(100) NOT NULL,
    activo BIT NOT NULL DEFAULT 1,
    fechaCreacion DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)

-- Tabla animales
CREATE TABLE animales (
    id NVARCHAR(50) PRIMARY KEY,
    nombre NVARCHAR(100) NOT NULL,
    tipo NVARCHAR(50) NOT NULL,
    sonido NVARCHAR(50) NOT NULL,
    activo BIT NOT NULL DEFAULT 1,
    fechaCreacion DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)
```

### **Datos por Defecto**
```
usuarios: usuario1, usuario2, usuario3
animales: perro, gato, raton
```

## 🎯 **Recursos Creados**

### **Por Cliente y Ambiente**
- **Resource Group**: `rg-witag-{client}-{environment}`
- **SQL Server**: `sql-witag-{client}-{environment}-2025`
- **SQL Database**: `witag-db`
- **Storage Account**: `stwitag{client}{environment}`
- **App Service Plan**: `asp-witag-{client}-{environment}`
- **Function Apps**: `{function}-{client}-{environment}`

### **Configuración de Seguridad**
- SQL Server con autenticación SQL
- Firewall configurado para Azure services
- Encryptions habilitadas
- Backup automático configurado

## 🔄 **Migración desde Cosmos DB**

### **Diferencias Clave**
| Aspecto | Cosmos DB | SQL Server |
|---------|-----------|------------|
| **Tipo** | NoSQL (Documentos) | SQL (Relacional) |
| **Esquema** | Schemaless | Schema fijo |
| **Queries** | SQL API + JavaScript | T-SQL |
| **Escalabilidad** | Horizontal (automática) | Vertical (manual) |
| **Costo** | Por RU/s | Por DTU/vCore |

### **Ventajas del Cambio**
✅ **Familiar**: SQL Server es más conocido por los desarrolladores
✅ **Herramientas**: Mejor ecosistema de herramientas de desarrollo
✅ **Queries**: T-SQL más potente para consultas complejas
✅ **Transacciones**: ACID completo
✅ **Costo**: Más predecible para cargas de trabajo pequeñas

## 📊 **Ejemplo de Uso**

### **Conexión desde Function App**
```csharp
// Connection string se inyecta automáticamente
var connectionString = Environment.GetEnvironmentVariable("SqlConnectionString");

using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();

// Query usuarios
var usuarios = await connection.QueryAsync<Usuario>("SELECT * FROM usuarios WHERE activo = 1");

// Query animales
var animales = await connection.QueryAsync<Animal>("SELECT * FROM animales WHERE tipo = @tipo", new { tipo = "mamifero" });
```

### **Validación de Deployment**
```powershell
# Verificar que todo esté funcionando
.\scripts\Validate-SqlDatabase.ps1 -ClientName "elite" -Environment "main"

# Salida esperada:
# ✅ Connection successful
# ✅ Table usuarios exists
# ✅ Table animales exists
# ✅ Found expected item: usuario1
# ✅ Found expected item: usuario2
# ✅ Found expected item: usuario3
# ✅ Found expected item: perro
# ✅ Found expected item: gato
# ✅ Found expected item: raton
# 🎉 All data validation passed!
```

## 🛡️ **Consideraciones de Seguridad**

### **Credenciales**
- Password se genera automáticamente si no se proporciona
- Se recomienda usar Azure Key Vault en producción
- Firewall configurado para permitir solo Azure services

### **Mejores Prácticas**
- Usar `SecureString` para passwords en scripts
- Implementar Azure AD authentication en producción
- Configurar backup y retention policies
- Monitorear performance y uso de recursos

## 🎯 **Próximos Pasos**

1. **Probar el deployment**: Ejecutar el script de deployment
2. **Validar funcionamiento**: Verificar que los datos se inserten correctamente
3. **Actualizar Function Apps**: Modificar el código para usar SQL Server
4. **Configurar CI/CD**: Adaptar GitHub Actions para usar los nuevos scripts
5. **Documentar**: Actualizar documentación del proyecto

¿Quieres proceder con el deployment de prueba? 🚀
