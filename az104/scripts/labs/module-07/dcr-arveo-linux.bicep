// dcr-arveo-linux.bicep — lab 07.7 : règle de collecte (DCR) de l'agent Azure Monitor
// Déployé dans rg-stNN-app. Collecte Syslog (avertissement et plus grave) et compteurs de
// performance des VMs Linux, envoyés vers log-stNN-shared (rg-stNN-shared, créé au module 3, exploité au module 10).
// Associe la règle à chaque VM listée. Prérequis : espace de travail créé, agent installé.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

param location string = resourceGroup().location

@description('VMs associées à la règle (dans ce groupe de ressources)')
param vmNames array = [
  'vm-st${numero}-web01'
  'vm-st${numero}-web02'
]

var prefix = 'st${numero}'
var workspaceId = resourceId('rg-${prefix}-shared', 'Microsoft.OperationalInsights/workspaces', 'log-${prefix}-shared')
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-${prefix}-linux'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      syslog: [
        {
          name: 'syslog-arveo'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
            'daemon'
            'syslog'
            'user'
          ]
          logLevels: [
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
        }
      ]
      performanceCounters: [
        {
          name: 'perf-arveo'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          // Noms des compteurs Linux [À VÉRIFIER] avec la règle générée par le portail
          counterSpecifiers: [
            '\\Processor(*)\\% Processor Time'
            '\\Memory(*)\\% Used Memory'
            '\\Logical Disk(*)\\% Used Space'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'la-arveo'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Syslog'
          'Microsoft-Perf'
        ]
        destinations: [
          'la-arveo'
        ]
      }
    ]
  }
}

resource vms 'Microsoft.Compute/virtualMachines@2024-03-01' existing = [for name in vmNames: {
  name: name
}]

resource associations 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = [for (name, i) in vmNames: {
  name: 'dcra-${name}'
  scope: vms[i]
  properties: {
    dataCollectionRuleId: dcr.id
    description: 'Syslog et performances vers log-${prefix}-shared'
  }
}]

output dcrId string = dcr.id
