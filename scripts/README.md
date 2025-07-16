# DevOps Lab - Scripts de Deployment y Inicialización

## 🎯 Descripción General

Esta colección de scripts permite desplegar y gestionar la infraestructura del laboratorio DevOps de manera automatizada, incluyendo la inicialización de datos por defecto en Cosmos DB.

## 📋 Scripts Disponibles

### 1. **Deploy-Environment.ps1** - Deployment de Infraestructura

Despliega toda la infraestructura necesaria (Cosmos DB, Azure Functions, Storage, etc.).

```powershell
# Uso básico
.\Deploy-Environment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id"

# Con ubicación específica
.\Deploy-Environment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id" -Location "Australia East"
```

### 2. **Initialize-CosmosData.ps1** - Inicialización de Datos

Puebla Cosmos DB con los datos por defecto requeridos por el laboratorio.

```powershell
# Inicializar datos para elite-main
.\Initialize-CosmosData.ps1 -ClientName "elite" -Environment "main"

# Inicializar datos para jarandes-testing
.\Initialize-CosmosData.ps1 -ClientName "jarandes" -Environment "testing"
```

**Datos creados:**
- **usuarios**: usuario1, usuario2, usuario3
- **animales**: perro, gato, ratón

### 3. **Validate-CosmosData.ps1** - Validación de Datos

Verifica que los datos por defecto estén presentes en Cosmos DB.

```powershell
# Validar datos para elite-main
.\Validate-CosmosData.ps1 -ClientName "elite" -Environment "main"

# Validar datos para jarandes-testing
.\Validate-CosmosData.ps1 -ClientName "jarandes" -Environment "testing"
```

### 4. **Complete-Deployment.ps1** - Deployment Completo

Ejecuta todo el proceso en un solo comando: deploy + inicialización + validación.

```powershell
# Deployment completo
.\Complete-Deployment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id"

# Solo deployment (sin inicialización)
.\Complete-Deployment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id" -SkipInitialization

# Solo deployment (sin validación)
.\Complete-Deployment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id" -SkipValidation
```

## 🔄 Flujo de Trabajo Recomendado

### Para Desarrollo/Testing:
```powershell
# 1. Deployment completo
.\Complete-Deployment.ps1 -ClientName "elite" -Environment "testing" -SubscriptionId "your-subscription-id"

# 2. Si necesitas re-inicializar datos
.\Initialize-CosmosData.ps1 -ClientName "elite" -Environment "testing"

# 3. Validar que todo está correcto
.\Validate-CosmosData.ps1 -ClientName "elite" -Environment "testing"
```

### Para Producción:
```powershell
# 1. Deployment de infraestructura
.\Deploy-Environment.ps1 -ClientName "elite" -Environment "main" -SubscriptionId "your-subscription-id"

# 2. Inicialización de datos
.\Initialize-CosmosData.ps1 -ClientName "elite" -Environment "main"

# 3. Validación final
.\Validate-CosmosData.ps1 -ClientName "elite" -Environment "main"
```

## 📊 Datos por Defecto

### Colección `usuarios`:
```json
{
  "id": "usuario1",
  "name": "Usuario Uno",
  "email": "usuario1@[cliente].com",
  "role": "admin",
  "active": true,
  "created": "2025-07-15T...",
  "client": "[cliente]",
  "environment": "[environment]"
}
```

### Colección `animales`:
```json
{
  "id": "perro",
  "name": "Perro",
  "tipo": "Mamífero",
  "categoria": "Doméstico",
  "habitat": "Casa",
  "descripcion": "Animal doméstico leal y cariñoso",
  "created": "2025-07-15T...",
  "client": "[cliente]",
  "environment": "[environment]"
}
```

## 🛠️ Características Técnicas

### ✅ **Idempotencia**
- Todos los scripts son idempotentes
- Pueden ejecutarse múltiples veces sin efectos secundarios
- Los recursos existentes no se recrean innecesariamente

### ✅ **Validación de Existencia**
- Los scripts verifican automáticamente si los recursos ya existen
- Solo se crean/actualizan los recursos necesarios
- Manejo gracioso de errores y conflictos

### ✅ **Logging Detallado**
- Salida con colores para fácil identificación
- Timestamps y seguimiento de progreso
- Mensajes de éxito y error claros

## 🔧 Requisitos

### Prerrequisitos:
- **PowerShell 7.0+**
- **Azure CLI** instalado y configurado
- **Permisos de Contributor** en la suscripción de Azure
- **Acceso a la suscripción** especificada

### Verificación de Prerrequisitos:
```powershell
# Verificar Azure CLI
az --version

# Verificar login
az account show

# Verificar PowerShell
$PSVersionTable.PSVersion
```

## 🌍 Configuración de Regiones

Por defecto, los scripts usan **Australia East** como región. Para cambiar:

```powershell
# Cambiar región por defecto en Deploy-Environment.ps1
-Location "West Europe"

# O configurar en config/clients.json
"defaultLocation": "West Europe"
```

## 🚨 Troubleshooting

### Problemas Comunes:

1. **Error de conexión a Cosmos DB**
   ```powershell
   # Verificar que la cuenta existe
   az cosmosdb show --name [account-name] --resource-group [rg-name]
   ```

2. **Datos no inicializados**
   ```powershell
   # Re-ejecutar inicialización
   .\Initialize-CosmosData.ps1 -ClientName "elite" -Environment "main"
   ```

3. **Validación fallida**
   ```powershell
   # Verificar contenido manualmente
   az cosmosdb sql container query --account-name [account] --database-name [db] --name usuarios --query "SELECT * FROM c"
   ```

## 📈 Métricas y Monitoreo

### Tiempo de Deployment Típico:
- **Infraestructura**: 3-5 minutos
- **Inicialización**: 30-60 segundos
- **Validación**: 10-20 segundos
- **Total**: 4-7 minutos

### Verificación Post-Deployment:
```powershell
# Verificar recursos creados
az resource list --resource-group [rg-name] --output table

# Verificar datos en Cosmos DB
.\Validate-CosmosData.ps1 -ClientName "elite" -Environment "main"
```

## 🔄 Integración CI/CD

### GitHub Actions Example:
```yaml
- name: Deploy Infrastructure
  run: |
    pwsh -File scripts/Complete-Deployment.ps1 `
      -ClientName "elite" `
      -Environment "main" `
      -SubscriptionId "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
```

### Azure DevOps Pipeline:
```yaml
- task: PowerShell@2
  inputs:
    filePath: 'scripts/Complete-Deployment.ps1'
    arguments: '-ClientName "elite" -Environment "main" -SubscriptionId "$(subscriptionId)"'
```

---

## 📞 Soporte

Para problemas o preguntas:
1. Revisar los logs detallados de los scripts
2. Verificar prerrequisitos y permisos
3. Consultar la documentación de Azure CLI
4. Revisar el estado de los recursos en Azure Portal
