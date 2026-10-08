// main.bicep — rattrapage module 07 : machines virtuelles Arvéo, déployé dans rg-stNN-app
// État obtenu = fin du module 7 (hors Bastion, passerelle NAT, espace de travail et
// associations de sous-réseaux, créés par deploy.sh) :
//   lbe-stNN-web + vm-stNN-web01 (zone 1, disque de données) + vm-stNN-web02 (zone 2),
//   lbi-stNN-api + vmss-stNN-api + as-stNN-api, extensions Custom Script (portail v2)
//   et agent Azure Monitor, règle de collecte dcr-stNN-linux.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Mot de passe administrateur des VMs (fichier ~/.arveo/web-admin.txt)')
@secure()
param adminPassword string

@description('false si vm-stNN-web01 existe déjà (création seule : customData non modifiable)')
param deployWeb01 bool = true

@description('false si vm-stNN-web02 existe déjà')
param deployWeb02 bool = true

@description('false si vmss-stNN-api existe déjà')
param deployVmss bool = true

@description('Compte de stockage des diagnostics de démarrage (module 3) ; vide = stockage managé')
param diagStorageName string = ''

param location string = resourceGroup().location

var prefix = 'st${numero}'
var octet = int(numero)
var webs = [
  {
    nomCourt: 'web01'
    zone: '1'
    hostOctet: 11
    dataDiskSizeGB: 32
    deploy: deployWeb01
  }
  {
    nomCourt: 'web02'
    zone: '2'
    hostOctet: 12
    dataDiskSizeGB: 0
    deploy: deployWeb02
  }
]

// ---------- Load Balancer public (S7.3, lab 07.4) ----------
module lbWeb 'lb-web.bicep' = {
  name: 'rattrapage-m07-lb-web'
  params: {
    numero: numero
    location: location
  }
}

// ---------- VMs web (S7.2, labs 07.2 et 07.3) ----------
module webVms 'vm-web.bicep' = [for web in webs: if (web.deploy) {
  name: 'rattrapage-m07-${web.nomCourt}'
  params: {
    numero: numero
    nomCourt: web.nomCourt
    zone: web.zone
    hostOctet: web.hostOctet
    dataDiskSizeGB: web.dataDiskSizeGB
    diagStorageName: diagStorageName
    adminPassword: adminPassword
    lbBackendPoolIds: [
      lbWeb.outputs.backendPoolId
    ]
    location: location
  }
}]

// ---------- Niveau API (S7.3, défi 07.5) ----------
module api 'vmss-api.bicep' = if (deployVmss) {
  name: 'rattrapage-m07-api'
  params: {
    numero: numero
    adminPassword: adminPassword
    location: location
  }
}

// ---------- Extensions (S7.4, labs 07.6 et 07.7) ----------
resource vms 'Microsoft.Compute/virtualMachines@2024-03-01' existing = [for web in webs: {
  name: 'vm-${prefix}-${web.nomCourt}'
}]

resource customScript 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (web, i) in webs: {
  parent: vms[i]
  name: 'CustomScript'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      script: base64(replace(loadTextContent('../../labs/module-07/portail-v2.sh'), '__OCT__', string(octet)))
    }
  }
  dependsOn: [
    webVms
  ]
}]

resource monitorAgent 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (web, i) in webs: {
  parent: vms[i]
  name: 'AzureMonitorLinuxAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0' // [À VÉRIFIER] version majeure courante de l'agent
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
  dependsOn: [
    customScript[i] // une seule opération d'extension à la fois par VM
  ]
}]

// ---------- Règle de collecte (S7.4, lab 07.7) ----------
module dcr '../../labs/module-07/dcr-arveo-linux.bicep' = {
  name: 'rattrapage-m07-dcr'
  params: {
    numero: numero
    location: location
  }
  dependsOn: [
    monitorAgent
  ]
}

output lbPublicIp string = lbWeb.outputs.publicIp
output apiFrontendIp string = '10.${octet}.5.100'
