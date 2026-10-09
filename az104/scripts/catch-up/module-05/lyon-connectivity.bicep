// lyon-connectivity.bicep — flux hybrides Lyon ↔ spokes Arvéo (solution du défi 05.3)
// Déployé dans rg-stNN-hub. Prérequis : état de fin du module 4 (pare-feu, stratégie, NSG/ASG).
//   - rt-stNN-gateway associée à GatewaySubnet : spokes → pare-feu (routage symétrique)
//   - groupe de collections rcg-lyon dans afwp-stNN-hub : Lyon → web (80, 443), Lyon → données (1433)
//   - règle Allow-SQL-From-Lyon dans nsg-stNN-data (module lyon-nsg-rule.bicep, rg-stNN-spoke)
// Déploiement : az deployment group create -g rg-stNN-hub -f lyon-connectivity.bicep -p numero=NN
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région du hub')
@allowed([ 'francecentral' ])
param location string = 'francecentral'

var prefix = 'st${numero}'
var octet = int(numero)
var lyonSubnet = '10.200.${octet}.0/24'
var spokes = [
  {
    name: 'spoke-app-via-fw'
    prefix: '10.${octet}.4.0/22'
  }
  {
    name: 'spoke-data-via-fw'
    prefix: '10.${octet}.8.0/22'
  }
]
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: 'vnet-${prefix}-hub'
}

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' existing = {
  name: 'afw-${prefix}-hub'
}

resource policy 'Microsoft.Network/firewallPolicies@2023-11-01' existing = {
  name: 'afwp-${prefix}-hub'
}

var firewallPrivateIp = firewall.properties.ipConfigurations[0].properties.privateIPAddress

// ---------- Routage : GatewaySubnet → pare-feu ----------
resource rtGateway 'Microsoft.Network/routeTables@2023-11-01' = {
  name: 'rt-${prefix}-gateway'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false // obligatoire sur GatewaySubnet
    routes: [for spoke in spokes: {
      name: spoke.name
      properties: {
        addressPrefix: spoke.prefix
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: firewallPrivateIp
      }
    }]
  }
}

// Sous-réseau existant redéclaré à l'identique, table de routes en plus
resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: hubVnet
  name: 'GatewaySubnet'
  properties: {
    addressPrefix: '10.${octet}.0.0/27'
    routeTable: {
      id: rtGateway.id
    }
  }
}

// ---------- Filtrage : pare-feu ----------
resource rcgLyon 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: policy
  name: 'rcg-lyon'
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-lyon-autoriser'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-web'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.4.0/24'
            ]
            destinationPorts: [
              '80'
              '443'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-data-sql'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.8.0/24'
            ]
            destinationPorts: [
              '1433'
            ]
          }
        ]
      }
    ]
  }
}

// ---------- Filtrage : NSG du spoke données ----------
module nsgRule 'lyon-nsg-rule.bicep' = {
  name: 'lyon-nsg-rule'
  scope: resourceGroup('rg-${prefix}-spoke')
  params: {
    numero: numero
  }
}

output firewallPrivateIp string = firewallPrivateIp
output gatewaySubnetRouteTable string = gatewaySubnet.properties.routeTable.id
