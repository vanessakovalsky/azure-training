# Module 05 — Corrections

Exemples donnés pour le stagiaire 07 (`NN=07`, `OCT=7`). Toutes les solutions supposent le bloc de variables des exercices exécuté dans Cloud Shell (Bash), fonctions `tester` et `lyon` comprises.

## Lab 05.1 ⭐⭐ — Transit de passerelle et peering global

### Solution
```bash
# 1. Passerelle et état initial des liens du hub
az network vnet-gateway show -g "$RG_HUB" -n "vpngw-${ST}-hub" --query provisioningState -o tsv
az network vnet peering list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  --query "[].{Nom:name, Etat:peeringState, Acces:allowVirtualNetworkAccess, Relaye:allowForwardedTraffic, Transit:allowGatewayTransit, Distante:useRemoteGateways}" \
  -o table
```
Sortie attendue :
```
Succeeded
Nom                     Etat       Acces    Relaye    Transit    Distante
----------------------  ---------  -------  --------  ---------  ----------
peer-hub-to-spoke-app   Connected  True     True      False      False
peer-hub-to-spoke-data  Connected  True     True      False      False
```

```bash
# 2. Transit de passerelle : liens du hub, PUIS liens des spokes
for spoke in app data; do
  az network vnet peering update -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
    -n "peer-hub-to-spoke-${spoke}" --set allowGatewayTransit=true -o none
done
for spoke in app data; do
  az network vnet peering update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
    -n "peer-spoke-${spoke}-to-hub" --set useRemoteGateways=true -o none
done

# 3. Spoke PRA en North Europe
az network vnet create -g "$RG_SPOKE" -n "vnet-${ST}-spoke-pra" -l northeurope \
  --address-prefixes "10.${OCT}.12.0/23" \
  --subnet-name snet-pra --subnet-prefixes "10.${OCT}.12.0/24" \
  --tags $TAGS -o none

# 4. Peering global hub ↔ PRA
HUB_ID=$(az network vnet show -g "$RG_HUB" -n "vnet-${ST}-hub" --query id -o tsv)
PRA_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-pra" --query id -o tsv)
az network vnet peering create -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-pra --remote-vnet "$PRA_ID" \
  --allow-vnet-access --allow-forwarded-traffic --allow-gateway-transit \
  --query peeringState -o tsv
az network vnet peering create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-pra" \
  -n peer-spoke-pra-to-hub --remote-vnet "$HUB_ID" \
  --allow-vnet-access --allow-forwarded-traffic --use-remote-gateways \
  --query peeringState -o tsv
```
Sortie attendue (étape 4) :
```
Initiated
Connected
```

```bash
# 5. Contrôle des liens
az network vnet peering list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  --query "[].{Nom:name, Etat:peeringState, Sync:peeringSyncLevel, Transit:allowGatewayTransit}" \
  -o table
for spoke in app data pra; do
  az network vnet peering show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
    -n "peer-spoke-${spoke}-to-hub" --query "[name, useRemoteGateways]" -o tsv
done
```
Sortie attendue :
```
Nom                     Etat       Sync         Transit
----------------------  ---------  -----------  ---------
peer-hub-to-spoke-app   Connected  FullyInSync  True
peer-hub-to-spoke-data  Connected  FullyInSync  True
peer-hub-to-spoke-pra   Connected  FullyInSync  True
peer-spoke-app-to-hub   True
peer-spoke-data-to-hub  True
peer-spoke-pra-to-hub   True
```

