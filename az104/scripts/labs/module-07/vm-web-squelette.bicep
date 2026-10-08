// vm-web-squelette.bicep — exercice 07.3 : VM web du portail client Arvéo
// Copier en vm-web.bicep (même dossier, pour loadTextContent), compléter les 5 TODO,
// puis déployer dans rg-stNN-app. Le sous-réseau snet-web est lu dans rg-stNN-spoke.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Nom court de la VM (ex. web02)')
param nomCourt string

@description('Zone de disponibilité')
@allowed([
  '1'
  '2'
  '3'
])
param zone string

@description('Dernier octet de l\'IP privée dans snet-web (ex. 12 pour 10.NN.4.12)')
@minValue(4)
@maxValue(254)
param hostOctet int

@description('Mot de passe administrateur (fichier ~/.arveo/web-admin.txt)')
@secure()
param adminPassword string

@description('Compte de stockage des diagnostics de démarrage (module 3) ; vide = stockage managé')
param diagStorageName string = 'starveost${numero}diag'

param location string = resourceGroup().location
param vmSize string = 'Standard_B2s_v2'
param adminUsername string = 'arveoadmin'

var prefix = 'st${numero}'
var octet = int(numero)
var vmName = 'vm-${prefix}-${nomCourt}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource snetWeb 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  scope: resourceGroup('rg-${prefix}-spoke')
  name: 'vnet-${prefix}-spoke-app/snet-web'
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${prefix}-${nomCourt}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: snetWeb.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.${octet}.4.${hostOctet}'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  // TODO 1 : zone de disponibilité (propriété de premier niveau, tableau de chaînes)
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      // TODO 2 : image Ubuntu Server 24.04 LTS
      //          (éditeur Canonical, offre ubuntu-24_04-lts, SKU server, dernière version)
      osDisk: {
        // TODO 3 : nom osdisk-<prefix>-<nomCourt>, création depuis l'image,
        //          SSD Standard LRS, supprimé avec la VM
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: empty(diagStorageName) ? null : 'https://${diagStorageName}.blob.${environment().suffixes.storage}/'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      // TODO 4 : customData = contenu de cloud-init-web.yaml (même dossier), encodé en base64
      linuxConfiguration: {
        // TODO 5 : authentification par mot de passe autorisée
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
  }
}

output vmName string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
