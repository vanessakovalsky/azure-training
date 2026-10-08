// main.bicep — rattrapage du module 08, déployé dans rg-stNN-app
// Plan App Service Linux S1, application du portail (emplacement staging), mise à l'échelle
// automatique du plan, registre de conteneurs Basic, identité managée affectée par l'utilisateur
// autorisée à tirer les images du registre (AcrPull).
// Le code (zip) et l'image de l'API sont publiés par deploy.sh, pas par ce fichier.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres (ex. 07)')
param numero string

@description('Code de session à 4 caractères du module 6 (ex. 2610) : unicité des noms globaux')
param session string

param location string = resourceGroup().location

@description('URL de l\'API privée (défi 08.5) ; vide = /api/ répond 503')
param apiUrl string = ''

@description('Nombre minimal d\'instances du plan (mise à l\'échelle automatique)')
@minValue(1)
param minInstances int = 2

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var appName = 'app-${prefix}-portail-${session}'
var acrName = 'crarveo${prefix}${session}'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // rôle intégré AcrPull

var siteConfigCommun = {
  linuxFxVersion: 'NODE|22-lts' // [À VÉRIFIER] az webapp list-runtimes --os linux
  appCommandLine: 'node server.js'
  healthCheckPath: '/health'
  alwaysOn: true
  minTlsVersion: '1.2'
  ftpsState: 'Disabled'
  http20Enabled: true
}

// ---------- Calcul PaaS (S8.1, S8.2) ----------
resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'asp-${prefix}-portail'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
    capacity: minInstances
  }
  properties: {
    reserved: true // obligatoire pour un plan Linux
  }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: union(siteConfigCommun, {
      appSettings: [
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        { name: 'ARVEO_ENV', value: 'production' }
        { name: 'API_URL', value: apiUrl }
      ]
    })
  }
}

// Paramètres d'emplacement : restent attachés à leur emplacement lors d'un échange
resource stickySettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: app
  name: 'slotConfigNames'
  properties: {
    appSettingNames: [
      'ARVEO_ENV'
      'API_URL'
    ]
  }
}

resource staging 'Microsoft.Web/sites/slots@2024-04-01' = {
  parent: app
  name: 'staging'
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: union(siteConfigCommun, {
      appSettings: [
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
        { name: 'ARVEO_ENV', value: 'recette' }
        { name: 'API_URL', value: '' }
      ]
    })
  }
}

resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'as-${prefix}-portail'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: plan.id
    profiles: [
      {
        name: 'profil-arveo'
        capacity: {
          minimum: string(minInstances)
          maximum: '4'
          default: string(minInstances)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: plan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: plan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT15M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

// ---------- Conteneurs (S8.3) ----------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource idAci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-aci'
  location: location
  tags: tags
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, idAci.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: idAci.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output appName string = app.name
output appHost string = app.properties.defaultHostName
output stagingHost string = staging.properties.defaultHostName
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output identityId string = idAci.id