```bash
# 6. Plage supplémentaire et synchronisation
az network vnet update -g "$RG_SPOKE" -n "vnet-${ST}-spoke-pra" \
  --address-prefixes "10.${OCT}.12.0/23" "10.${OCT}.14.0/23" -o none
az network vnet peering list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  --query "[].{Nom:name, Sync:peeringSyncLevel}" -o table
az network vnet peering show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-pra" \
  -n peer-spoke-pra-to-hub --query peeringSyncLevel -o tsv
az network vnet peering sync -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-pra -o none
az network vnet peering show -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-pra \
  --query "[peeringSyncLevel, join(' ', remoteAddressSpace.addressPrefixes)]" -o tsv
```
Sortie attendue (libellés des états non synchronisés `[À VÉRIFIER]` sur l'API du jour) :
```
Nom                     Sync
----------------------  --------------
peer-hub-to-spoke-app   FullyInSync
peer-hub-to-spoke-data  FullyInSync
peer-hub-to-spoke-pra   LocalNotInSync
RemoteNotInSync
FullyInSync	10.7.12.0/23 10.7.14.0/23
```

```bash
# 7. Saut suivant vers le spoke PRA
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.${OCT}.12.4" \
  --query "{Saut:nextHopType, IP:nextHopIpAddress}" -o table
```
Sortie attendue :
```
Saut              IP
----------------  ---------
VirtualAppliance  10.7.0.68
```

Réponses attendues (étape 8) :
- a. `useRemoteGateways` exige que le lien d'en face autorise déjà le transit (`allowGatewayTransit`) et qu'une passerelle provisionnée existe dans le VNet distant ; dans l'ordre inverse, la plateforme refuse la mise à jour du lien du spoke.
- b. Non : le spoke app n'est appairé qu'au hub, le peering n'est pas transitif. L'étape 7 montre que le paquet part vers le pare-feu (UDR `0.0.0.0/0` du M4) ; il ne passera que si une règle du pare-feu l'autorise, ce qui n'est pas le cas (refus implicite).
- c. Grâce au transit de passerelle : le lien PRA → hub utilise la passerelle du hub (`useRemoteGateways`), y compris en peering global ; une passerelle dans le spoke serait d'ailleurs incompatible avec cette option.

### Pourquoi
- Transit plutôt qu'une passerelle par spoke : une seule passerelle facturée et un seul tunnel par site distant ; les plages des spokes sont connues de la passerelle du hub.
- Options modifiées sur les liens existants (`update`) : aucune coupure du peering, pas de recréation, pas de perte de l'état `Connected`.
- `--set` (mise à jour générique) : agit directement sur la propriété ARM (`allowGatewayTransit`, `useRemoteGateways`), même nom qu'en Bicep.
- Spoke PRA en North Europe : région appairée de France Central pour un PRA, autorisée par la stratégie de régions du M2 ; plage `10.<OCT>.12.0/23` dans le bloc `10.<OCT>.0.0/20` du stagiaire, déjà annoncé à Lyon par la formatrice (aucune modification côté Lyon).
- Plage ajoutée en `/23` puis `/23` : `10.<OCT>.12.0/22` d'emblée aurait chevauché la seconde plage ; la liste passée à `vnet update` est COMPLÈTE (plages existantes + nouvelle).
- Synchronisation sur le lien du hub : c'est lui qui conserve une copie de l'espace d'adressage distant (`remoteAddressSpace`) ; tant qu'elle n'est pas mise à jour, la nouvelle plage n'est pas routée depuis le hub.
- Spoke PRA sans table de routes : aucune VM à protéger pour l'instant ; la symétrie avec le pare-feu est traitée en bonus 2 (table dans la région du VNet).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Mise à jour d'un lien refusée : `AnotherOperationInProgress` ou passerelle en `Updating` | Passerelle encore en provisionnement, ou deux mises à jour lancées en parallèle | Attendre `Succeeded`, relancer les mises à jour une par une |
| `useRemoteGateways` refusé (`RemotePeeringDoesNotAllowGatewayTransit` `[À VÉRIFIER]` libellé) | Lien du hub sans `allowGatewayTransit`, ou lien du spoke mis à jour en premier | Mettre à jour d'abord `peer-hub-to-spoke-*` |
| `RequestDisallowedByPolicy` sur `vnet-stNN-spoke-pra` | Tags oubliés, ou North Europe absente de la stratégie de régions du M2 | `--tags $TAGS` ; sinon prévenir la formatrice |
| `peering create` : `VnetAddressSpacesOverlap` | `OCT` mal défini, plage du PRA identique à celle d'un autre VNet | `echo $OCT`, recréer le VNet avec `10.${OCT}.12.0/23` |
| `vnet update` : `NetcfgSubnetRangesOverlap` / `AddressPrefixesOverlap` | Plage `/22` saisie au lieu de `/23`, ou ancienne plage omise de la liste | Liste complète : `10.<OCT>.12.0/23 10.<OCT>.14.0/23` |
| `az network vnet peering sync` inconnu | Azure CLI trop ancienne (Cloud Shell à jour : non concerné) | `az upgrade`, ou mise à jour du lien du hub dans le portail (« Synchroniser ») |
| `show-next-hop` : `NetworkWatcherNotFound` | Network Watcher absent dans la région de la VM | Formatrice : `az network watcher configure -g NetworkWatcherRG -l <REGION> --enabled true` |

### Variantes acceptables
- Peerings et options en Bicep (propriétés `allowGatewayTransit` et `useRemoteGateways` des ressources `virtualNetworkPeerings`) : recommandé en production ; c'est l'approche du rattrapage `scripts/catch-up/module-05/`.
- Création du spoke PRA dans un groupe dédié en North Europe : plus propre pour un vrai PRA (cycle de vie séparé) ; non prévu par l'isolation du tenant partagé (six groupes par stagiaire).
- Portail : le panneau de peering crée les deux liens et règle les options des deux côtés en une fois ; acceptable, non reproductible.

## Lab 05.2 ⭐⭐ — Tunnel VPN site-à-site vers Lyon

### Solution
```bash
# 1. Serveur de Lyon (14:30)
./scripts/labs/module-05/lyon-vm.sh "$NN"

# 2. IP publiques et côté Lyon (lecture seule)
LYON_IP=$(az network public-ip show -g "$RG_LYON" -n pip-lyon-vpngw --query ipAddress -o tsv)
HUB_PIP=$(az network public-ip show -g "$RG_HUB" -n "pip-${ST}-vpngw" --query ipAddress -o tsv)
echo "Lyon : ${LYON_IP} / Hub : ${HUB_PIP}"
az network local-gateway show -g "$RG_LYON" -n "lng-lyon-${ST}" \
  --query "{IP:gatewayIpAddress, Plages:join(' ', localNetworkAddressSpace.addressPrefixes)}" \
  -o table
```
Sortie attendue (adresses propres à chaque session) :
```
Lyon : <IP_LYON> / Hub : <IP_HUB>
IP          Plages
----------  -----------
<IP_HUB>    10.7.0.0/20
```
Le `/20` (`10.7.0.0` à `10.7.15.255`) couvre en une seule plage le hub (`/22`), les spokes app et données (`/22` chacun) et le spoke PRA (`10.7.12.0/23` et `10.7.14.0/23`) : aucun changement côté Lyon quand Arvéo ajoute un réseau dans ce bloc.

```bash
# 3. Passerelle de réseau local : le site de Lyon vu depuis le hub
az network local-gateway create -g "$RG_HUB" -n "lng-${ST}-lyon" -l "$LOC" \
  --gateway-ip-address "$LYON_IP" --local-address-prefixes "10.200.${OCT}.0/24" \
  --tags $TAGS -o none

# 4. Connexion IPsec (clé saisie sans écho, absente de l'historique)
read -r -s -p "Clé partagée : " PSK; echo
az network vpn-connection create -g "$RG_HUB" -n "cn-${ST}-hub-to-lyon" \
  --vnet-gateway1 "vpngw-${ST}-hub" --local-gateway2 "lng-${ST}-lyon" \
  --shared-key "$PSK" --tags $TAGS -o none

# 5. Établissement du tunnel
for _ in $(seq 1 10); do
  ETAT=$(az network vpn-connection show -g "$RG_HUB" -n "cn-${ST}-hub-to-lyon" \
    --query connectionStatus -o tsv)
  echo "$ETAT"
  [[ "$ETAT" == "Connected" ]] && break
  sleep 30
done
az network vpn-connection show -g "$RG_HUB" -n "cn-${ST}-hub-to-lyon" \
  --query "[connectionStatus, ingressBytesTransferred, egressBytesTransferred]" -o tsv
```
Sortie attendue (nombre de lignes `Connecting` et compteurs variables) :
```
Connecting
Connected
Connected	2104	3388
```

```bash
# 6. Routes apprises par le serveur de Lyon
az network nic show-effective-route-table -g "$RG_LYON_ST" -n "nic-${ST}-lyon-fs" \
  --query "value[?nextHopType=='VirtualNetworkGateway'].{Prefixe:addressPrefix[0], Saut:nextHopType}" \
  -o table
```
Sortie attendue (une ligne par stagiaire connecté côté Lyon) :
```
Prefixe      Saut
-----------  ---------------------
10.7.0.0/20  VirtualNetworkGateway
10.8.0.0/20  VirtualNetworkGateway
```

```bash
# 7. Test Lyon → serveur web du spoke app
lyon "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://10.${OCT}.4.10).Content.Trim() } catch { 'ECHEC' }"

# 8. Sauts suivants, aller et retour
az network watcher show-next-hop -g "$RG_LYON_ST" --vm "vm-${ST}-lyon-fs" \
  --source-ip "10.200.${OCT}.10" --dest-ip "10.${OCT}.4.10" --query nextHopType -o tsv
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.200.${OCT}.10" \
  --query "{Saut:nextHopType, IP:nextHopIpAddress}" -o table
```
Sortie attendue :
```
ECHEC
VirtualNetworkGateway
Saut              IP
----------------  ---------
VirtualAppliance  10.7.0.68
```

Explication attendue (étape 9) :
- Aller : `vm-st07-lyon-fs` → `vpngw-lyon` → tunnel → `vpngw-st07-hub`. Sans table de routes sur `GatewaySubnet`, la passerelle suit la route système `VNetPeering` vers `10.7.4.0/22` : le paquet arrive DIRECTEMENT sur la VM web, sans passer par le pare-feu ; `nsg-st07-web` l'autorise (port 80, toute source).
- Retour : la réponse de `10.7.4.10` vers `10.200.7.10` suit `rt-st07-spoke-app` (`0.0.0.0/0` → `10.7.0.68`) et arrive au pare-feu.
- Rejet : le pare-feu reçoit une réponse (SYN-ACK) d'une connexion qu'il n'a jamais vue ; son suivi d'états la rejette. De plus, aucune règle n'autorise Lyon. Correction : défi 05.3.

### Pourquoi
- Serveur de Lyon lancé avant l'exposé : 5 à 10 min de création d'une VM Windows absorbées par la théorie.
- Passerelle de réseau local = description de L'AUTRE extrémité : IP publique de son équipement VPN et plages joignables derrière lui ; côté Lyon, la formatrice décrit symétriquement le hub du stagiaire.
- Plage `10.200.<OCT>.0/24` et non `10.200.0.0/16` : seul le sous-réseau du stagiaire est annoncé ; les serveurs des autres stagiaires ne sont pas routés vers son hub.
- Connexion de type IPsec avec IKEv2 (valeur par défaut) et stratégie par défaut des deux côtés : la négociation aboutit sans paramétrage cryptographique.
- Clé partagée : identique des deux côtés, saisie par `read -s` ; en production, générée aléatoirement et stockée dans Azure Key Vault.
- `Connected` uniquement quand les deux connexions existent et que les clés concordent ; les compteurs d'octets prouvent que des paquets traversent réellement le tunnel (sondes IKE comprises).
- Routes effectives côté Lyon : la passerelle de Lyon injecte les plages de chaque passerelle locale (`10.<OCT>.0.0/20` par stagiaire) dans toutes les cartes de `vnet-lyon`.
- `show-next-hop` dans les deux sens : outil le plus rapide pour démontrer une asymétrie de routage, sans générer de trafic.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `lyon-vm.sh` : `snet-stNN introuvable` | Sous-réseau non préparé par la formatrice | Formatrice : `lyon-site.sh prepare <NN>` |
| `lyon-vm.sh` : `AuthorizationFailed` sur `subnets/join/action` | Rôle Contributeur de réseau absent sur `snet-stNN` | Formatrice : attribution du rôle (même commande) ; propagation jusqu'à 5 min |
| `RequestDisallowedByPolicy` sur la carte ou la VM | `francecentral` absente de la stratégie de régions de `rg-stNN-lyon`, ou disque OS sans tag | Formatrice : stratégie du M2 (voir guide) |
| `SkuNotAvailable` pour la VM Lyon | Taille indisponible ou quota vCPU atteint en France Central | `VM_SIZE=Standard_D2as_v6 ./scripts/labs/module-05/lyon-vm.sh $NN` ou `VM_SIZE=Standard_D2s_v6 …` selon disponibilité |
| Connexion `NotConnected` après 5 min | Clé différente, IP de `lng-stNN-lyon` erronée, ou `cn-lyon-to-stNN` absente | Comparer `LYON_IP` et `gatewayIpAddress` ; `lyon-site.sh status` (formatrice) ; recréer la connexion avec la bonne clé |
| Connexion `Connected`, routes Lyon absentes à l'étape 6 | VM de Lyon arrêtée ou encore en création | `az vm list -g rg-stNN-lyon -d -o table` ; attendre `VM running` |
| `lyon` : `Conflict` ou exécution très longue | `run-command` déjà en cours sur la VM, ou agent Windows pas encore prêt (premier démarrage) | Attendre 2 à 3 min, relancer une seule commande à la fois |
| Étape 7 réussie (réponse `vm-stNN-test-web`) | `rt-stNN-spoke-app` absente de `snet-web` (rattrapage M4 incomplet) : chemin direct dans les deux sens | Réassocier la table de routes ; le défi 05.3 suppose le routage du M4 |

## Défi 05.3 ⭐⭐⭐ — Flux hybrides Lyon ↔ Arvéo sous IaC

### Solution
Fichier `lyon-connectivity.bicep` (identique à `scripts/catch-up/module-05/lyon-connectivity.bicep`) :
```bicep
// lyon-connectivity.bicep — flux hybrides Lyon ↔ spokes Arvéo (solution du défi 05.3)
// Déployé dans rg-stNN-hub. Prérequis : état de fin du module 4 (pare-feu, stratégie, NSG/ASG).
//   - rt-stNN-gateway associée à GatewaySubnet : spokes → pare-feu (routage symétrique)
//   - groupe de collections rcg-lyon dans afwp-stNN-hub : Lyon → web (80, 443), Lyon → données (1433)
//   - règle Allow-SQL-From-Lyon dans nsg-stNN-data (module lyon-nsg-rule.bicep, rg-stNN-spoke)
// Déploiement : az deployment group create -g rg-stNN-hub -f lyon-connectivity.bicep -p numero=NN
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région du hub')
@allowed([ 'francecentral', 'westeurope' ])
param location string = 'francecentral'

var prefix = 'st${numero}'
var octet = int(numero)
var lyonSubnet = '10.200.${octet}.0/24'
var spokes = [
  {
    name: 'spoke-app-via-fw'
    prefix: '10.${octet}.4.0/22'
  }
  {
    name: 'spoke-data-via-fw'
    prefix: '10.${octet}.8.0/22'
  }
]
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: 'vnet-${prefix}-hub'
}

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' existing = {
  name: 'afw-${prefix}-hub'
}

resource policy 'Microsoft.Network/firewallPolicies@2023-11-01' existing = {
  name: 'afwp-${prefix}-hub'
}

var firewallPrivateIp = firewall.properties.ipConfigurations[0].properties.privateIPAddress

// ---------- Routage : GatewaySubnet → pare-feu ----------
resource rtGateway 'Microsoft.Network/routeTables@2023-11-01' = {
  name: 'rt-${prefix}-gateway'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false // obligatoire sur GatewaySubnet
    routes: [for spoke in spokes: {
      name: spoke.name
      properties: {
        addressPrefix: spoke.prefix
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: firewallPrivateIp
      }
    }]
  }
}

// Sous-réseau existant redéclaré à l'identique, table de routes en plus
resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: hubVnet
  name: 'GatewaySubnet'
  properties: {
    addressPrefix: '10.${octet}.0.0/27'
    routeTable: {
      id: rtGateway.id
    }
  }
}

// ---------- Filtrage : pare-feu ----------
resource rcgLyon 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: policy
  name: 'rcg-lyon'
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-lyon-autoriser'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-web'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.4.0/24'
            ]
            destinationPorts: [
              '80'
              '443'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-data-sql'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.8.0/24'
            ]
            destinationPorts: [
              '1433'
            ]
          }
        ]
      }
    ]
  }
}

// ---------- Filtrage : NSG du spoke données ----------
module nsgRule 'lyon-nsg-rule.bicep' = {
  name: 'lyon-nsg-rule'
  scope: resourceGroup('rg-${prefix}-spoke')
  params: {
    numero: numero
  }
}

output firewallPrivateIp string = firewallPrivateIp
output gatewaySubnetRouteTable string = gatewaySubnet.properties.routeTable.id
```

Module `lyon-nsg-rule.bicep` (même dossier) :
```bicep
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
```

Contrôle, prévisualisation, déploiement :
```bash
az bicep build --file lyon-connectivity.bicep --stdout > /dev/null && echo "Syntaxe OK"
az deployment group what-if -g "$RG_HUB" -f lyon-connectivity.bicep -p numero="$NN"
az deployment group create -g "$RG_HUB" -n lyon-connectivity \
  -f lyon-connectivity.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
```
Sortie attendue du `what-if` (fin, détail des propriétés omis) :
```
  + Microsoft.Network/firewallPolicies/afwp-st07-hub/ruleCollectionGroups/rcg-lyon [2023-11-01]
  + Microsoft.Network/routeTables/rt-st07-gateway [2023-11-01]
  ~ Microsoft.Network/virtualNetworks/vnet-st07-hub/subnets/GatewaySubnet [2023-11-01]
  + Microsoft.Network/networkSecurityGroups/nsg-st07-data/securityRules/Allow-SQL-From-Lyon [2023-11-01]

Resource changes: 3 to create, 1 to modify.
```
Puis `Succeeded` après 3 à 8 min (mise à jour du pare-feu associé à la stratégie).

Tests de la matrice :
```bash
WEB="http://10.${OCT}.4.10"; SQL="http://10.${OCT}.8.10:1433"; D80="http://10.${OCT}.8.10"
for url in "$WEB" "$SQL" "$D80"; do   # tests a, b, c
  lyon "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 $url).Content.Trim() } catch { 'ECHEC' }"
done
tester web "timeout 5 bash -c '</dev/tcp/10.200.${OCT}.10/3389' && echo OUVERT || echo ECHEC"   # d
az network watcher show-next-hop -g "$RG_LYON_ST" --vm "vm-${ST}-lyon-fs" \
  --source-ip "10.200.${OCT}.10" --dest-ip "10.${OCT}.8.10" --query nextHopType -o tsv   # e
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-data" \
  --source-ip "10.${OCT}.8.10" --dest-ip "10.200.${OCT}.10" \
  --query "[nextHopType, nextHopIpAddress]" -o tsv                                       # e
```
Sortie attendue (30 à 60 s par test exécuté sur une VM) :
```
vm-st07-test-web
vm-st07-test-data
ECHEC
ECHEC
VirtualNetworkGateway
VirtualAppliance	10.7.0.68
```
Le test e côté Lyon renvoie `VirtualNetworkGateway` : le passage par le pare-feu se décide dans `GatewaySubnet`, invisible depuis la VM de Lyon ; la preuve du passage est la réussite des tests a et b avec un retour par `VirtualAppliance`, et les journaux du pare-feu (M10).

Réponses attendues (étape 4) :
- a. La source vue par `vm-st07-test-data` reste `10.200.7.10` (pas de SNAT vers une destination privée). `Allow-SQL-From-Web` n'accepte que `10.7.4.0/24` ; l'étiquette `VirtualNetwork` couvre les plages des sites VPN (spoke en `useRemoteGateways`) et, avec l'UDR `0.0.0.0/0`, toute adresse : `Deny-VNet-Inbound` (priorité 4000) refuse le flux. Il faut une règle NSG explicite pour Lyon, plus prioritaire.
- b. `0.0.0.0/0` n'est pas pris en charge sur `GatewaySubnet` (création ou fonctionnement de la passerelle bloqués). Une route vers le hub `10.7.0.0/22` engloberait `AzureFirewallSubnet` et `GatewaySubnet` eux-mêmes : boucle vers le pare-feu ; et le hub n'héberge aucune charge de travail à protéger.
- c. Sans propagation, `GatewaySubnet` ne reçoit plus les routes de la passerelle elle-même : le trafic du tunnel n'est plus acheminé correctement, configuration non prise en charge par Microsoft ; la connectivité VPN est rompue.

### Pourquoi
- Routes par spoke (`/22`) et non par sous-réseau : tout nouveau sous-réseau d'un spoke est couvert sans modification de la table.
- IP du pare-feu lue sur `afw-stNN-hub` (`existing`) : le fichier reste juste si le pare-feu est recréé avec une autre adresse (rattrapage).
- `GatewaySubnet` redéclaré avec sa plage exacte : une ressource `subnets` est un remplacement complet ; une plage différente serait refusée (sous-réseau utilisé par la passerelle).
- Groupe `rcg-lyon` séparé de `rcg-arveo` : cycle de vie propre (supprimé d'un bloc à la fin de la migration de Lyon), priorité 300 après les règles internes.
- Règles réseau (et non d'application) : flux TCP vers des adresses privées, aucun FQDN ; le refus implicite couvre « tout autre port » (test c) et « spokes → Lyon » (test d).
- Règle NSG par module : le NSG est dans `rg-stNN-spoke`, une ressource Bicep ne cible qu'un seul groupe par déploiement ; destination en ASG `asg-stNN-data`, source en plage IP (cartes de Lyon hors du VNet de l'ASG).
- Priorité NSG 110 : à côté de `Allow-SQL-From-Web` (100), avant `Deny-VNet-Inbound` (4000).
- Aucune règle pour le retour des flux : pare-feu et NSG sont à états.
- Test d sur le port 3389 : port ouvert par défaut sur l'image Windows Server d'Azure, donc un échec ne vient pas de la VM de Lyon mais du pare-feu (aucune règle spokes → Lyon) `[À VÉRIFIER]` règle du pare-feu Windows sur l'image du jour.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `BCP120` / valeur non calculable au début du déploiement | IP du pare-feu utilisée dans un nom de ressource ou une boucle | L'utiliser uniquement dans `properties` (comme `nextHopIpAddress`) |
| `InUseSubnetCannotBeUpdated` / `GatewaySubnet` refusé | Plage différente de `10.<OCT>.0.0/27` dans la redéclaration | Recopier la plage exacte du script de passerelle |
| `RouteTableCannotDisableBgpPropagationOnGatewaySubnet` `[À VÉRIFIER]` libellé | `disableBgpRoutePropagation: true` sur la table de `GatewaySubnet` | `false` (valeur par défaut) |
| Déploiement en `Conflict` / `AnotherOperationInProgress` | Pare-feu ou VNet du hub encore en mise à jour | Attendre 2 à 5 min, relancer |
| Test a : `ECHEC` | Table non associée à `GatewaySubnet`, ou règle `lyon-vers-web` absente | `az network vnet subnet show ... -n GatewaySubnet --query routeTable.id` ; `rule-collection-group show ... -n rcg-lyon` |
| Test b : `ECHEC`, test a réussi | Règle NSG absente ou mal placée (sortante, priorité > 4000, source erronée) | `az network nsg rule list -g $RG_SPOKE --nsg-name nsg-$ST-data -o table` |
| Test c : réponse `vm-stNN-test-data` | Port `*` ou `80` ajouté à la règle Lyon → données | Restreindre à `1433` |
| Test d : `OUVERT` | Règle réseau trop large (source spokes, destination `10.200.0.0/16`) | Supprimer la règle ; aucun flux spokes → Lyon dans la matrice |
| `what-if` : `~` sur `GatewaySubnet` à chaque exécution | Propriétés par défaut ajoutées par la plateforme (`privateEndpointNetworkPolicies`) | Bruit acceptable si aucune route ni règle ne change |

### Variantes acceptables
- Route agrégée unique `10.<OCT>.4.0/22` + `10.<OCT>.8.0/22` remplacée par une route par sous-réseau : plus fine, à maintenir à chaque nouveau sous-réseau.
- Groupes d'adresses IP (`Microsoft.Network/ipGroups`) pour Lyon et les spokes : lisible à grande échelle, ressource supplémentaire.
- NSG rule et table de routes en Azure CLI, règles du pare-feu en Bicep : correct techniquement, hors de la contrainte « rejouable par un seul fichier ».
- Collection de refus explicite (Lyon → `10.<OCT>.0.0/20`, priorité 4000) pour journaliser nommément les flux interdits : valide.

## Étude de cas 05.4 — Choisir la connectivité hybride

### Solution
| Besoin | Solution | Arguments | Risque ou limite |
|---|---|---|---|
| 1. Migration de Lyon, ERP hybride | ExpressRoute (circuit 1 Gbit/s, peering privé) + VPN S2S existant en secours | Latence prévisible et SLA exigés par l'éditeur ; 40 To ≈ 90 h de transfert à 1 Gbit/s saturé, compatible avec 3 mois | Délai de commande opérateur (semaines) : commander immédiatement, migrer les premiers lots par VPN ou Azure Data Box |
| 2. 14 agences + 60 nomades | Virtual WAN Standard : VPN S2S des agences, point-to-site (authentification Entra ID) des nomades, Lyon raccordé au hub virtuel | 15 sites et plus, transit agence ↔ agence ↔ Lyon sans UDR, exploitation simplifiée | Refonte du hub-spoke actuel (hub virtuel + intention de routage), coût horaire du hub et des unités d'échelle |
| 3. Après Lyon | Plus de liaison hybride : applications publiées sur Internet (App Service, Application Gateway avec WAF), accès conditionnel Entra ID ; point-to-site réservé aux administrateurs | Coût réseau minimal, aucun équipement sur site, sécurité portée par l'identité | Dépendance à Internet ; exposition publique à protéger (WAF, MFA, journalisation) |

Calcul du point 1 : `40 × 10¹² octets × 8 / 10⁹ bit/s ≈ 320 000 s ≈ 89 h`, à pondérer par l'efficacité réelle du lien (souvent 70 à 80 %).

### Variantes acceptables
- Besoin 2 : passerelle VPN du hub montée en SKU (VpnGw2AZ, 30 tunnels S2S, point-to-site) avec BGP pour le transit agence ↔ agence : valable à 14 agences, moins évolutif ; la réponse doit citer la limite du nombre de tunnels.
- Besoin 1 : VPN S2S seul en VpnGw2AZ ou VpnGw3AZ si l'éditeur accepte une latence non garantie : moins cher, à argumenter par une mesure de latence.

## Bonus

### 1. Résolution DNS depuis Lyon
```bash
lyon 'try { (Resolve-DnsName sql.arveo.internal -ErrorAction Stop).IPAddress } catch { $_.Exception.Message }'
```
Sortie attendue :
```
sql.arveo.internal : DNS name does not exist
```
Le serveur de Lyon interroge le résolveur de son propre VNet ; la zone privée `arveo.internal` n'est liée qu'aux VNets Arvéo (M4). Dans un vrai datacenter, le DNS de Lyon ne peut de toute façon pas joindre `168.63.129.16`. Architecture cible : DNS Private Resolver dans le hub (point de terminaison entrant dans un sous-réseau dédié et délégué), redirecteur conditionnel `arveo.internal` sur le DNS de Lyon vers l'IP du point de terminaison entrant, flux UDP/TCP 53 Lyon → point de terminaison autorisé à travers le tunnel (et le pare-feu si une route l'y conduit).

### 2. PRA joignable depuis Lyon
Ajouts dans `lyon-connectivity.bicep` :
```bicep
// dans var spokes
  {
    name: 'spoke-pra-via-fw'
    prefix: '10.${octet}.12.0/22'
  }
```
```bicep
// dans rules de rc-lyon-autoriser
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-pra-https'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.12.0/24'
            ]
            destinationPorts: [
              '443'
            ]
          }
```
```bash
az deployment group create -g "$RG_HUB" -n lyon-connectivity \
  -f lyon-connectivity.bicep -p numero="$NN" --query properties.provisioningState -o tsv
az network watcher show-next-hop -g "$RG_LYON_ST" --vm "vm-${ST}-lyon-fs" \
  --source-ip "10.200.${OCT}.10" --dest-ip "10.${OCT}.12.4" --query nextHopType -o tsv
```
Sortie attendue :
```
Succeeded
VirtualNetworkGateway
```
Côté PRA, le retour doit aussi passer par le pare-feu : table de routes `rt-stNN-spoke-pra` (`0.0.0.0/0` → `10.<OCT>.0.68`, propagation désactivée) créée en **West Europe**, car une table de routes ne s'associe qu'à des sous-réseaux de sa région, puis associée à `snet-pra`. Le pare-feu de France Central reste le saut suivant à travers le peering global.

### 3. Stratégie IPsec effective
```bash
az network vpn-connection ipsec-policy list -g "$RG_HUB" \
  --connection-name "cn-${ST}-hub-to-lyon" -o json
```
Sortie attendue :
```
[]
```
Liste vide = aucune stratégie personnalisée : la passerelle propose et accepte sa liste de combinaisons par défaut (IKEv2). Une stratégie personnalisée sur une seule connexion restreint cette passerelle à UNE combinaison (chiffrement, intégrité, groupe DH, PFS, durées de vie) ; si la passerelle d'en face ne la propose pas, la phase 1 ou 2 échoue et la connexion reste `NotConnected`. Règle pratique : même stratégie, appliquée des deux côtés.

## QCM — Réponses
1. **C** — `allowGatewayTransit` sur le lien du hub prête sa passerelle aux VNets appairés.
2. **A** — `useRemoteGateways` exige que le lien distant autorise le transit de passerelle.
3. **B** — La passerelle de réseau local décrit le site distant : son IP publique et ses plages.
4. **A** — `lng-st07-lyon` contient l'IP de `vpngw-lyon` et la plage `10.200.7.0/24`.
5. **B** — Sans connexion correspondante en face, le tunnel ne s'établit pas.
6. **B** — Sans UDR sur `GatewaySubnet`, l'aller contourne le pare-feu et le retour y passe : rejet.
7. **B** — Une route `0.0.0.0/0` n'est pas prise en charge sur `GatewaySubnet`.
8. **B** — Le peering global relie des régions différentes par la dorsale Microsoft, sans passerelle.
9. **C** — ExpressRoute fournit une liaison privée via un opérateur, avec SLA.
10. **B** — Le niveau Standard ajoute transit VNet ↔ VNet, point-to-site, ExpressRoute et hub à hub.
