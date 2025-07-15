targetScope = 'subscription'

@description('Client name (e.g., elite, jarandes, ght)')
param clientName string

@description('Environment name (testing or main)')
param environmentName string

@description('Azure region for resources')
param location string = 'East US'

@description('Resource group name')
param resourceGroupName string

@description('Cosmos DB account name')
param cosmosDbAccountName string

@description('Cosmos DB database name')
param cosmosDbName string

@description('Core functions to deploy')
param coreFunctions array

@description('Plugin functions to deploy')
param pluginFunctions array

@description('Function mappings configuration')
param functionMappings object

@description('Cosmos DB collections configuration')
param cosmosCollections array

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

// Cosmos DB
module cosmosDb 'modules/cosmosdb.bicep' = {
  name: 'cosmosDb-${clientName}-${environmentName}'
  scope: resourceGroup
  params: {
    accountName: cosmosDbAccountName
    databaseName: cosmosDbName
    location: location
    clientName: clientName
    environmentName: environmentName
    collections: cosmosCollections
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
    cosmosDbConnectionString: cosmosDb.outputs.connectionString
    cosmosDbName: cosmosDbName
  }
  dependsOn: [
    appServicePlan
    storageAccount
    cosmosDb
  ]
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
    cosmosDbConnectionString: cosmosDb.outputs.connectionString
    cosmosDbName: cosmosDbName
  }
  dependsOn: [
    appServicePlan
    storageAccount
    cosmosDb
  ]
}]

// Outputs
output resourceGroupName string = resourceGroup.name
output cosmosDbAccountName string = cosmosDb.outputs.accountName
output cosmosDbConnectionString string = cosmosDb.outputs.connectionString
output storageAccountName string = storageAccount.outputs.storageAccountName
output appServicePlanId string = appServicePlan.outputs.planId
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