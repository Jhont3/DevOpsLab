@description('Cosmos DB account name')
param accountName string

@description('Database name')
param databaseName string

@description('Location for the Cosmos DB account')
param location string

@description('Client name')
param clientName string

@description('Environment name')
param environmentName string

// Cosmos DB Account - Ultra minimal Serverless configuration
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2022-11-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
  tags: {
    environment: environmentName
    client: clientName
    solution: 'witag'
    managedBy: 'bicep'
  }
}

// Cosmos DB Database - Ultra minimal configuration
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-11-15' = {
  name: databaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// Outputs
output accountName string = cosmosAccount.name
output databaseName string = cosmosDatabase.name
output connectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
output endpoint string = cosmosAccount.properties.documentEndpoint
output primaryKey string = cosmosAccount.listKeys().primaryMasterKey
