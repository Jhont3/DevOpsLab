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

@description('Collections configuration')
param collections array

// Cosmos DB Account - Minimal Serverless configuration
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    // Minimal configuration - let Azure handle defaults
  }
  tags: {
    environment: environmentName
    client: clientName
    solution: 'witag'
    managedBy: 'bicep'
  }
}

// Cosmos DB Database - Minimal configuration
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  name: databaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// Cosmos DB Containers - Minimal configuration
resource cosmosContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = [for collection in collections: {
  name: collection.name
  parent: cosmosDatabase
  properties: {
    resource: {
      id: collection.name
      partitionKey: {
        paths: [
          collection.partitionKey
        ]
        kind: 'Hash'
      }
    }
  }
}]

// Outputs
output accountName string = cosmosAccount.name
output databaseName string = cosmosDatabase.name
output connectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
output endpoint string = cosmosAccount.properties.documentEndpoint
output primaryKey string = cosmosAccount.listKeys().primaryMasterKey
