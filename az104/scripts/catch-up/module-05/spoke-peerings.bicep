// spoke-peerings.bicep — module du rattrapage M5, déployé dans rg-stNN-spoke
// Liens spoke → hub (app, données, PRA) avec utilisation de la passerelle du hub.
// À déployer APRÈS les liens hub → spokes en allowGatewayTransit (dépendance dans main.bicep).
targetScope = 'resourceGroup'

param numero string
param hubVnetId string

var prefix = 'st${numero}'
var spokes = [
  'app'
  'data'
  'pra'
]

resource spokeVnets 'Microsoft.Network/virtualNetworks@2023-11-01' existing = [for spoke in spokes: {
  name: 'vnet-${prefix}-spoke-${spoke}'
}]

@batchSize(1) // une opération à la fois sur la passerelle du hub
resource peerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = [for (spoke, i) in spokes: {
  parent: spokeVnets[i]
  name: 'peer-spoke-${spoke}-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
  }
}]
