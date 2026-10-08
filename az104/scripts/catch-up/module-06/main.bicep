// main.bicep — rattrapage module 06 : stockage Arvéo (rg-stNN-data)
// Lancé par deploy.sh, en deux passes :
//   passe 1 (publicNetworkAccess=Enabled) : comptes, services, rôles, synchronisation
//   passe 2 (publicNetworkAccess=Disabled, registeredServerId renseigné) : état final
// État obtenu = fin du module 6 :
//   - starveostNNdata<SES> : RA-GRS, versioning, flux de modifications, suppression réversible,
//     cycle de vie (lifecycle-pod.json), conteneur pod, clé partagée désactivée,
//     private endpoint pe-stNN-blob (module storage-private.bicep)
//   - starveostNNarch<SES> : destination de la réplication d'objets (conteneur pod-replica)
//   - starveostNNfiles<SES> : partage partage-lyon (100 Gio), suppression réversible des partages
//   - sss-stNN, groupe sg-partage-lyon, points de terminaison cloud et serveur
// La règle de réplication d'objets est créée par deploy.sh (Azure CLI) : son identifiant,
// généré par le compte de destination, n'est pas connu au début du déploiement.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Code de session (4 caractères, minuscules et chiffres)')
@minLength(4)
@maxLength(4)
param session string

param location string = 'francecentral'

@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = 'Disabled'

@description('ID d\'objet Entra du stagiaire (Storage Blob Data Contributor sur le compte de données)')
param userObjectId string

@description('ID de principal de l\'identité managée de vm-stNN-lyon-fs (inscription du serveur)')
param lyonPrincipalId string

@description('ID d\'objet du principal de service Microsoft.StorageSync du tenant')
param storageSyncSpObjectId string

@description('ID (GUID) du rôle « Reader and Data Access », lu par deploy.sh')
param readerDataAccessRoleId string

@description('ID de ressource du serveur inscrit ; vide = point de terminaison serveur non créé')
param registeredServerId string = ''

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
// Rôles intégrés (GUID identiques dans tous les tenants)
var roleContributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var roleBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// ---------- Compte de données + private endpoint (S6.1, S6.3) ----------
module dataPrivate 'storage-private.bicep' = {
  name: 'rattrapage-m06-data'
  params: {
    numero: numero
    session: session
    location: location
    publicNetworkAccess: publicNetworkAccess
  }
}

resource dataAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: 'starveost${numero}data${session}'
}

// ---------- Protection des données et cycle de vie (S6.2) ----------
resource dataBlob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: dataAccount
  name: 'default'
  properties: {
    isVersioningEnabled: true
    changeFeed: {
      enabled: true
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 14
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 14
    }
  }
  dependsOn: [
    dataPrivate
  ]
}

resource podContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: dataBlob
  name: 'pod'
  properties: {
    publicAccess: 'None'
  }
}

resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: dataAccount
  name: 'default'
  properties: {
    policy: loadJsonContent('lifecycle-pod.json')
  }
  dependsOn: [
    dataPrivate
  ]
}

// ---------- Accès aux données par Entra ID (S6.3) ----------
resource userBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataAccount.id, userObjectId, roleBlobDataContributor)
  scope: dataAccount
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',
      roleBlobDataContributor)
  }
  dependsOn: [
    dataPrivate
  ]
}

// ---------- Compte d'archive, destination de la réplication d'objets (S6.2) ----------
resource archAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'starveost${numero}arch${session}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Cool'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource archBlob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: archAccount
  name: 'default'
  properties: {
    isVersioningEnabled: true
  }
}

resource replicaContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: archBlob
  name: 'pod-replica'
  properties: {
    publicAccess: 'None'
  }
}

// ---------- Azure Files (S6.4) ----------
resource filesAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'starveost${numero}files${session}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    largeFileSharesState: 'Enabled'
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: filesAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource share 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: 'partage-lyon'
  properties: {
    shareQuota: 100
    accessTier: 'TransactionOptimized'
    enabledProtocols: 'SMB'
  }
}

// Le service de synchronisation accède au compte de fichiers (rôle attribué automatiquement
// par le portail à la création d'un point de terminaison cloud) [À VÉRIFIER] rôles exigés
// lorsque le service de synchronisation utilise une identité managée
resource syncRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(filesAccount.id, storageSyncSpObjectId, readerDataAccessRoleId)
  scope: filesAccount
  properties: {
    principalId: storageSyncSpObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions',
      readerDataAccessRoleId)
  }
}

// ---------- Azure File Sync (S6.4) ----------
resource sss 'Microsoft.StorageSync/storageSyncServices@2022-06-01' = {
  name: 'sss-${prefix}'
  location: location
  tags: tags
  properties: {
    incomingTrafficPolicy: 'AllowAllTraffic'
  }
}

resource syncGroup 'Microsoft.StorageSync/storageSyncServices/syncGroups@2022-06-01' = {
  parent: sss
  name: 'sg-partage-lyon'
  properties: {}
}

resource cloudEndpoint 'Microsoft.StorageSync/storageSyncServices/syncGroups/cloudEndpoints@2022-06-01' = {
  parent: syncGroup
  name: 'ce-partage-lyon'
  properties: {
    storageAccountResourceId: filesAccount.id
    azureFileShareName: share.name
    storageAccountTenantId: tenant().tenantId
  }
  dependsOn: [
    syncRole
  ]
}

// Inscription du serveur par son identité managée : Contributeur limité au service de synchronisation
// (rôle plus restreint possible : « Azure File Sync Administrator » [À VÉRIFIER] disponibilité)
resource lyonSyncRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sss.id, lyonPrincipalId, roleContributor)
  scope: sss
  properties: {
    principalId: lyonPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleContributor)
  }
}

resource serverEndpoint 'Microsoft.StorageSync/storageSyncServices/syncGroups/serverEndpoints@2022-06-01' = if (!empty(registeredServerId)) {
  parent: syncGroup
  name: 'se-lyon-fs'
  properties: {
    serverResourceId: registeredServerId
    serverLocalPath: 'F:\\Partages\\Commun'
    cloudTiering: 'on'
    volumeFreeSpacePercent: 20
    initialDownloadPolicy: 'NamespaceThenModifiedFiles'
    localCacheMode: 'UpdateLocallyCachedFiles'
  }
  dependsOn: [
    cloudEndpoint
  ]
}

output dataAccount string = dataAccount.name
output privateEndpointIp string = dataPrivate.outputs.privateEndpointIp
output storageSyncServiceId string = sss.id
