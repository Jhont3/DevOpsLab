targetScope = 'subscription'

// Updated to trigger workflow with simplified connection string fix
@description('Client name (e.g., elite, jarandes, ght)')
param clientName string

@description('Environment name (testing or main)')
param environmentName string

@description('Azure region for resources')
param location string = 'East US'

@description('Resource group name')
param resourceGroupName string

@description('SQL Server name')
param sqlServerName string

@description('SQL Database name')
param sqlDatabaseName string

@description('SQL Server administrator login')
param sqlAdminLogin string

@description('SQL Server administrator password')
@secure()
param sqlAdminPassword string

@description('Core functions to deploy')
param coreFunctions array

@description('Plugin functions to deploy')
param pluginFunctions array

@description('Function mappings configuration')
param functionMappings object

// Resource Group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: {
    environment: environmentName
    client: clientName
    solution: 'witag'
    managedBy: 'bicep'
  }
}

// Storage Account for Function Apps
module storageAccount 'modules/storage.bicep' = {
  name: 'storageAccount-${clientName}-${environmentName}'
  scope: resourceGroup
  params: {
    storageAccountName: 'stwitag${clientName}${environmentName}'
    location: location
    clientName: clientName
    environmentName: environmentName
  }
}

// SQL Server and Database
module sqlServer 'modules/sqlserver.bicep' = {
  name: 'sqlServer-${clientName}-${environmentName}'
  scope: resourceGroup
  params: {
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    location: location
    skuName: 'Basic'
    tier: 'Basic'
    capacity: 5
    tags: {
      environment: environmentName
      client: clientName
      solution: 'witag'
      managedBy: 'bicep'
    }
  }
}

// Application Service Plan for Function Apps
module appServicePlan 'modules/appserviceplan.bicep' = {
  name: 'appServicePlan-${clientName}-${environmentName}'
  scope: resourceGroup
  params: {
    planName: 'asp-witag-${clientName}-${environmentName}'
    location: location
    clientName: clientName
    environmentName: environmentName
  }
}

// Deploy Core Functions
module coreFunctionApps 'modules/functionapp.bicep' = [for functionName in coreFunctions: {
  name: 'coreFunction-${functionName}-${clientName}-${environmentName}'
  scope: resourceGroup
  params: {
    functionAppName: '${functionName}-${clientName}-${environmentName}'
    location: location
    clientName: clientName
    environmentName: environmentName
    functionType: functionMappings[functionName].type
    appServicePlanId: appServicePlan.outputs.planId
    storageAccountName: storageAccount.outputs.storageAccountName
    storageAccountKey: storageAccount.outputs.storageAccountKey
    cosmosDbConnectionString: 'Server=${sqlServer.outputs.sqlServerFqdn};Database=${sqlServer.outputs.sqlDatabaseName};User ID=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=true;Connection Timeout=30;'
    cosmosDbName: sqlDatabaseName
  }
  // Dependencies are automatically managed by Bicep based on parameter references
}]

// Deploy Plugin Functions
module pluginFunctionApps 'modules/functionapp.bicep' = [for functionName in pluginFunctions: {
  name: 'pluginFunction-${functionName}-${clientName}-${environmentName}'
  scope: resourceGroup
  params: {
    functionAppName: '${functionName}-${clientName}-${environmentName}'
    location: location
    clientName: clientName
    environmentName: environmentName
    functionType: functionMappings[functionName].type
    appServicePlanId: appServicePlan.outputs.planId
    storageAccountName: storageAccount.outputs.storageAccountName
    storageAccountKey: storageAccount.outputs.storageAccountKey
    cosmosDbConnectionString: 'Server=${sqlServer.outputs.sqlServerFqdn};Database=${sqlServer.outputs.sqlDatabaseName};User ID=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=true;Connection Timeout=30;'
    cosmosDbName: sqlDatabaseName
  }
}]

// Outputs
output resourceGroupName string = resourceGroup.name
output appServicePlanId string = appServicePlan.outputs.planId
output storageAccountName string = storageAccount.outputs.storageAccountName
output sqlServerName string = sqlServer.outputs.sqlServerName
output sqlServerFqdn string = sqlServer.outputs.sqlServerFqdn
output sqlDatabaseName string = sqlServer.outputs.sqlDatabaseName

output coreFunctionApps array = [for (functionName, i) in coreFunctions: {
  name: functionName
  functionAppName: coreFunctionApps[i].outputs.functionAppName
  defaultHostName: coreFunctionApps[i].outputs.defaultHostName
}]

output pluginFunctionApps array = [for (functionName, i) in pluginFunctions: {
  name: functionName
  functionAppName: pluginFunctionApps[i].outputs.functionAppName
  defaultHostName: pluginFunctionApps[i].outputs.defaultHostName
}]
