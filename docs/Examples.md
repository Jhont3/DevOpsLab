# Ejemplos Prácticos de Uso

## Ejemplo 1: Añadir Cliente "Colflores" con Ambiente Testing

### Paso a Paso

```powershell
# 1. Añadir cliente usando el script
./scripts/Add-NewClient.ps1 -ClientName "colflores" -DisplayName "Colflores Client" -Environment "testing" -DeployNow -SubscriptionId "abc123-def456-ghi789"

# 2. Verificar que se creó el resource group
az group show --name "rg-witag-colflores-testing"

# 3. Verificar las Function Apps
az functionapp list --resource-group "rg-witag-colflores-testing" --query "[].{Name:name, State:state}" --output table

# 4. Verificar Cosmos DB
az cosmosdb show --name "cosmos-witag-colflores-testing" --resource-group "rg-witag-colflores-testing"
```

### Configuración Resultante

```json
{
  "clients": {
    "colflores": {
      "displayName": "Colflores Client",
      "environments": {
        "testing": {
          "resourceGroup": "rg-witag-colflores-testing",
          "location": "East US",
          "cosmosDb": {
            "accountName": "cosmos-witag-colflores-testing",
            "databaseName": "witag-db"
          },
          "functions": {
            "core": ["functionUsuarios", "functionAnimales"],
            "plugins": []
          }
        }
      }
    }
  }
}
```

### Recursos Creados

- **Resource Group**: `rg-witag-colflores-testing`
- **Cosmos DB**: `cosmos-witag-colflores-testing`
- **Storage Account**: `stwitagcolflores testing`
- **App Service Plan**: `asp-witag-colflores-testing`
- **Function Apps**:
  - `functionUsuarios-colflores-testing`
  - `functionAnimales-colflores-testing`

## Ejemplo 2: Actualizar Función de Usuarios

### Escenario

Necesitas actualizar la función de usuarios para añadir validación de email.

### Código Actualizado

```csharp
// UsersFunction/Function1.cs
[FunctionName("GetUsers")]
public static async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Function, "get", Route = "users")] HttpRequest req,
    ILogger log)
{
    log.LogInformation("C# HTTP trigger function processed a request.");

    // Nueva validación de email
    var emailParam = req.Query["email"];
    if (!string.IsNullOrEmpty(emailParam) && !IsValidEmail(emailParam))
    {
        return new BadRequestObjectResult("Invalid email format");
    }

    // Resto del código...
}

private static bool IsValidEmail(string email)
{
    try
    {
        var addr = new System.Net.Mail.MailAddress(email);
        return addr.Address == email;
    }
    catch
    {
        return false;
    }
}
```

### Proceso de Despliegue

```bash
# 1. Hacer cambios localmente
git add UsersFunction/

# 2. Commit descriptivo
git commit -m "feat: add email validation to users function"

# 3. Push a testing para probar
git push origin testing

# 4. GitHub Actions desplegará automáticamente en:
# - functionUsuarios-elite-testing
# - functionUsuarios-jarandes-testing
# - functionUsuarios-ght-testing
# - functionUsuarios-florexpo-testing
# - functionUsuarios-colflores-testing

# 5. Verificar que funciona en testing
curl "https://functionUsuarios-elite-testing.azurewebsites.net/api/users?email=invalid-email"
# Debe retornar: {"error": "Invalid email format"}

# 6. Si todo está bien, merge a main
git checkout main
git merge testing
git push origin main
```

## Ejemplo 3: Añadir Plugin a Cliente Existente

### Escenario

El cliente Florexpo quiere añadir el plugin `functionRandomUsuario` a su ambiente de producción.

### Paso a Paso

```bash
# 1. Editar config/clients.json
```

```json
{
  "clients": {
    "florexpo": {
      "environments": {
        "main": {
          "functions": {
            "core": ["functionUsuarios", "functionAnimales"],
            "plugins": ["functionRandomUsuario"]  // Añadir plugin
          }
        }
      }
    }
  }
}
```

```bash
# 2. Commit y push
git add config/clients.json
git commit -m "feat: add randomUsuario plugin to florexpo production"
git push origin main

# 3. El workflow de infraestructura se ejecutará automáticamente
# 4. Verificar que se creó la Function App
az functionapp show --name "functionRandomUsuario-florexpo-main" --resource-group "rg-witag-florexpo-main"
```

### Verificar Funcionamiento

```bash
# Test del nuevo plugin
curl "https://functionRandomUsuario-florexpo-main.azurewebsites.net/api/random-user"
```

