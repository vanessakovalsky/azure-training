// firewall.bicep — Azure Firewall Basic du hub Arvéo (rg-stNN-hub)
// Prérequis : vnet-stNN-hub avec AzureFirewallSubnet et AzureFirewallManagementSubnet
// (créés par scripts/prereq-vpn-gateways.sh). Déploiement : 5 à 15 min.
// La stratégie afwp-stNN-hub est créée VIDE : tout flux est refusé tant qu'aucune règle n'existe.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région de déploiement (celle du hub)')
@allowed([ 'francecentral' ])
param location string = 'francecentral'

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: 'vnet-${prefix}-hub'
}

// IP publique du trafic (SNAT sortant, DNAT entrant)
resource pipFw 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${prefix}-fw'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// IP publique de gestion, exigée par le niveau Basic (trafic de la plateforme uniquement)
resource pipFwMgmt 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${prefix}-fw-mgmt'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource policy 'Microsoft.Network/firewallPolicies@2023-11-01' = {
  name: 'afwp-${prefix}-hub'
  location: location
  tags: tags
  properties: {
    sku: {
      tier: 'Basic'
    }
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
  name: 'afw-${prefix}-hub'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    firewallPolicy: {
      id: policy.id
    }
    ipConfigurations: [
      {
        name: 'ipconfig-trafic'
        properties: {
          subnet: {
            id: '${hubVnet.id}/subnets/AzureFirewallSubnet'
          }
          publicIPAddress: {
            id: pipFw.id
          }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'ipconfig-gestion'
      properties: {
        subnet: {
          id: '${hubVnet.id}/subnets/AzureFirewallManagementSubnet'
        }
        publicIPAddress: {
          id: pipFwMgmt.id
        }
      }
    }
  }
}

output firewallPrivateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallPublicIp string = pipFw.properties.ipAddress
output policyName string = policy.name
