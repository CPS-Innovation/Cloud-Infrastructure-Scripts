param location string = resourceGroup().location
param vnetName string = 'myVNet'
param subnetName string = 'mySubnet'
param routeTableName string = 'myRouteTable'
param virtualApplianceIp string = '10.0.2.4'
param pipName string = 'myPIP'

param dnsServers array = [
  '10.1.1.4'
  '10.1.1.5'
]

// -----------------------------
// Create Route Table
// -----------------------------
resource myRouteTable 'Microsoft.Network/routeTables@2022-09-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'default-route-to-appliance'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: virtualApplianceIp
        }
      }
    ]
  }
}

// -----------------------------
// Create VNet + Subnet with DNS and Route Table
// -----------------------------
resource myVNet 'Microsoft.Network/virtualNetworks@2022-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    dhcpOptions: {
      dnsServers: dnsServers
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          routeTable: {
            id: myRouteTable.id
          }
        }
      }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2022-09-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static' // Standard requires Static or leave as Dynamic
  }
}



