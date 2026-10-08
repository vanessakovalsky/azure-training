// main.bicep — rattrapage module 05 : connectivité inter-sites Arvéo
// Déployé dans rg-stNN-hub ; les modules pra-vnet, spoke-peerings et lyon-nsg-rule ciblent rg-stNN-spoke.
// Prérequis : état de fin du module 4, passerelle vpngw-stNN-hub en Succeeded,
// côté Lyon prêt (formatrice : lyon-site.sh prepare puis connect).
// État obtenu = fin du module 5 : transit de passerelle, spoke PRA en peering global,
// tunnel S2S vers Lyon, GatewaySubnet routé vers le pare-feu, règles Lyon (pare-feu + NSG).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région du hub')
@allowed([ 'francecentral', 'westeurope' ])
param location string = 'francecentral'

@description('Clé partagée du tunnel, identique à celle de cn-lyon-to-stNN')
@secure()
param psk string

@description('Groupe de ressources du site de Lyon simulé (formatrice)')
param lyonResourceGroup string = 'rg-formation-lyon'

@description('false si vnet-stNN-spoke-pra existe déjà (une redéclaration risquerait ses peerings)')
param deployPraVnet bool = true

var prefix = 'st${numero}'
var octet = int(numero)
var spokeRg = 'rg-${prefix}-spoke'
var spokeIds = {
  app: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-app')
  data: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-data')
}
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: 'vnet-${prefix}-hub'
}

resource hubGateway 'Microsoft.Network/virtualNetworkGateways@2023-11-01' existing = {
  name: 'vpngw-${prefix}-hub'
}

resource lyonPip 'Microsoft.Network/publicIPAddresses@2023-11-01' existing = {
  name: 'pip-lyon-vpngw'
  scope: resourceGroup(lyonResourceGroup)
}

// ---------- S5.1 : transit de passerelle (liens du hub) ----------
@batchSize(1)
resource hubToSpokes 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = [for spoke in items(spokeIds): {
  parent: hubVnet
  name: 'peer-hub-to-spoke-${spoke.key}'
  properties: {
    remoteVirtualNetwork: {
      id: spoke.value
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}]

// ---------- S5.1 : spoke PRA en West Europe (peering global) ----------
module praVnet 'pra-vnet.bicep' = if (deployPraVnet) {
  name: 'rattrapage-m05-pra'
  scope: resourceGroup(spokeRg)
  params: {
    numero: numero
  }
}

resource hubToPra 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke-pra'
  properties: {
    remoteVirtualNetwork: {
      id: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-pra')
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
  dependsOn: [
    praVnet
    hubToSpokes
  ]
}

module spokePeerings 'spoke-peerings.bicep' = {
  name: 'rattrapage-m05-peerings'
  scope: resourceGroup(spokeRg)
  params: {
    numero: numero
    hubVnetId: hubVnet.id
  }
  dependsOn: [
    hubToSpokes
    hubToPra
  ]
}

// ---------- S5.2 : tunnel site-à-site vers Lyon ----------
resource lngLyon 'Microsoft.Network/localNetworkGateways@2023-11-01' = {
  name: 'lng-${prefix}-lyon'
  location: location
  tags: tags
  properties: {
    gatewayIpAddress: lyonPip.properties.ipAddress
    localNetworkAddressSpace: {
      addressPrefixes: [
        '10.200.${octet}.0/24'
      ]
    }
  }
}

resource connection 'Microsoft.Network/connections@2023-11-01' = {
  name: 'cn-${prefix}-hub-to-lyon'
  location: location
  tags: tags
  properties: {
    connectionType: 'IPsec'
    connectionProtocol: 'IKEv2'
    virtualNetworkGateway1: {
      id: hubGateway.id
      properties: {}
    }
    localNetworkGateway2: {
      id: lngLyon.id
      properties: {}
    }
    sharedKey: psk
  }
  dependsOn: [
    spokePeerings
  ]
}

// ---------- S5.2 : routage symétrique et filtrage (solution du défi 05.3) ----------
module lyonConnectivity 'lyon-connectivity.bicep' = {
  name: 'rattrapage-m05-lyon'
  params: {
    numero: numero
    location: location
  }
  dependsOn: [
    spokePeerings
    connection
  ]
}

output lyonGatewayIp string = lyonPip.properties.ipAddress
output firewallPrivateIp string = lyonConnectivity.outputs.firewallPrivateIp
