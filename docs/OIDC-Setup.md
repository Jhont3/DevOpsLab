# Configuración OIDC para GitHub Actions con Azure

## Descripción

Este documento describe cómo configurar la autenticación OIDC (OpenID Connect) entre GitHub Actions y Azure para permitir el despliegue automático sin necesidad de almacenar credenciales en secretos.

## Requisitos Previos

- Suscripción de Azure con permisos de administrador
- Repositorio de GitHub con permisos de administrador
- Azure CLI instalado
- Permisos para crear aplicaciones en Azure AD

## Paso 1: Crear una App Registration en Azure AD

### 1.1 Crear la aplicación

```bash
# Crear la aplicación en Azure AD
az ad app create --display-name "witag-devops"
```

### 1.2 Obtener el Application ID

```bash
# Obtener el Application ID
az ad app list --display-name "witag-devops" --query "[0].appId" --output tsv
```

### 1.3 Crear un Service Principal

```bash
# Crear service principal usando el Application ID
az ad sp create --id <APPLICATION_ID>
```

## Paso 2: Configurar Federation con GitHub

### 2.1 Crear Federation Credential

```bash
# Reemplazar los valores apropiados
APPLICATION_ID="<tu-application-id>"
GITHUB_ORGANIZATION="<tu-organizacion>"
GITHUB_REPOSITORY="<tu-repositorio>"

# Crear federation credential para la rama main
az ad app federated-credential create \
  --id $APPLICATION_ID \
  --parameters '{
    "name": "witag-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORGANIZATION'/'$GITHUB_REPOSITORY':ref:refs/heads/main",
    "description": "Main branch deployment",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Crear federation credential para la rama testing
az ad app federated-credential create \
  --id $APPLICATION_ID \
  --parameters '{
    "name": "witag-testing-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORGANIZATION'/'$GITHUB_REPOSITORY':ref:refs/heads/testing",
    "description": "Testing branch deployment",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Crear federation credential para pull requests
az ad app federated-credential create \
  --id $APPLICATION_ID \
  --parameters '{
    "name": "witag-pull-requests",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORGANIZATION'/'$GITHUB_REPOSITORY':pull_request",
    "description": "Pull request validation",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

## Paso 3: Asignar Permisos en Azure

### 3.1 Asignar rol de Contributor

```bash
# Obtener el ID de la suscripción
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Asignar rol de Contributor al Service Principal
az role assignment create \
  --assignee $APPLICATION_ID \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

No necesario hasta que configure oicd para bd
### 3.2 Asignar permisos adicionales si es necesario

```bash
# Para crear resource groups
az role assignment create \
  --assignee $APPLICATION_ID \
  --role "Resource Group Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Para manejar identidades
az role assignment create \
  --assignee $APPLICATION_ID \
  --role "Managed Identity Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
```

## Paso 4: Configurar Secretos en GitHub

### 4.1 Obtener información necesaria

```bash
# Obtener Tenant ID
TENANT_ID=$(az account show --query tenantId --output tsv)

# Obtener Subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# El Application ID ya lo tienes del paso 1.2
echo "APPLICATION_ID: $APPLICATION_ID"
echo "TENANT_ID: $TENANT_ID"
echo "SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

### 4.2 Configurar secretos en GitHub

Ve a tu repositorio GitHub → Settings → Secrets and variables → Actions → New repository secret

Crear los siguientes secretos:

- **Name**: `AZURE_CLIENT_ID`
  - **Value**: `<APPLICATION_ID>`

- **Name**: `AZURE_TENANT_ID`
  - **Value**: `<TENANT_ID>`

- **Name**: `AZURE_SUBSCRIPTION_ID`
  - **Value**: `<SUBSCRIPTION_ID>`

## Paso 5: Verificar la Configuración

### 5.1 Script de verificación

```bash
#!/bin/bash
# verify-oidc-setup.sh

echo "Verificando configuración OIDC..."

# Verificar que la aplicación existe
echo "1. Verificando aplicación en Azure AD..."
az ad app show --id $APPLICATION_ID --query "displayName" --output tsv

# Verificar federation credentials
echo "2. Verificando federation credentials..."
az ad app federated-credential list --id $APPLICATION_ID --query "[].name" --output tsv

# Verificar role assignments
echo "3. Verificando role assignments..."
az role assignment list --assignee $APPLICATION_ID --query "[].{Role:roleDefinitionName, Scope:scope}" --output table

echo "Configuración OIDC completada ✅"
```

### 5.2 Ejecutar el script de verificación

```bash
chmod +x verify-oidc-setup.sh
./verify-oidc-setup.sh
```

## Paso 6: Probar la Configuración

### 6.1 Crear un workflow de prueba

Crear `.github/workflows/test-oidc.yml`:

```yaml
name: Test OIDC Authentication

on:
  workflow_dispatch:

jobs:
  test-auth:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login via OIDC
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Test Azure CLI
        run: |
          az account show
          az group list --query "[].name" --output table
```

### 6.2 Ejecutar el workflow

1. Ve a tu repositorio → Actions
2. Selecciona el workflow "Test OIDC Authentication"
3. Haz clic en "Run workflow"
4. Verifica que se ejecute correctamente

## Solución de Problemas

### Error: "The request to create a federated credential failed"

**Causa**: El Application ID no es correcto o no tienes permisos.

**Solución**: Verifica el Application ID y asegúrate de tener permisos de administrador.

### Error: "AADSTS70021: No matching federated identity record found"

**Causa**: La configuración de federation credential no coincide con el repositorio/rama.

**Solución**: Verifica que el subject en la federation credential coincida exactamente con tu repositorio.

### Error: "Insufficient privileges to complete the operation"

**Causa**: El Service Principal no tiene los permisos necesarios.

**Solución**: Asigna los roles necesarios al Service Principal.

## Seguridad

### Principio de Menor Privilegio

- Asigna solo los permisos mínimos necesarios
- Usa scopes específicos en lugar de toda la suscripción cuando sea posible
- Revisa regularmente los permisos asignados

### Monitoreo

- Configura alertas para actividad inusual
- Revisa los logs de Azure AD regularmente
- Monitorea el uso de los workflows

## Mantenimiento

### Renovación de Credenciales

Las credenciales OIDC no expiran, pero debes:

1. Revisar los federation credentials regularmente
2. Actualizar si cambias la estructura del repositorio
3. Eliminar federation credentials no utilizados

### Backup de Configuración

```bash
# Exportar configuración actual
az ad app show --id $APPLICATION_ID > app-config-backup.json
az ad app federated-credential list --id $APPLICATION_ID > federated-credentials-backup.json
az role assignment list --assignee $APPLICATION_ID > role-assignments-backup.json
```

## Referencias

- [Azure AD Workload Identity](https://docs.microsoft.com/en-us/azure/active-directory/workload-identities/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/) 