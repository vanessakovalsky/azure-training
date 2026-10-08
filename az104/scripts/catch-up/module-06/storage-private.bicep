// storage-private.bicep — compte de données Arvéo joignable uniquement depuis le réseau Arvéo
// Solution du défi 06.4. Déployé dans rg-stNN-data.
//   - compte starveostNNdata<SES> redéclaré À L'IDENTIQUE de l'état des labs 06.1 à 06.3
//     (une déclaration de compte est un remplacement complet de ses propriétés), avec
//     publicNetworkAccess à Disabled
//   - private endpoint pe-stNN-blob (sous-ressource blob) dans snet-pe du spoke données
//   - zone privatelink.blob.core.windows.net dans rg-stNN-hub (module private-dns.bicep)
//     et groupe de zones DNS : enregistrement A créé et maintenu par la plateforme
// Déploiement :
//   az deployment group create -g rg-stNN-data -f storage-private.bicep -p numero=NN session=<SES>
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Code de session (4 caractères, minuscules et chiffres), fourni par la formatrice')
@minLength(4)
@maxLength(4)
param session string

@description('Région du compte et du private endpoint')
param location string = 'francecentral'

@description('Accès public au compte : Disabled (cible du défi) ; Enabled réservé au rattrapage')
@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = 'Disabled'

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var peSubnetId = resourceId('rg-${prefix}-spoke', 'Microsoft.Network/virtualNetworks/subnets',
  'vnet-${prefix}-spoke-data', 'snet-pe')

// ---------- Compte de données (état des labs 06.1 à 06.3) ----------
resource dataAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'starveost${numero}data${session}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_RAGRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Disabled' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ---------- DNS privé (hub) ----------
module dns 'private-dns.bicep' = {
  name: 'private-dns-blob'
  scope: resourceGroup('rg-${prefix}-hub')
  params: {
    numero: numero
  }
}

// ---------- Private endpoint ----------
resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${prefix}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    customNetworkInterfaceName: 'nic-${prefix}-pe-blob'
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-blob'
        properties: {
          privateLinkServiceId: dataAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: dns.outputs.zoneId
        }
      }
    ]
  }
}

// IP lue sur la carte réseau créée par la plateforme, nommée par customNetworkInterfaceName
// (customDnsConfigs peut être vide quand un groupe de zones DNS est associé)
resource peNic 'Microsoft.Network/networkInterfaces@2023-11-01' existing = {
  name: 'nic-${prefix}-pe-blob'
}

output privateEndpointIp string = peNic.properties.ipConfigurations[0].properties.privateIPAddress
output blobEndpoint string = dataAccount.properties.primaryEndpoints.blob
output accountName string = dataAccount.name
