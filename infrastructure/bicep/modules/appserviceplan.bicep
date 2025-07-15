@description('App Service Plan name')
param planName string

@description('Location for the App Service Plan')
param location string

@description('Client name')
param clientName string

@description('Environment name')
param environmentName string

@description('App Service Plan SKU')
param skuName string = 'Y1'

@description('App Service Plan tier')
param skuTier string = 'Dynamic'

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  kind: 'functionapp'
  properties: {
    reserved: false
  }
  tags: {
    environment: environmentName
    client: clientName
    solution: 'witag'
    managedBy: 'bicep'
  }
}

// Outputs
output planId string = appServicePlan.id
output planName string = appServicePlan.name 