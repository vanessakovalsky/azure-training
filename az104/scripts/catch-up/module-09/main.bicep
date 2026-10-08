// Rattrapage module 09 — coffre Recovery Services et stratégies de sauvegarde Arvéo
// Déployé dans rg-stNN-shared. Les protections (VMs, partage, serveur MARS) et les sauvegardes
// immédiates sont lancées par deploy.sh (Azure CLI) : elles dépendent de ressources d'autres
// groupes et d'opérations non déclaratives (backup-now).
// Redondance du stockage de sauvegarde : réglable uniquement tant qu'aucun élément n'est protégé.
// deploy.sh passe configurerStockage=false si le coffre existe déjà.

@description('Numéro de stagiaire sur deux chiffres (ex. 07)')
param numero string

@description('Région du coffre : celle des VMs et du compte de fichiers protégés')
param location string = resourceGroup().location

@description('Régler la redondance du stockage de sauvegarde (coffre neuf uniquement)')
param configurerStockage bool = true

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var fuseau = 'Romance Standard Time'
var heureVm = '2026-01-01T22:00:00Z'       // 22:00, heure de Paris (fuseau ci-dessus)
var heureFichiers = '2026-01-01T20:00:00Z' // 20:00, heure de Paris

resource vault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: 'rsv-${prefix}-arveo'
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource stockage 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2023-04-01' = if (configurerStockage) {
  parent: vault
  name: 'vaultstorageconfig'
  properties: {
    storageModelType: 'LocallyRedundant'
    crossRegionRestoreFlag: false
  }
}

// Stratégie Améliorée (V2) : obligatoire pour les VMs à lancement fiable (web01, web02)
resource polVm 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: vault
  name: 'pol-vm-arveo'
  dependsOn: [
    stockage
  ]
  properties: {
    backupManagementType: 'AzureIaasVM'
    policyType: 'V2'
    instantRpRetentionRangeInDays: 7
    timeZone: fuseau
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicyV2'
      scheduleRunFrequency: 'Daily'
      dailySchedule: {
        scheduleRunTimes: [
          heureVm
        ]
      }
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          heureVm
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
      weeklySchedule: {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          heureVm
        ]
        retentionDuration: {
          count: 12
          durationType: 'Weeks'
        }
      }
    }
  }
}

// Stratégie Azure Files : instantané quotidien du partage, conservé 30 jours
resource polFichiers 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: vault
  name: 'pol-files-arveo'
  dependsOn: [
    stockage
  ]
  properties: {
    backupManagementType: 'AzureStorage'
    workLoadType: 'AzureFileShare'
    timeZone: fuseau
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        heureFichiers
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          heureFichiers
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
    }
  }
}

output vaultName string = vault.name
output vaultId string = vault.id
output policies array = [
  polVm.name
  polFichiers.name
]
