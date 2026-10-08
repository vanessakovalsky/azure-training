// alerte-ssh.bicep — défi 10.4 (solution) et rattrapage du module 10
// Déployé dans rg-stNN-shared :
//   - fonction KQL ArveoEchecsSsh enregistrée dans log-stNN-shared (catégorie Arveo) ;
//   - alerte de recherche dans les journaux alr-stNN-ssh-echecs : au moins 5 « Failed password »
//     en 10 min par serveur ET par adresse source, évaluée toutes les 5 min, résolution automatique.
// La requête de l'alerte est écrite en entier (pas d'appel à la fonction) : la règle ne dépend
// pas d'un objet modifiable par l'équipe sécurité.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('ID du groupe d\'actions notifié')
param actionGroupId string

param location string = resourceGroup().location

@description('Nombre d\'échecs déclenchant l\'alerte, par serveur et par adresse source')
param seuil int = 5

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var requete = '''
Syslog
| where Facility in ("auth", "authpriv") and SyslogMessage has "Failed password"
| parse SyslogMessage with * "from " IpSource " port " *
| project TimeGenerated, Computer, IpSource, SyslogMessage
'''

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: 'log-${prefix}-shared'
}

resource fonction 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: workspace
  name: 'arveo-echecs-ssh'
  properties: {
    category: 'Arveo'
    displayName: 'Échecs SSH Arvéo'
    query: requete
    functionAlias: 'ArveoEchecsSsh'
  }
}

resource regle 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alr-${prefix}-ssh-echecs'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'alr-${prefix}-ssh-echecs'
    description: 'Arvéo : au moins ${seuil} échecs SSH en 10 min par serveur et adresse source'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [
      workspace.id
    ]
    criteria: {
      allOf: [
        {
          query: requete
          timeAggregation: 'Count'
          dimensions: [
            {
              name: 'Computer'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'IpSource'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThanOrEqual'
          threshold: seuil
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

output ruleName string = regle.name
output functionAlias string = fonction.properties.functionAlias
