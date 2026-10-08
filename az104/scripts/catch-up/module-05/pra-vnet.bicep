// pra-vnet.bicep — module du rattrapage M5, déployé dans rg-stNN-spoke
// Spoke de reprise d'activité en West Europe (peering global avec le hub de France Central).
// État de fin de module : deux plages (lab 05.1, étape d'extension de l'espace d'adressage).
targetScope = 'resourceGroup'

param numero string

@allowed([ 'westeurope' ])
param location string = 'westeurope'

var prefix = 'st${numero}'
var octet = int(numero)
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource spokePra 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${prefix}-spoke-pra'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.${octet}.12.0/23'
        '10.${octet}.14.0/23'
      ]
    }
    subnets: [
      {
        name: 'snet-pra'
        properties: {
          addressPrefix: '10.${octet}.12.0/24'
        }
      }
    ]
  }
}

output spokePraId string = spokePra.id
