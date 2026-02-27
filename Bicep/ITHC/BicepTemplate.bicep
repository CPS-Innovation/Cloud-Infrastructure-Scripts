param vnetName string
param routeTableName string
param pipName string
param firewallAddress string
param vnetAddressRange string
param nicName string

param location string = resourceGroup().location
param subnetName string = 'default'

param dnsServers array

resource routeTable 'Microsoft.Network/routeTables@2022-09-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'default-route-to-appliance'
        properties: {
          addressPrefix: '10.0.0.0/8'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallAddress 
        }
      }
    ]
  }
}

resource VNet 'Microsoft.Network/virtualNetworks@2022-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressRange
      ]
    }
    dhcpOptions: {
      dnsServers: dnsServers
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: vnetAddressRange
          routeTable: {
            id: routeTable.id
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

resource nic 'Microsoft.Network/networkInterfaces@2022-09-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: VNet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
  }
}
