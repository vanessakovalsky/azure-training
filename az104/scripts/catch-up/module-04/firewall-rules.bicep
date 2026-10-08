// firewall-rules.bicep — règles du pare-feu Arvéo (solution du défi 04.4)
// Ajoute le groupe de collections rcg-arveo à la stratégie existante afwp-stNN-hub.
// Déploiement : az deployment group create -g rg-stNN-hub -f firewall-rules.bicep -p numero=NN
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('FQDN autorisés en sortie depuis les spokes (HTTP et HTTPS)')
param allowedFqdns array = [
  '*.ubuntu.com'
]

var prefix = 'st${numero}'
var octet = int(numero)
var webSubnet = '10.${octet}.4.0/24'
var dataSubnet = '10.${octet}.8.0/24'
var spokeApp = '10.${octet}.4.0/22'
var spokeData = '10.${octet}.8.0/22'

resource policy 'Microsoft.Network/firewallPolicies@2023-11-01' existing = {
  name: 'afwp-${prefix}-hub'
}

resource rcg 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: policy
  name: 'rcg-arveo'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-reseau-autoriser'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'web-vers-data-sql'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              webSubnet
            ]
            destinationAddresses: [
              dataSubnet
            ]
            destinationPorts: [
              '1433'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-application-autoriser'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'spokes-vers-depots-ubuntu'
            sourceAddresses: [
              spokeApp
              spokeData
            ]
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: allowedFqdns
          }
        ]
      }
    ]
  }
}
