// vmss-api.bicep — rattrapage M7 et solution du défi 07.5 : API de suivi des colis
// Déployé dans rg-stNN-app :
//   - nsg-stNN-app : filtrage de snet-app (association au sous-réseau par CLI, cf. deploy.sh) ;
//   - lbi-stNN-api : Load Balancer interne Standard, frontal 10.NN.5.100 zone-redondant, TCP 8080 ;
//   - vmss-stNN-api : groupe identique (VMSS) Flexible, zones 1 2 3, 2 instances ;
//   - as-stNN-api : mise à l'échelle automatique 2 à 4 instances sur le CPU moyen.
// Le sous-réseau snet-app (rg-stNN-spoke) n'est PAS redéclaré : un PUT de sous-réseau
// réécrirait toutes ses propriétés (passerelle NAT, NSG, table de routes).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Mot de passe administrateur (fichier ~/.arveo/web-admin.txt)')
@secure()
param adminPassword string

param location string = resourceGroup().location
param vmSize string = 'Standard_B2s_v2'
param adminUsername string = 'arveoadmin'

@minValue(1)
param minInstances int = 2

@minValue(1)
param maxInstances int = 4

var prefix = 'st${numero}'
var octet = int(numero)
var lbName = 'lbi-${prefix}-api'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource snetApp 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  scope: resourceGroup('rg-${prefix}-spoke')
  name: 'vnet-${prefix}-spoke-app/snet-app'
}

// ---------- Filtrage de snet-app ----------
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}-app'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-API-From-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.${octet}.4.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.${octet}.1.0/26'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
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

// ---------- Équilibreur interne ----------
resource ilb 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: lbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-api'
        zones: [
          '1'
          '2'
          '3'
        ]
        properties: {
          subnet: {
            id: snetApp.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.${octet}.5.100'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'bp-api'
      }
    ]
    probes: [
      {
        name: 'hp-api'
        properties: {
          protocol: 'Http'
          port: 8080
          requestPath: '/'
          intervalInSeconds: 5
          numberOfProbes: 1
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-api'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-api')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-api')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'hp-api')
          }
          protocol: 'Tcp'
          frontendPort: 8080
          backendPort: 8080
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
        }
      }
    ]
  }
}

// ---------- Groupe identique Flexible ----------
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-03-01' = {
  name: 'vmss-${prefix}-api'
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: minInstances
  }
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'api${numero}'
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: base64(loadTextContent('../../labs/module-07/cloud-init-api.yaml'))
        linuxConfiguration: {
          disablePasswordAuthentication: false
        }
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
            storageAccountType: 'StandardSSD_LRS'
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
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true // stockage managé : aucun compte à gérer pour des instances éphémères
        }
      }
      networkProfile: {
        networkApiVersion: '2020-11-01'
        networkInterfaceConfigurations: [
          {
            name: 'nic-${prefix}-api'
            properties: {
              primary: true
              deleteOption: 'Delete'
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: snetApp.id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-api')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    ilb
  ]
}

// ---------- Mise à l'échelle automatique ----------
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'as-${prefix}-api'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'profil-cpu'
        capacity: {
          minimum: string(minInstances)
          maximum: string(maxInstances)
          default: string(minInstances)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

output nsgId string = nsgApp.id
output apiFrontendIp string = '10.${octet}.5.100'