## Ejemplo 4: Despliegue Multi-Cliente Automático

### Escenario

Tienes una actualización en la función de animales que debe desplegarse en todos los clientes.

### Código Actualizado

```csharp
// AnimalsFunction/Function1.cs
[FunctionName("GetAnimals")]
public static async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Function, "get", Route = "animals")] HttpRequest req,
    ILogger log)
{
    log.LogInformation("C# HTTP trigger function processed a request.");

    // Nueva funcionalidad: filtrar por tipo
    var typeFilter = req.Query["type"];
    
    // Obtener datos de Cosmos DB
    var animals = await GetAnimalsFromCosmosDB(typeFilter);
    
    return new OkObjectResult(animals);
}

private static async Task<List<Animal>> GetAnimalsFromCosmosDB(string typeFilter)
{
    // Lógica para filtrar por tipo
    // ...
}
```

### Proceso de Despliegue

```bash
# 1. Commit y push a testing
git add AnimalsFunction/
git commit -m "feat: add type filtering to animals function"
git push origin testing
```

### Resultado del Despliegue

GitHub Actions desplegará automáticamente en:

**Ambientes Testing**:
- `functionAnimales-elite-testing`
- `functionAnimales-jarandes-testing`
- `functionAnimales-ght-testing`
- `functionAnimales-florexpo-testing`
- `functionAnimales-colflores-testing`

**Logs del Workflow**:
```
✅ Successfully deployed to functionAnimales-elite-testing
✅ Successfully deployed to functionAnimales-jarandes-testing
✅ Successfully deployed to functionAnimales-ght-testing
✅ Successfully deployed to functionAnimales-florexpo-testing
✅ Successfully deployed to functionAnimales-colflores-testing
🎉 All testing environments deployed successfully!
```

## Ejemplo 5: Configuración de Nuevo Cliente con Plugins

### Escenario

Añadir cliente "Mascotas" con plugins específicos desde el inicio.

### Configuración Completa

```powershell
# Añadir cliente con plugins
./scripts/Add-NewClient.ps1 -ClientName "mascotas" -DisplayName "Mascotas Client" -Environment "both" -PluginFunctions @("functionRandomUsuario") -DeployNow -SubscriptionId "abc123-def456-ghi789"
```

### Configuración JSON Resultante

```json
{
  "clients": {
    "mascotas": {
      "displayName": "Mascotas Client",
      "environments": {
        "testing": {
          "resourceGroup": "rg-witag-mascotas-testing",
          "location": "East US",
          "cosmosDb": {
            "accountName": "cosmos-witag-mascotas-testing",
            "databaseName": "witag-db"
          },
          "functions": {
            "core": ["functionUsuarios", "functionAnimales"],
            "plugins": ["functionRandomUsuario"]
          }
        },
        "main": {
          "resourceGroup": "rg-witag-mascotas-main",
          "location": "East US",
          "cosmosDb": {
            "accountName": "cosmos-witag-mascotas-main",
            "databaseName": "witag-db"
          },
          "functions": {
            "core": ["functionUsuarios", "functionAnimales"],
            "plugins": ["functionRandomUsuario"]
          }
        }
      }
    }
  }
}
```

### Function Apps Creadas

**Testing**:
- `functionUsuarios-mascotas-testing`
- `functionAnimales-mascotas-testing`
- `functionRandomUsuario-mascotas-testing`

**Production**:
- `functionUsuarios-mascotas-main`
- `functionAnimales-mascotas-main`
- `functionRandomUsuario-mascotas-main`

## Ejemplo 6: Despliegue Manual de Infraestructura

### Escenario

Necesitas redesplegar la infraestructura para un cliente específico.

### Usando GitHub Actions

1. Ve a **Actions** → **Deploy Infrastructure**
2. Haz clic en **Run workflow**
3. Completa los parámetros:
   - `client_name`: `elite`
   - `environment`: `testing`
   - `force_deploy`: `true`
4. Haz clic en **Run workflow**

### Usando PowerShell

```powershell
# Redesplegar ambiente testing para cliente elite
./scripts/Deploy-Environment.ps1 -ClientName "elite" -Environment "testing" -SubscriptionId "abc123-def456-ghi789"

# Verificar despliegue
az group show --name "rg-witag-elite-testing"
az functionapp list --resource-group "rg-witag-elite-testing" --query "[].{Name:name, State:state}" --output table
```

## Ejemplo 7: Monitoreo y Troubleshooting

### Verificar Estado de Funciones

