# DevOpsLab - Solución Multi-Cliente con Azure Functions

## 🚀 Descripción

Solución DevOps completa para gestionar múltiples clientes desde un único repositorio, con despliegue automatizado en Azure utilizando GitHub Actions, Bicep y Azure Functions.

## ✨ Características

- **Repositorio Único**: Gestiona todos los clientes desde un solo lugar
- **Despliegue Automático**: GitHub Actions despliega en múltiples ambientes
- **Infraestructura como Código**: Bicep templates para recursos Azure
- **Configuración Centralizada**: JSON configuration para clientes y ambientes
- **Funciones Core y Plugins**: Funciones base + plugins opcionales por cliente
- **Autenticación OIDC**: Autenticación segura sin credenciales almacenadas
- **Monitoreo Integrado**: Application Insights y logs automáticos

## 🏗️ Arquitectura

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Repo   │    │  GitHub Actions │    │     Azure       │
│                 │    │                 │    │                 │
│ ├─ UsersFunction│────┼─ Build & Test   │────┼─ Function Apps  │
│ ├─ AnimalsFunc  │    │ ├─ Testing      │    │ ├─ Cosmos DB    │
│ ├─ PluginFunc   │    │ ├─ Production   │    │ ├─ Storage      │
│ └─ Config JSON  │    │ └─ Infrastructure│    │ └─ App Plans    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🎯 Casos de Uso

### ✅ Cumple con los Requerimientos

- **Único repositorio** para múltiples clientes ✓
- **Dos ramas principales**: `testing` y `main` ✓
- **Despliegue automático** en múltiples resource groups ✓
- **Un solo paso** para crear stack completo ✓
- **Funciones core** (usuarios, animales) ✓
- **Plugins opcionales** por cliente ✓
- **Configuración centralizada** ✓

### 🔥 Beneficios Adicionales

- Autenticación OIDC segura
- Monitoreo y logging automático
- Scripts de administración
- Documentación completa
- Ejemplos prácticos

## 📋 Prerrequisitos

- Suscripción de Azure
- Repositorio GitHub
- Azure CLI instalado
- PowerShell 7+ (para scripts)

## 🚀 Inicio Rápido

### 1. Configurar OIDC

```bash
# Crear aplicación Azure AD
az ad app create --display-name "witag-devops-github-actions"

# Configurar federation credentials
# Ver docs/OIDC-Setup.md para detalles completos
```

### 2. Configurar Secretos GitHub

- `AZURE_CLIENT_ID`: ID de la aplicación Azure AD
- `AZURE_TENANT_ID`: ID del tenant Azure AD  
- `AZURE_SUBSCRIPTION_ID`: ID de la suscripción Azure

### 3. Añadir Primer Cliente

```powershell
# Añadir cliente "colflores" con ambiente testing
./scripts/Add-NewClient.ps1 -ClientName "colflores" -DisplayName "Colflores Client" -Environment "testing" -DeployNow -SubscriptionId "tu-subscription-id"
```

### 4. Verificar Despliegue

```bash
# Verificar resource group
az group show --name "rg-witag-colflores-testing"

# Verificar Function Apps
az functionapp list --resource-group "rg-witag-colflores-testing" --query "[].{Name:name, State:state}" --output table
```

## 🔧 Estructura del Proyecto

```
DevOpsLab/
├── config/
│   └── clients.json                 # Configuración clientes
├── infrastructure/bicep/             # Templates Bicep
│   ├── main.bicep                   # Template principal
│   └── modules/                     # Módulos reutilizables
├── scripts/                         # Scripts PowerShell
│   ├── Deploy-Environment.ps1       # Despliegue entorno
│   └── Add-NewClient.ps1           # Añadir cliente
├── .github/workflows/               # GitHub Actions
│   ├── deploy-testing.yml          # Despliegue testing
│   ├── deploy-production.yml       # Despliegue producción
│   └── deploy-infrastructure.yml   # Despliegue infraestructura
├── UsersFunction/                   # Función usuarios
├── AnimalsFunction/                 # Función animales
├── PlugginsRandomFunctionOne/       # Función plugin
└── docs/                           # Documentación
```

## 📖 Documentación

- **[Guía Completa](docs/README.md)**: Documentación detallada
- **[Configuración OIDC](docs/OIDC-Setup.md)**: Setup autenticación
- **[Ejemplos Prácticos](docs/Examples.md)**: Casos de uso reales

## 🎮 Ejemplos de Uso

### Añadir Nuevo Cliente

```powershell
# Con plugins específicos
./scripts/Add-NewClient.ps1 -ClientName "mascotas" -DisplayName "Mascotas Client" -Environment "both" -PluginFunctions @("functionRandomUsuario") -DeployNow
```

### Desplegar Cambios

```bash
# Cambios en testing
git add .
git commit -m "feat: update users function"
git push origin testing  # Despliega automáticamente en todos los testing

# Cambios en producción
git checkout main
git merge testing
git push origin main     # Despliega automáticamente en todos los production
```

### Añadir Plugin a Cliente

```json
// Editar config/clients.json
{
  "clients": {
    "elite": {
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

## 🔄 Flujo de Trabajo

### Desarrollo Normal

1. **Desarrollar** → Cambios en código
2. **Testing** → `git push origin testing`
3. **Automático** → GitHub Actions despliega en todos los ambientes testing
4. **Verificar** → Probar en ambientes testing
5. **Producción** → `git push origin main`
6. **Automático** → GitHub Actions despliega en todos los ambientes production

### Nuevo Cliente

1. **Configurar** → Ejecutar script o editar JSON
2. **Automático** → GitHub Actions despliega infraestructura
3. **Verificar** → Validar recursos creados
4. **Listo** → Cliente operativo

## 🏃‍♂️ Comandos Útiles

```bash
# Listar clientes configurados
cat config/clients.json | jq '.clients | keys'

# Verificar estado de Function Apps
az functionapp list --resource-group "rg-witag-elite-testing" --output table

# Ver logs de GitHub Actions
gh run list --workflow="deploy-testing.yml" --limit=5

# Verificar Cosmos DB
az cosmosdb show --name "cosmos-witag-elite-testing" --resource-group "rg-witag-elite-testing"
```

## 🤝 Contribuir

1. Fork el repositorio
2. Crear feature branch (`git checkout -b feature/amazing-feature`)
3. Commit cambios (`git commit -m 'Add amazing feature'`)
4. Push branch (`git push origin feature/amazing-feature`)
5. Crear Pull Request

## 📝 Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para detalles.

## 🆘 Soporte

- 📖 **Documentación**: Revisa `docs/`
- 🐛 **Issues**: Reporta problemas en GitHub Issues
- 💬 **Discussions**: Usa GitHub Discussions para preguntas

## 🎯 Roadmap

- [ ] Soporte para múltiples regiones
- [ ] Integración con Azure DevOps
- [ ] Dashboard de monitoreo
- [ ] Backup automático de configuraciones
- [ ] Validación de configuración pre-despliegue

---

⭐ **¡Si te resulta útil, dale una estrella al repositorio!**