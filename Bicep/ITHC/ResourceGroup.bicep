targetScope = 'subscription'

param rgName string
param location string

param startDate string
param endDate string
param pm string

var tags = {
  ProjectManager: pm
  StartDate: startDate
  EndDate: endDate
}

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: tags
}
