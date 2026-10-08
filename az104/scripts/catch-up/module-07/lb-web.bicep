// lb-web.bicep — rattrapage M7 : Load Balancer public du portail client (lab 07.4)
// lbe-stNN-web (Standard), IP frontale pip-stNN-lbe-web zone-redondante, sonde HTTP /,
// règle TCP 80 sans SNAT sortant (sortie Internet assurée par la passerelle NAT ng-stNN-app).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

param location string = resourceGroup().location

var prefix = 'st${numero}'
var lbName = 'lbe-${prefix}-web'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource pip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${prefix}-lbe-web'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource lb 'Microsoft.Network/loadBalancers@2023-11-01' = {
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
        name: 'fe-web'
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'bp-web'
      }
    ]
    probes: [
      {
        name: 'hp-http'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 5
          numberOfProbes: 1
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-web')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-web')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'hp-http')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
          disableOutboundSnat: true
        }
      }
    ]
  }
}

output backendPoolId string = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-web')
output publicIp string = pip.properties.ipAddress
