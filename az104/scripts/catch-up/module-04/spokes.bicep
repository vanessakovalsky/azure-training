// spokes.bicep — module du rattrapage M4, déployé dans rg-stNN-spoke
// vnet-stNN-spoke-app, vnet-stNN-spoke-data, NSG, ASG, tables de routes,
// peerings spoke → hub, VMs de test.
targetScope = 'resourceGroup'

param numero string
param location string
param hubVnetId string
param firewallPrivateIp string

@description('Clé publique SSH des VMs de test (accès par run-command uniquement)')
param sshPublicKey string

param vmSize string = 'Standard_B2s_v2'
param adminUsername string = 'arveoadmin'

@description('false si les VMs de test existent déjà (création seule : clé SSH et customData non modifiables)')
param deployTestVms bool = true

var prefix = 'st${numero}'
var octet = int(numero)
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

// ---------- Filtrage (S4.2) ----------
resource asgData 'Microsoft.Network/applicationSecurityGroups@2023-11-01' = {
  name: 'asg-${prefix}-data'
  location: location
  tags: tags
}

resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}-web'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-HTTPS-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
    ]
  }
}

resource nsgData 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}-data'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SQL-From-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.${octet}.4.0/24'
          sourcePortRange: '*'
          destinationApplicationSecurityGroups: [
            {
              id: asgData.id
            }
          ]
          destinationPortRange: '1433'
        }
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------- Routage (S4.3) ----------
resource rtApp 'Microsoft.Network/routeTables@2023-11-01' = {
  name: 'rt-${prefix}-spoke-app'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'default-via-fw'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

resource rtData 'Microsoft.Network/routeTables@2023-11-01' = {
  name: 'rt-${prefix}-spoke-data'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'default-via-fw'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

// ---------- Réseaux (S4.1) ----------
resource spokeApp 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${prefix}-spoke-app'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.${octet}.4.0/22'
      ]
    }
    subnets: [
      {
        name: 'snet-web'
        properties: {
          addressPrefix: '10.${octet}.4.0/24'
          networkSecurityGroup: {
            id: nsgWeb.id
          }
          routeTable: {
            id: rtApp.id
          }
        }
      }
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.${octet}.5.0/24'
          routeTable: {
            id: rtApp.id
          }
        }
      }
    ]
  }
}

resource spokeData 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${prefix}-spoke-data'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.${octet}.8.0/22'
      ]
    }
    subnets: [
      {
        name: 'snet-data'
        properties: {
          addressPrefix: '10.${octet}.8.0/24'
          networkSecurityGroup: {
            id: nsgData.id
          }
          routeTable: {
            id: rtData.id
          }
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.${octet}.9.0/24'
        }
      }
    ]
  }
}

// ---------- Peerings spoke → hub (S4.3) ----------
resource peerAppToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: spokeApp
  name: 'peer-spoke-app-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource peerDataToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: spokeData
  name: 'peer-spoke-data-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

// ---------- VMs de test ----------
var vms = [
  {
    role: 'web'
    subnetId: '${spokeApp.id}/subnets/snet-web'
    ip: '10.${octet}.4.10'
    asg: false
  }
  {
    role: 'data'
    subnetId: '${spokeData.id}/subnets/snet-data'
    ip: '10.${octet}.8.10'
    asg: true
  }
]

resource nics 'Microsoft.Network/networkInterfaces@2023-11-01' = [for vm in vms: {
  name: 'nic-${prefix}-test-${vm.role}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vm.subnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: vm.ip
          applicationSecurityGroups: vm.asg ? [
            {
              id: asgData.id
            }
          ] : []
        }
      }
    ]
  }
}]

resource testVms 'Microsoft.Compute/virtualMachines@2024-03-01' = [for (vm, i) in vms: if (deployTestVms) {
  name: 'vm-${prefix}-test-${vm.role}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    osProfile: {
      computerName: 'vm-${prefix}-test-${vm.role}'
      adminUsername: adminUsername
      customData: base64(loadTextContent('../../labs/module-04/cloud-init-test.yaml'))
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
  }
}]

output spokeAppId string = spokeApp.id
output spokeDataId string = spokeData.id
