param vnetName string
param routeTableName string
param pipName string
param firewallAddress string
param vnetAddressRange string
param nicName string
param externalAccessIP string
param dnsName string

param startDate string
param pm string

param osDiskName string

@secure()
param adminPassword string

param adminUsername string = 'azureuser'

param vmName string

var tags = {
  ProjectManager: pm
  StartDate: startDate
}

param location string = resourceGroup().location
param subnetName string = 'default'

param dnsServers array

param nsgName string

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-SIPA'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '51.11.141.254'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-From-SIPA2'
        properties: {
          priority: 105
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '52.142.147.85'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-SSH-From-External'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: externalAccessIP
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource routeTable 'Microsoft.Network/routeTables@2022-09-01' = {
  name: routeTableName
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'default-route-to-hub'
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
  tags: tags
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
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2022-09-01' = {
  name: pipName
  tags: tags
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsName
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2022-09-01' = {
  name: nicName
  tags: tags
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

resource VMMachineObject 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  tags: tags
  location: 'uksouth'
  plan: {
    name: 'kali-2025-4'
    product: 'kali'
    publisher: 'kali-linux'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    storageProfile: {
      imageReference: {
        publisher: 'kali-linux'
        offer: 'kali'
        sku: 'kali-2025-4'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: osDiskName
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
        diskSizeGB: 25
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
      secrets: []
      allowExtensionOperations: true
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Detach'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}
