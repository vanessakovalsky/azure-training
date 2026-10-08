// private-dns.bicep — zone DNS privée des private endpoints Blob, déployée dans rg-stNN-hub
// Module de storage-private.bicep (défi 06.4) et de main.bicep (rattrapage M6).
// Zone privatelink.blob.core.windows.net liée au hub et aux deux spokes (sans enregistrement
// automatique : une seule zone d'enregistrement par VNet, déjà arveo.internal au M4).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

var prefix = 'st${numero}'
var spokeRg = 'rg-${prefix}-spoke'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var vnets = [
  {
    link: 'link-hub'
    id: resourceId('Microsoft.Network/virtualNetworks', 'vnet-${prefix}-hub')
  }
  {
    link: 'link-spoke-app'
    id: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-app')
  }
  {
    link: 'link-spoke-data'
    id: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-data')
  }
]

resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for v in vnets: {
  parent: blobZone
  name: v.link
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: v.id
    }
    registrationEnabled: false
  }
}]

output zoneId string = blobZone.id
