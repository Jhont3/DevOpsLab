targetScope = 'resourceGroup'

// Test parameters
param testAccountName string = 'cosmos-test-elite-main-2025'
param testDatabaseName string = 'witag-db'
param testLocation string = 'East US'
param testClientName string = 'elite'
param testEnvironmentName string = 'main'
param testCollections array = [
  {
    name: 'usuarios'
    partitionKey: '/id'
  }
  {
    name: 'animales'
    partitionKey: '/id'
  }
]

// Import the cosmosdb module
module testCosmosDb 'infrastructure/bicep/modules/cosmosdb.bicep' = {
  name: 'test-cosmosdb'
  params: {
    accountName: testAccountName
    databaseName: testDatabaseName
    location: testLocation
    clientName: testClientName
    environmentName: testEnvironmentName
    collections: testCollections
  }
}

// Test outputs
output testAccountName string = testCosmosDb.outputs.accountName
output testDatabaseName string = testCosmosDb.outputs.databaseName
output testEndpoint string = testCosmosDb.outputs.endpoint
