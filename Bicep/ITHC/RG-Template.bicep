targetScope = 'subscription'

param rgName string
param location string = 'uksouth'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
}
