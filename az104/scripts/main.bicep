// main.bicep — rattrapage module 03 : socle partagé Arvéo (rg-stNN-shared)
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région de déploiement')
@allowed([ 'francecentral' ])
param location string = 'francecentral'

@description('Nom du compte de stockage de diagnostic (3 à 24 minuscules ou chiffres)')
@minLength(3)
@maxLength(24)
param storageName string = 'starveost${numero}diag'

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${prefix}-shared'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource diagStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-deploy'
  location: location
  tags: tags
}

output workspaceId string = workspace.id
output storageAccountId string = diagStorage.id
output identityPrincipalId string = deployIdentity.properties.principalId
