// diag-lb.bicep — lab 10.1 : métriques de lbe-stNN-web vers log-stNN-shared (table AzureMetrics)
// Module de main.bicep, déployé dans rg-stNN-app. Le paramètre de diagnostic est une ressource
// d'extension : sa portée est le Load Balancer, pas le groupe de ressources.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('ID de ressource de l\'espace de travail Log Analytics')
param workspaceId string

resource lb 'Microsoft.Network/loadBalancers@2023-11-01' existing = {
  name: 'lbe-st${numero}-web'
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-arveo'
  scope: lb
  properties: {
    workspaceId: workspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
