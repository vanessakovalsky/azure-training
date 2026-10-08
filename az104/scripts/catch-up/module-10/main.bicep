// main.bicep — rattrapage module 10 : supervision Arvéo (déployé dans rg-stNN-shared)
// Lancé par deploy.sh, APRÈS preparer-supervision.sh (diagnostic du coffre et du NSG,
// journal de flux, extension Network Watcher). État obtenu = fin du module 10 :
//   - groupe d'actions ag-stNN-exploitation (courriel) ;
//   - alr-stNN-cpu-vm : CPU moyen > 80 % sur 5 min, toutes les VMs de rg-stNN-app ;
//   - alr-stNN-lb-sante : DipAvailability < 100 sur 5 min, une série par serveur du pool ;
//   - alr-stNN-nsg-regle : suppression d'une règle de NSG dans rg-stNN-spoke ou rg-stNN-app ;
//   - fonction ArveoEchecsSsh et alerte alr-stNN-ssh-echecs (module alerte-ssh.bicep, défi 10.4) ;
//   - paramètre de diagnostic diag-arveo de lbe-stNN-web (module diag-lb.bicep, lab 10.1).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Adresse de messagerie qui reçoit les notifications')
param courriel string

param location string = 'francecentral'

var prefix = 'st${numero}'
var octet = int(numero)
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var rgAppId = '${subscription().id}/resourceGroups/rg-${prefix}-app'
var rgSpokeId = '${subscription().id}/resourceGroups/rg-${prefix}-spoke'
var lbId = resourceId('rg-${prefix}-app', 'Microsoft.Network/loadBalancers', 'lbe-${prefix}-web')

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: 'log-${prefix}-shared'
}

// ---------- Groupe d'actions (lab 10.2) ----------
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${prefix}-exploitation'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ag-${prefix}-exp'
    enabled: true
    emailReceivers: [
      {
        name: 'exploitation'
        emailAddress: courriel
        useCommonAlertSchema: true
      }
    ]
  }
}

// ---------- Saturation CPU durable, toutes les VMs du groupe applicatif ----------
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alr-${prefix}-cpu-vm'
  location: 'global'
  tags: tags
  properties: {
    description: 'Arvéo : CPU moyen > 80 % sur 5 min (VMs de rg-${prefix}-app)'
    severity: 2
    enabled: true
    scopes: [
      rgAppId
    ]
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'cpu-sup-80'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ---------- Serveur web sorti du pool bp-web ----------
resource lbAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alr-${prefix}-lb-sante'
  location: 'global'
  tags: tags
  properties: {
    description: 'Arvéo : serveur du pool bp-web en échec de sonde (10.${octet}.4.0/24)'
    severity: 1
    enabled: true
    scopes: [
      lbId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'sante-pool'
          metricNamespace: 'Microsoft.Network/loadBalancers'
          metricName: 'DipAvailability'
          dimensions: [
            {
              name: 'BackendIPAddress'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'LessThan'
          threshold: 100
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ---------- Suppression d'une règle de filtrage (journal d'activité) ----------
resource nsgAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alr-${prefix}-nsg-regle'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Arvéo : règle de NSG supprimée (rg-${prefix}-spoke, rg-${prefix}-app)'
    enabled: true
    scopes: [
      rgSpokeId
      rgAppId
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Network/networkSecurityGroups/securityRules/delete'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// ---------- Défi 10.4 : échecs SSH ----------
module ssh 'alerte-ssh.bicep' = {
  name: 'rattrapage-m10-ssh'
  params: {
    numero: numero
    actionGroupId: actionGroup.id
    location: location
  }
}

// ---------- Lab 10.1 : métriques du Load Balancer vers l'espace de travail ----------
module diagLb 'diag-lb.bicep' = {
  name: 'rattrapage-m10-diag-lb'
  scope: resourceGroup('rg-${prefix}-app')
  params: {
    numero: numero
    workspaceId: workspace.id
  }
}

output actionGroupId string = actionGroup.id
output alertes array = [
  cpuAlert.name
  lbAlert.name
  nsgAlert.name
  ssh.outputs.ruleName
]
