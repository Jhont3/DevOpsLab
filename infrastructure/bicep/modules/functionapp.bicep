@description('Function App name')
param functionAppName string

@description('Location for the Function App')
param location string

@description('Client name')
param clientName string

@description('Environment name')
param environmentName string

@description('Function type (backend or frontend)')
param functionType string

@description('App Service Plan ID')
param appServicePlanId string

@description('Storage Account name')
param storageAccountName string

@description('Storage Account key')
@secure()
param storageAccountKey string

@description('Cosmos DB connection string')
param cosmosDbConnectionString string

@description('Cosmos DB database name')
param cosmosDbName string

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlanId
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'CosmosDbConnectionString'
          value: cosmosDbConnectionString
        }
        {
          name: 'CosmosDbName'
          value: cosmosDbName
        }
        {
          name: 'CLIENT_NAME'
          value: clientName
        }
        {
          name: 'ENVIRONMENT_NAME'
          value: environmentName
        }
        {
          name: 'FUNCTION_TYPE'
          value: functionType
        }
      ]
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          '*'
        ]
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: false
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  tags: {
    environment: environmentName
    client: clientName
    solution: 'witag'
    managedBy: 'bicep'
    functionType: functionType
  }
}

// Outputs
output functionAppName string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output functionAppId string = functionApp.id 