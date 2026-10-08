// vm-web.bicep — rattrapage M7 (et solution complète de l'exercice 07.3)
// VM web du portail client Arvéo dans rg-stNN-app, carte dans snet-web (rg-stNN-spoke).
// Ajouts par rapport à la solution de l'exercice 07.3 :
//   - lbBackendPoolIds : appartenance au pool bp-web du Load Balancer (lab 07.4) ;
//   - identité managée affectée par le système (agent Azure Monitor, lab 07.7) ;
//   - dataDiskSizeGB : disque de données zonal au LUN 0 (lab 07.2), 0 = aucun.
// ⚠️ Redéployer sans lbBackendPoolIds RETIRE la carte du pool (propriété réécrite).
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

@description('Pools de back-end de Load Balancer auxquels rattacher la carte')
param lbBackendPoolIds array = []

@description('Taille du disque de données en Gio (0 = aucun disque de données)')
@minValue(0)
param dataDiskSizeGB int = 0

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
          loadBalancerBackendAddressPools: [for poolId in lbBackendPoolIds: {
            id: poolId
          }]
        }
      }
    ]
  }
}

resource dataDisk 'Microsoft.Compute/disks@2023-10-02' = if (dataDiskSizeGB > 0) {
  name: 'disk-${prefix}-${nomCourt}-data'
  location: location
  tags: tags
  zones: [
    zone
  ]
  sku: {
    name: 'StandardSSD_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: dataDiskSizeGB
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  zones: [
    zone
  ]
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${prefix}-${nomCourt}'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      dataDisks: dataDiskSizeGB > 0 ? [
        {
          lun: 0
          createOption: 'Attach'
          caching: 'ReadOnly'
          managedDisk: {
            id: dataDisk.id
          }
        }
      ] : []
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
      customData: base64(loadTextContent('../../labs/module-07/cloud-init-web.yaml'))
      linuxConfiguration: {
        disablePasswordAuthentication: false
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