```bash
# Listar todas las Function Apps de un cliente
az functionapp list --resource-group "rg-witag-elite-testing" --output table

# Verificar logs de una Function App específica
az functionapp log tail --name "functionUsuarios-elite-testing" --resource-group "rg-witag-elite-testing"

# Verificar Application Insights
az monitor app-insights component show --app "functionUsuarios-elite-testing" --resource-group "rg-witag-elite-testing"
```

### Verificar Cosmos DB

```bash
# Verificar estado de Cosmos DB
az cosmosdb show --name "cosmos-witag-elite-testing" --resource-group "rg-witag-elite-testing"

# Listar colecciones
az cosmosdb sql container list --account-name "cosmos-witag-elite-testing" --database-name "witag-db" --resource-group "rg-witag-elite-testing"

# Verificar datos en colección
az cosmosdb sql container query --account-name "cosmos-witag-elite-testing" --database-name "witag-db" --name "usuarios" --resource-group "rg-witag-elite-testing" --query-text "SELECT * FROM c"
```

### Verificar Workflows

```bash
# Verificar último workflow execution
gh run list --workflow="deploy-testing.yml" --limit=5

# Ver detalles de un workflow específico
gh run view [RUN_ID]

# Ver logs de un workflow
gh run view [RUN_ID] --log
```

## Ejemplo 8: Rollback de Despliegue

### Escenario

Una actualización causó problemas en producción y necesitas hacer rollback.

### Proceso de Rollback

```bash
# 1. Identificar el commit problemático
git log --oneline -10

# 2. Hacer rollback del código
git revert [COMMIT_HASH]

# 3. Push a main para redesplegar
git push origin main

# 4. Verificar que el rollback fue exitoso
curl "https://functionUsuarios-elite-main.azurewebsites.net/api/users"
```

### Rollback de Infraestructura

```powershell
# Si necesitas rollback de infraestructura, restaura config/clients.json
git checkout [PREVIOUS_COMMIT] -- config/clients.json
git commit -m "rollback: restore infrastructure configuration"
git push origin main
```

## Ejemplo 9: Configuración de Múltiples Regiones

### Escenario

Configurar cliente en diferentes regiones para alta disponibilidad.

### Configuración JSON

```json
{
  "clients": {
    "global": {
      "displayName": "Global Client",
      "environments": {
        "testing": {
          "resourceGroup": "rg-witag-global-testing-eastus",
          "location": "East US",
          "functions": {
            "core": ["functionUsuarios", "functionAnimales"],
            "plugins": []
          }
        },
        "main": {
          "resourceGroup": "rg-witag-global-main-westus",
          "location": "West US",
          "functions": {
            "core": ["functionUsuarios", "functionAnimales"],
            "plugins": []
          }
        }
      }
    }
  }
}
```

### Despliegue Multi-Región

```powershell
# Desplegar en East US (testing)
./scripts/Deploy-Environment.ps1 -ClientName "global" -Environment "testing" -Location "East US" -SubscriptionId "abc123-def456-ghi789"

# Desplegar en West US (production)
./scripts/Deploy-Environment.ps1 -ClientName "global" -Environment "main" -Location "West US" -SubscriptionId "abc123-def456-ghi789"
```

## Ejemplo 10: Automatización con Azure DevOps

### Integración con Azure DevOps

Si prefieres usar Azure DevOps en lugar de GitHub Actions:

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main
      - testing

variables:
  azureSubscription: 'your-service-connection'

stages:
- stage: Deploy
  jobs:
  - job: DeployFunctions
    pool:
      vmImage: 'ubuntu-latest'
    steps:
    - task: AzureCLI@2
      inputs:
        azureSubscription: $(azureSubscription)
        scriptType: 'pscore'
        scriptLocation: 'scriptPath'
        scriptPath: 'scripts/Deploy-Environment.ps1'
        arguments: '-ClientName "elite" -Environment "testing" -SubscriptionId "$(azureSubscription)"'
```

## Conclusión

Estos ejemplos muestran la flexibilidad y potencia de la solución DevOps multi-cliente. Puedes:

1. **Añadir clientes** fácilmente con o sin plugins
2. **Desplegar automáticamente** en múltiples ambientes
3. **Gestionar plugins** por cliente
4. **Monitorear y troubleshoot** eficientemente
5. **Hacer rollbacks** cuando sea necesario
6. **Escalar** a múltiples regiones
7. **Integrar** con diferentes plataformas CI/CD

La clave está en la configuración centralizada y los workflows automatizados que aseguran consistencia y confiabilidad en todos los despliegues. 