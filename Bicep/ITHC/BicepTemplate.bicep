param vnetName string
param routeTableName string
param pipName string
param firewallAddress string
param vnetAddressRange string
param nicName string

param startDate string
param pm string

var tags = {
  ProjectManager: pm
  StartDate: startDate
}

param location string = resourceGroup().location
param subnetName string = 'default'

param dnsServers array

resource routeTable 'Microsoft.Network/routeTables@2022-09-01' = {
  name: routeTableName
  location: location
  tags: tags
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
    publicIPAllocationMethod: 'Static' // Standard requires Static or leave as Dynamic
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

param disks_TESTVM_OsDisk_1_df0b103f6d824afc9916e908a0213f8e_name string = 'TESTVM_OsDisk_1_df0b103f6d824afc9916e908a0213f8edvv'

resource disks_TESTVM_OsDisk_1_df0b103f6d824afc9916e908a0213f8e_name_resource 'Microsoft.Compute/disks@2025-01-02' = {
  name: disks_TESTVM_OsDisk_1_df0b103f6d824afc9916e908a0213f8e_name
  location: 'uksouth'
  tags: tags
  sku: {
    name: 'Premium_LRS'
    tier: 'Premium'
  }
  properties: {
    osType: 'Linux'
    hyperVGeneration: 'V2'
    purchasePlan: {
      name: 'kali-2025-4'
      publisher: 'kali-linux'
      product: 'kali'
    }
    supportsHibernation: false
    supportedCapabilities: {
      diskControllerTypes: 'SCSI'
      acceleratedNetwork: false
      architecture: 'x64'
    }
    creationData: {
      createOption: 'FromImage'
      imageReference: {
        id: '/Subscriptions/8587dc13-9243-4af2-94ef-d95428bad513/Providers/Microsoft.Compute/Locations/uksouth/Publishers/kali-linux/ArtifactTypes/VMImage/Offers/kali/Skus/kali-2025-4/Versions/2025.4.0'
      }
    }
    diskSizeGB: 25
    diskIOPSReadWrite: 120
    diskMBpsReadWrite: 25
    encryption: {
      type: 'EncryptionAtRestWithPlatformKey'
    }
    networkAccessPolicy: 'AllowAll'
    publicNetworkAccess: 'Enabled'
    tier: 'P4'
  }
}

@secure()
param adminPassword string

resource VMMachine 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'testvm2'
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
        name: 'testDisk'
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
      computerName: 'testvm2'
      adminUsername: 'azureuser'
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
