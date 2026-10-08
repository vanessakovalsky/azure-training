// aci.bicep — conteneur de l'API de suivi des colis sur Azure Container Instances
// Mode public (lab 08.4) : IP publique + étiquette DNS, port 8080.
// Mode privé (défi 08.5) : IP privée dans snet-aci (sous-réseau délégué), aucune IP publique.
// Image tirée du registre avec l'identité managée id-stNN-aci (rôle AcrPull).
targetScope = 'resourceGroup'

param numero string
param session string
param location string = resourceGroup().location

@description('Serveur de connexion du registre (ex. crarveost072610.azurecr.io)')
param acrLoginServer string

@description('ID de ressource de l\'identité id-stNN-aci')
param identityId string

param imageTag string = '2.0'

@description('false = lab 08.4 (public) ; true = défi 08.5 (privé, snet-aci)')
param prive bool = false

@description('ID du sous-réseau snet-aci (mode privé uniquement)')
param subnetId string = ''

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource aci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: prive ? 'aci-${prefix}-api-priv' : 'aci-${prefix}-api'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    osType: 'Linux'
    restartPolicy: 'Always'
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        identity: identityId
      }
    ]
    containers: [
      {
        name: 'api'
        properties: {
          image: '${acrLoginServer}/arveo/api-suivi-colis:${imageTag}'
          ports: [
            {
              port: 8080
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: json('0.5')
              memoryInGB: json('0.5')
            }
          }
        }
      }
    ]
    ipAddress: {
      type: prive ? 'Private' : 'Public'
      ports: [
        {
          port: 8080
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: prive ? null : 'arveo-${prefix}-api-${session}'
    }
    subnetIds: prive ? [
      {
        id: subnetId
      }
    ] : null
  }
}

output ip string = aci.properties.ipAddress.ip
output fqdn string = prive ? '' : aci.properties.ipAddress.fqdn
