// main.bicep — rattrapage module 04 : réseau hub-spoke Arvéo
// Déployé dans rg-stNN-hub ; le module spokes.bicep cible rg-stNN-spoke.
// Prérequis : vnet-stNN-hub et ses sous-réseaux (scripts/prereq-vpn-gateways.sh, relancé par deploy.sh).
// État obtenu = fin du module 4 : spokes, NSG/ASG, pare-feu + règles, UDR, peerings, DNS.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région de déploiement')
@allowed([ 'francecentral', 'westeurope' ])
param location string = 'francecentral'

@description('Clé publique SSH des VMs de test')
param sshPublicKey string

@description('false si les VMs de test existent déjà')
param deployTestVms bool = true

var prefix = 'st${numero}'
var octet = int(numero)
var spokeRg = 'rg-${prefix}-spoke'
var spokeAppId = resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-app')
var spokeDataId = resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-data')
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: 'vnet-${prefix}-hub'
}

// ---------- Pare-feu (S4.3) ----------
module firewall '../../labs/module-04/firewall.bicep' = {
  name: 'rattrapage-m04-firewall'
  params: {
    numero: numero
    location: location
  }
}

module firewallRules 'firewall-rules.bicep' = {
  name: 'rattrapage-m04-regles'
  params: {
    numero: numero
  }
  dependsOn: [
    firewall
  ]
}

// ---------- Spokes (S4.1, S4.2, S4.3) ----------
module spokes 'spokes.bicep' = {
  name: 'rattrapage-m04-spokes'
  scope: resourceGroup(spokeRg)
  params: {
    numero: numero
    location: location
    hubVnetId: hubVnet.id
    firewallPrivateIp: firewall.outputs.firewallPrivateIp
    sshPublicKey: sshPublicKey
    deployTestVms: deployTestVms
  }
}

// ---------- Peerings hub → spokes (S4.3) ----------
resource peerHubToApp 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke-app'
  properties: {
    remoteVirtualNetwork: {
      id: spokes.outputs.spokeAppId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource peerHubToData 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke-data'
  properties: {
    remoteVirtualNetwork: {
      id: spokes.outputs.spokeDataId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
  dependsOn: [
    peerHubToApp
  ]
}

// ---------- DNS privé (S4.4) ----------
resource privateZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'arveo.internal'
  location: 'global'
  tags: tags
}

var links = [
  {
    name: 'link-hub'
    vnetId: hubVnet.id
    registration: false
  }
  {
    name: 'link-spoke-app'
    vnetId: spokeAppId
    registration: true
  }
  {
    name: 'link-spoke-data'
    vnetId: spokeDataId
    registration: true
  }
]

resource zoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for link in links: {
  parent: privateZone
  name: link.name
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: link.vnetId
    }
    registrationEnabled: link.registration
  }
  dependsOn: [
    spokes
  ]
}]

resource sqlRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateZone
  name: 'sql'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.${octet}.8.10'
      }
    ]
  }
}

// ---------- DNS public (S4.4) ----------
resource publicZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: 'arveo-${prefix}.fr'
  location: 'global'
  tags: tags
}

resource wwwRecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: publicZone
  name: 'www'
  properties: {
    TTL: 300
    ARecords: [
      {
        ipv4Address: firewall.outputs.firewallPublicIp
      }
    ]
  }
}

output firewallPrivateIp string = firewall.outputs.firewallPrivateIp
output firewallPublicIp string = firewall.outputs.firewallPublicIp
output publicNameServers array = publicZone.properties.nameServers
