// lyon-nsg-rule.bicep — module de lyon-connectivity.bicep, déployé dans rg-stNN-spoke
// Ajoute Allow-SQL-From-Lyon (priorité 110) au NSG existant nsg-stNN-data.
// Attention : le rattrapage du module 4 redéclare nsg-stNN-data avec ses règles en ligne
// et supprime cette règle ; relancer ensuite le rattrapage du module 5.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

var prefix = 'st${numero}'
var octet = int(numero)

resource nsgData 'Microsoft.Network/networkSecurityGroups@2023-11-01' existing = {
  name: 'nsg-${prefix}-data'
}

resource asgData 'Microsoft.Network/applicationSecurityGroups@2023-11-01' existing = {
  name: 'asg-${prefix}-data'
}

resource allowSqlFromLyon 'Microsoft.Network/networkSecurityGroups/securityRules@2023-11-01' = {
  parent: nsgData
  name: 'Allow-SQL-From-Lyon'
  properties: {
    priority: 110
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: '10.200.${octet}.0/24'
    sourcePortRange: '*'
    destinationApplicationSecurityGroups: [
      {
        id: asgData.id
      }
    ]
    destinationPortRange: '1433'
  }
}
