targetScope = 'subscription'

// Test parameters
param testAccountName string = 'cosmos-test-simple-2025'
param testDatabaseName string = 'witag-db'
param testLocation string = 'Australia East'
param testClientName string = 'elite'
param testEnvironmentName string = 'main'
param testResourceGroup string = 'rg-test-cosmosdb-simple'

// Create resource group
resource testRG 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: testResourceGroup
  location: testLocation
}

// Import the simplified cosmosdb module
module testCosmosDb 'infrastructure/bicep/modules/cosmosdb-simple.bicep' = {
  name: 'test-cosmosdb-simple'
  scope: testRG
  params: {
    accountName: testAccountName
    databaseName: testDatabaseName
    location: testLocation
    clientName: testClientName
    environmentName: testEnvironmentName
  }
}

// Test outputs
output testAccountName string = testCosmosDb.outputs.accountName
output testDatabaseName string = testCosmosDb.outputs.databaseName
output testEndpoint string = testCosmosDb.outputs.endpoint
