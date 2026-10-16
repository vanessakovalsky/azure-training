# Module 07 — Corrections

Toutes les commandes supposent le bloc de variables des exercices exécuté (`NN`, `OCT`, `ST`, `RG_*`, `LOC`, `TAGS`, fonction `vmrun`). Exemples de sortie pour le stagiaire 07.

## Exercice 07.1 ⭐ — Dimensionner les charges Arvéo

### Solution
| N° | Taille | Disques | Option tarifaire |
|---|---|---|---|
| 1 Portail web | 2 × `Standard_B2s_v2` (2 vCPU, 8 Gio), zones 1 et 2 (abonnement de formation : zone 2 seule, `web02` sans zone) | SSD Standard | Paiement à l'usage ; réservation envisageable après 3 mois de mesures |
| 2 ERP SQL Server | `Standard_E8s_v5` (8 vCPU, 64 Gio) ou `E8as_v5` | OS en SSD Premium ; données et journaux en SSD Premium v2 (ou Premium, cache `ReadOnly` pour les données, `None` pour les journaux) | Réservation 3 ans + Azure Hybrid Benefit (licences SQL avec SA) |
| 3 Calcul des tournées | `Standard_F16s_v2` (16 vCPU, 32 Gio) | SSD Standard (données d'entrée sur un partage ou un compte de stockage) | VM Spot, éviction « désallouer », relance par l'ordonnanceur |
| 4 Serveur de fichiers | Pas de VM : Azure Files + Azure File Sync (module 6) | Partage Azure Files (niveau optimisé pour les transactions ou à chaud) | Paiement à l'usage (6 mois), aucun système d'exploitation à maintenir |

Contrôles des étapes 2 et 3 :
```
Taille        Zones
------------  -------
Standard_B2s_v2  1,2,3
Quota                     Utilise    Limite
------------------------  ---------  --------
Total Regional vCPUs      24         100
Standard BSv2 Family vCPUs  24         100
```

### Pourquoi
- **Charge 1** : CPU moyen faible avec pics courts = profil type de la série B (crédits accumulés la nuit, consommés de 8 h à 10 h). Deux VMs dans deux zones = SLA 99,99 % avec le Load Balancer (S7.3). Une taille `D2s_v5` est acceptable si les pics s'allongent.
- **Charge 2** : ratio 8 Gio par vCPU = famille E. Fonctionnement 24 h/24 sur 3 ans = réservation (remise maximale sur une taille fixe) ; licences SQL avec SA = Azure Hybrid Benefit. Disques Premium : SLA de la VM unique et latence adaptée à une base. La lettre `s` est indispensable (disques Premium).
- **Charge 3** : calcul pur (2 Gio par vCPU) = famille F ; quelques heures par nuit et traitement relançable = Spot (remise forte, éviction acceptable).
- **Charge 4** : une VM pour servir des partages SMB impose système, correctifs, sauvegardes et licence ; Azure Files le fait en PaaS, et File Sync assure la transition avec Lyon. Le dimensionnement commence par la question « faut-il une VM ? ».
- **Quota** : 2 × B2s_v2 + 2 × B2s_v2 (API) = 8 vCPU par stagiaire en France Central ; avec 12 stagiaires, 96 vCPU (+ instances ajoutées par la mise à l'échelle, jusqu'à 2 de plus chacun).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| ERP proposé en `D8s_v5` | Ratio mémoire ignoré (32 Gio seulement) | Relire le profil : 64 Go → famille E |
| Taille sans `s` pour l'ERP | Disques Premium non compatibles | Choisir une taille dont le nom contient `s` |
| Réservation pour le calcul nocturne | 4 h/24 : la réservation est payée 24 h/24 | Spot ou paiement à l'usage |
| `list-skus` renvoie une ligne avec restrictions | Taille non proposée à l'abonnement dans la région | Choisir une autre taille ou ouvrir une demande de support |

### Variantes acceptables
- Charge 1 : `Standard_B2als_v2` ou `B2s_v2` (génération plus récente, prix proche) `[À VÉRIFIER]` disponibilité par zone.
- Charge 2 : plan d'économies au lieu d'une réservation si Arvéo prévoit de changer de taille ou de région ; SQL Server sur VM ou Azure SQL Managed Instance (PaaS) : choix d'architecture hors du périmètre AZ-104.
- Charge 3 : paiement à l'usage si le traitement ne supporte aucune interruption.

---

## Lab 07.2 ⭐ — Première VM sans IP publique, accès par Bastion

### Solution
Les commandes de l'énoncé sont complètes. Récapitulatif dans l'ordre :
```bash
./scripts/labs/module-07/bastion.sh "$NN"
az network public-ip create -g "$RG_SPOKE" -n "pip-${ST}-natgw" -l "$LOC" \
  --sku Standard --allocation-method Static --tags $TAGS -o none
az network nat gateway create -g "$RG_SPOKE" -n "ng-${ST}-app" -l "$LOC" \
  --public-ip-addresses "pip-${ST}-natgw" --idle-timeout 4 --tags $TAGS -o none
for SNET in snet-web snet-app; do
  az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
    -n "$SNET" --nat-gateway "ng-${ST}-app" -o none
done
mkdir -p ~/.arveo
[[ -s ~/.arveo/web-admin.txt ]] || ( umask 077; echo "Arv-$(openssl rand -hex 8)-Z9" > ~/.arveo/web-admin.txt )
ADMIN_PW=$(cat ~/.arveo/web-admin.txt)
SNET_WEB=$(az network vnet subnet show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
  -n snet-web --query id -o tsv)
az network nic create -g "$RG_APP" -n "nic-${ST}-web01" -l "$LOC" --subnet "$SNET_WEB" \
  --private-ip-address "10.${OCT}.4.11" --tags $TAGS -o none
az vm create -g "$RG_APP" -n "vm-${ST}-web01" -l "$LOC" --zone 2 --nics "nic-${ST}-web01" \
  --image Ubuntu2404 --size Standard_B2s_v2 \
  --os-disk-name "osdisk-${ST}-web01" --storage-sku StandardSSD_LRS \
  --admin-username arveoadmin --authentication-type password --admin-password "$ADMIN_PW" \
  --custom-data scripts/labs/module-07/cloud-init-web.yaml \
  --boot-diagnostics-storage "$DIAG_SA" --tags $TAGS -o table
vmrun web01 "cloud-init status --wait >/dev/null; curl -s localhost; curl -s --max-time 5 https://api.ipify.org; echo"
az disk create -g "$RG_APP" -n "disk-${ST}-web01-data" -l "$LOC" --zone 2 \
  --size-gb 32 --sku StandardSSD_LRS --tags $TAGS -o none
az vm disk attach -g "$RG_APP" --vm-name "vm-${ST}-web01" \
  --name "disk-${ST}-web01-data" --lun 0 --caching ReadOnly -o none
vmrun web01 "$(cat scripts/labs/module-07/init-data-disk.sh)"
```
Contrôle des critères :
```bash
az vm show -g "$RG_APP" -n "vm-${ST}-web01" -d --query "[zones[0], publicIps, privateIps]" -o tsv
vmrun web01 "findmnt -no SOURCE,TARGET /srv/arveo"
```
Sortie attendue :
```
1		10.7.4.11
/dev/sdc1 /srv/arveo
```
Étape 8, ressources attendues dans `rg-st07-app` : `nic-st07-web01`, `vm-st07-web01`, `osdisk-st07-web01`, `disk-st07-web01-data`. Aucune `publicIPAddresses`, aucun `networkSecurityGroups`.

### Pourquoi
- **Passerelle NAT d'abord** : les spokes ont été créés en 2026, leurs sous-réseaux sont privés par défaut (aucun accès sortant implicite), et le pare-feu a été supprimé en fin de J2. Sans sortie, cloud-init ne peut pas installer nginx (`apt` échoue en silence, page absente).
- **Carte réseau créée avant la VM** : nom conforme à la convention (`nic-st07-web01` au lieu de `vm-st07-web01VMNic`), IP fixe connue d'avance (pool du Load Balancer, documentation), et `az vm create --nics` ne crée alors ni IP publique ni NSG.
- **Mot de passe dans `~/.arveo`** : jamais dans le dépôt Git ni dans l'historique d'un fichier versionné ; le même mot de passe sert au Bicep (07.3) et au VMSS (07.5). En production : clé SSH ou connexion Entra ID, secret dans Key Vault.
- **Disque créé explicitement en zone 2** : un disque LRS est zonal ; l'attacher à une VM d'une autre zone est refusé. Créer le disque séparément rend la contrainte visible.
- **Montage par étiquette avec `nofail`** : l'ordre des périphériques `/dev/sdX` peut changer au redémarrage ; `nofail` évite un démarrage bloqué si le disque est détaché (restauration au M9).
- **Bastion dans le hub** : un seul point d'administration pour tous les spokes appairés, journalisé, sans port 22 ouvert sur Internet.
- **Diagnostics de démarrage vers `starveost<NN>diag`** : compte du socle (module 3) prévu pour cet usage ; capture d'écran et journal série consultables même quand la VM ne répond plus sur le réseau (démarrage bloqué, `fstab` erroné), et prérequis de la console série. Variante : stockage managé (aucun compte à gérer).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Étape 5 : page vide, `api.ipify.org` sans réponse | Passerelle NAT absente ou non associée à `snet-web` au moment du démarrage | Associer la passerelle, puis `vmrun web01 "cloud-init clean --logs && cloud-init init && cloud-init modules --mode final"` `[À VÉRIFIER]`, ou recréer la VM |
| `az vm create` : `InvalidParameter ... adminPassword` | Mot de passe vide (`ADMIN_PW` non défini dans une nouvelle session) | Relancer `ADMIN_PW=$(cat ~/.arveo/web-admin.txt)` |
| `RequestDisallowedByPolicy` sur le disque OS | Tag obligatoire du M2 absent sur une ressource implicite `[À VÉRIFIER]` avec la définition réelle du M2 | Vérifier `--tags $TAGS` ; ajouter les tags au disque après création si la stratégie est en mode audit |
| `az vm disk attach` : disque dans une autre zone | `az disk create` sans `--zone 2` | Supprimer le disque, le recréer avec `--zone 2` |
| `init-data-disk.sh` : « Aucun disque de données au LUN 0 » | Disque attaché sur un autre LUN, ou commande lancée avant la fin de l'attachement | `az vm show ... --query "storageProfile.dataDisks[].lun"` ; relancer |
| Bouton Bastion grisé ou « déploiement en cours » | Bastion encore en `Updating` | Attendre `Succeeded` (`az network bastion show ... --query provisioningState`) |
| Bastion : échec d'authentification | Mot de passe recopié avec une espace ou un retour à la ligne | `cat ~/.arveo/web-admin.txt` dans Cloud Shell, copier sans retour à la ligne |
| `--boot-diagnostics-storage` : compte introuvable | `DIAG_SA` vide (bloc de variables non rejoué, compte du M3 absent) | `echo $DIAG_SA` ; rattrapage du module 3, ou omettre l'option puis `az vm boot-diagnostics enable` (stockage managé) |
| `SkuNotAvailable` / quota atteint | Taille indisponible dans la zone ou quota de vCPU de la famille BSv2 atteint | Vérifier `list-skus` et `list-usage` (exercice 07.1) ; prévenir la formatrice |

---

## Exercice 07.3 ⭐⭐ — Deuxième serveur web en Bicep

### Solution
Fichier complet `scripts/labs/module-07/vm-web.bicep` :
```bicep
// vm-web.bicep — solution de l'exercice 07.3 : VM web du portail client Arvéo
// Déployé dans rg-stNN-app. Le sous-réseau snet-web est lu dans rg-stNN-spoke.
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
  zones: empty(zone) ? [] : [
    zone
  ]
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
      customData: base64(loadTextContent('cloud-init-web.yaml'))
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
```
Compilation, prévisualisation et déploiement :
```bash
cp scripts/labs/module-07/vm-web-squelette.bicep scripts/labs/module-07/vm-web.bicep
# (complétion des TODO)
az bicep build --file scripts/labs/module-07/vm-web.bicep
az deployment group what-if -g "$RG_APP" --template-file scripts/labs/module-07/vm-web.bicep \
  --parameters numero="$NN" nomCourt=web02 zone='' hostOctet=12 \
               adminPassword="$(cat ~/.arveo/web-admin.txt)"
az deployment group create -g "$RG_APP" -n vm-web02 \
  --template-file scripts/labs/module-07/vm-web.bicep \
  --parameters numero="$NN" nomCourt=web02 zone='' hostOctet=12 \
               adminPassword="$(cat ~/.arveo/web-admin.txt)" \
  --query "properties.outputs.{VM:vmName.value, IP:privateIp.value}" -o table
vmrun web02 "cloud-init status --wait >/dev/null; curl -s localhost"
```
Sortie attendue :
```
VM             IP
-------------  ---------
vm-st07-web02  10.7.4.12
<h1>Arveo - portail client v1</h1><p>Serveur : vm-st07-web02 - zone aucune</p>
```
Étape 5 :
- Mêmes paramètres : `what-if` n'annonce aucune création ni suppression ; quelques propriétés peuvent apparaître en `Modify` ou `Ignore` (valeurs ajoutées par la plateforme, mot de passe sécurisé) `[À VÉRIFIER]` selon la version de l'API.
- `zone=3` : `what-if` annonce une modification de `zones` ; le déploiement échoue : zone 3 refusée pour l'abonnement (`NotAvailableForSubscription`) et, de toute façon, zone d'une VM non modifiable (message de type `PropertyChangeNotAllowed` `[À VÉRIFIER]` libellé exact).

### Pourquoi
- **a.** Le disque OS est créé implicitement par la VM, dans la même zone qu'elle (ressource zonale enfant). Un disque de données créé séparément doit, lui, déclarer sa zone.
- **b.** La zone fait partie de l'identité physique de la VM : elle est fixée à la création. Pour déplacer une VM : recréer la VM dans la nouvelle zone à partir d'un instantané de ses disques (ou d'une sauvegarde, module 9), ou utiliser le déplacement régional vers zonal d'Azure `[À VÉRIFIER]` disponibilité. Dans une architecture HA, on ne déplace pas : on ajoute une instance dans l'autre zone et on retire l'ancienne.
- **c.** Non. `customData` n'est exécuté qu'au premier démarrage, et sa modification sur une VM existante est refusée par l'API. Une configuration à faire évoluer passe par une extension (lab 07.6) ou un outil de gestion de configuration.
- Modèle paramétré (nom court, zone, octet) : le même fichier crée `web03`, `web04` sans duplication ; le rattrapage du module (`scripts/catch-up/module-07/vm-web.bicep`) en est la version complète (pool de Load Balancer, identité managée, disque de données).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `BCP035 ... missing required properties: "createOption"` | TODO 3 incomplet | Ajouter `createOption: 'FromImage'` |
| `zones` refusé (`BCP037`) | Propriété placée dans `properties` | La déplacer au premier niveau de la ressource |
| `loadTextContent` : fichier introuvable | `vm-web.bicep` copié ailleurs que `scripts/labs/module-07/` | Chemin relatif au fichier Bicep : garder les deux fichiers dans le même dossier |
| Déploiement : `PrivateIPAddressInUse` | `hostOctet=11` (IP de `web01`) | `hostOctet=12` |
| `what-if` demande `adminPassword` | Paramètre sécurisé sans valeur | `adminPassword="$(cat ~/.arveo/web-admin.txt)"` |
| Page affiche « zone aucune » | `zones` oublié : VM régionale (non zonale) | Supprimer la VM et la recréer avec `zones` (zone non modifiable) |
| Déploiement : compte de stockage `starveost<NN>diag` introuvable | Compte du module 3 créé avec un suffixe | Ajouter `diagStorageName="$DIAG_SA"` aux paramètres |

### Variantes acceptables
- Paramètre `customData` passé en chaîne depuis la CLI (`loadTextContent` évité) : fonctionne, mais le fichier Bicep n'est plus autonome.
- Clé SSH (`linuxConfiguration.ssh.publicKeys`) au lieu du mot de passe : meilleure pratique en production ; l'accès Bastion se fait alors avec la clé privée (fichier local) ou une clé stockée dans Key Vault.
- Sous-réseau référencé par `resourceId('rg-...-spoke', 'Microsoft.Network/virtualNetworks/subnets', ...)` au lieu d'une ressource `existing` : équivalent.

---

## Lab 07.4 ⭐⭐ — Load Balancer public et bascule entre zones

### Solution
```bash
az network public-ip create -g "$RG_APP" -n "pip-${ST}-lbe-web" -l "$LOC" --sku Standard \
  --allocation-method Static --zone 1 2 3 --tags $TAGS -o none
az network lb create -g "$RG_APP" -n "lbe-${ST}-web" -l "$LOC" --sku Standard \
  --public-ip-address "pip-${ST}-lbe-web" --frontend-ip-name fe-web \
  --backend-pool-name bp-web --tags $TAGS -o none
az network lb probe create -g "$RG_APP" --lb-name "lbe-${ST}-web" -n hp-http \
  --protocol Http --port 80 --path / --interval 5 -o none
az network lb rule create -g "$RG_APP" --lb-name "lbe-${ST}-web" -n rule-http \
  --protocol Tcp --frontend-port 80 --backend-port 80 --frontend-ip-name fe-web \
  --backend-pool-name bp-web --probe-name hp-http --idle-timeout 4 \
  --disable-outbound-snat true -o none
for VM in web01 web02; do
  az network nic ip-config address-pool add -g "$RG_APP" --nic-name "nic-${ST}-${VM}" \
    --ip-config-name ipconfig1 --lb-name "lbe-${ST}-web" --address-pool bp-web -o none
done
LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
for i in $(seq 10); do curl -s --max-time 5 "http://${LB_IP}/"; echo; done \
  | grep -o 'vm-st[0-9]*-web0[12] - zone [0-9]' | sort | uniq -c
```
Sortie attendue (répartition variable) :
```
      6 vm-st07-web01 - zone 2
      4 vm-st07-web02 - zone aucune
```
Panne simulée :
```bash
vmrun web01 "systemctl stop nginx"
sleep 15
for i in $(seq 10); do curl -s --max-time 5 "http://${LB_IP}/"; echo; done \
  | grep -o 'vm-st[0-9]*-web0[12] - zone [0-9]' | sort | uniq -c
LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
az monitor metrics list --resource "$LB_ID" --metric DipAvailability --interval PT1M \
  --aggregation Average --offset 10m --query "value[0].timeseries[0].data[-3:].average" -o tsv
vmrun web01 "systemctl start nginx"
```
Sortie attendue :
```
     10 vm-st07-web02 - zone aucune
100
75
50
```
(La métrique, moyenne sur l'ensemble du pool, passe de 100 à 50 ; valeurs intermédiaires et délai d'apparition variables.)

### Pourquoi
- **a.** Une règle d'équilibrage Standard peut aussi servir au SNAT sortant des VMs du pool (méthode déconseillée : ports SNAT limités). Ici la passerelle NAT, associée à `snet-web`, prend en charge TOUTE la sortie du sous-réseau et prévaut sur le Load Balancer ; désactiver le SNAT de la règle rend ce choix explicite.
- **b.** `Allow-HTTP-HTTPS-Inbound` (priorité 100, source `*`, ports 80 et 443) de `nsg-st<NN>-web` (module 4). Un Load Balancer Standard est sécurisé par défaut : sans NSG qui autorise le flux, les connexions entrantes publiques vers le pool sont refusées. La sonde passe par la règle par défaut `AllowAzureLoadBalancerInBound`.
- **c.** Une VM de test ne sert pas le portail (page différente) : elle rendrait des réponses incohérentes. De plus elle est désallouée : la sonde la marquerait en échec. Un pool ne contient que des instances identiques du même service.
- La répartition n'est pas un « tourniquet » strict : hachage sur 5 éléments, chaque `curl` utilise un nouveau port source, d'où une répartition proche de 50/50 sur un grand nombre de requêtes.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `curl` sans réponse (expiration) | Pool vide, sonde en échec, ou table de routes encore associée à `snet-web` (réponses envoyées vers le pare-feu supprimé) | Vérifier le pool ; `az network vnet subnet show ... -n snet-web --query routeTable` ; dissocier (`module-04-firewall.sh`) |
| Une seule VM répond, même sans panne | nginx arrêté ou cloud-init non terminé sur l'autre VM | `vmrun web02 "systemctl is-active nginx; curl -s localhost"` |
| `address-pool add` : configuration IP introuvable | VM créée sans carte nommée (`vm-st07-web01VMNic`, configuration `ipconfigvm-st07-web01`) | `az vm show ... --query networkProfile.networkInterfaces[0].id` puis `az network nic show ... --query "ipConfigurations[].name"` |
| Erreur de zone à la création de l'IP publique | `--zone` omis puis ajouté (zone non modifiable) | Supprimer l'IP (non encore associée) et la recréer |
| Réponses encore réparties pendant la panne | Sonde pas encore en échec (intervalle) | Attendre 15 s de plus |

### Variantes acceptables
- Portail Azure (Load Balancer → Créer) : identique, à condition de cocher les deux cartes dans le pool et de choisir « Aucun » pour la connectivité sortante.
- Pool par adresses IP (`az network lb address-pool create --backend-address`) au lieu des cartes : valable pour un Load Balancer Standard `[À VÉRIFIER]` restrictions (pas de SNAT sortant, même VNet).
- Bicep : `scripts/catch-up/module-07/lb-web.bicep` + paramètre `lbBackendPoolIds` de `vm-web.bicep`.

---

## Défi 07.5 ⭐⭐⭐ — API de suivi des colis en VMSS

### Solution
Fichier Bicep (identique à `scripts/catch-up/module-07/vmss-api.bicep`) :
```bicep
// vmss-api.bicep — rattrapage M7 et solution du défi 07.5 : API de suivi des colis
// Déployé dans rg-stNN-app :
//   - nsg-stNN-app : filtrage de snet-app (association au sous-réseau par CLI, cf. deploy.sh) ;
//   - lbi-stNN-api : Load Balancer interne Standard, frontal 10.NN.5.100 zone-redondant, TCP 8080 ;
//   - vmss-stNN-api : groupe identique (VMSS) Flexible, sans zone (abonnement limité à la zone 2), 2 instances ;
//   - as-stNN-api : mise à l'échelle automatique 2 à 4 instances sur le CPU moyen.
// Le sous-réseau snet-app (rg-stNN-spoke) n'est PAS redéclaré : un PUT de sous-réseau
// réécrirait toutes ses propriétés (passerelle NAT, NSG, table de routes).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Mot de passe administrateur (fichier ~/.arveo/web-admin.txt)')
@secure()
param adminPassword string

param location string = resourceGroup().location
param vmSize string = 'Standard_B2s_v2'
param adminUsername string = 'arveoadmin'

@minValue(1)
param minInstances int = 2

@minValue(1)
param maxInstances int = 4

var prefix = 'st${numero}'
var octet = int(numero)
var lbName = 'lbi-${prefix}-api'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource snetApp 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  scope: resourceGroup('rg-${prefix}-spoke')
  name: 'vnet-${prefix}-spoke-app/snet-app'
}

// ---------- Filtrage de snet-app ----------
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}-app'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-API-From-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.${octet}.4.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.${octet}.1.0/26'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------- Équilibreur interne ----------
resource ilb 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: lbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-api'
        zones: [
          '1'
          '2'
          '3'
        ]
        properties: {
          subnet: {
            id: snetApp.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.${octet}.5.100'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'bp-api'
      }
    ]
    probes: [
      {
        name: 'hp-api'
        properties: {
          protocol: 'Http'
          port: 8080
          requestPath: '/'
          intervalInSeconds: 5
          numberOfProbes: 1
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-api'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-api')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-api')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'hp-api')
          }
          protocol: 'Tcp'
          frontendPort: 8080
          backendPort: 8080
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
        }
      }
    ]
  }
}

// ---------- Groupe identique Flexible ----------
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-03-01' = {
  name: 'vmss-${prefix}-api'
  location: location
  tags: tags
  // sans zone : abonnement de formation limité à la zone 2
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: minInstances
  }
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'api${numero}'
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: base64(loadTextContent('../../labs/module-07/cloud-init-api.yaml'))
        linuxConfiguration: {
          disablePasswordAuthentication: false
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: 'ubuntu-24_04-lts'
          sku: 'server'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          deleteOption: 'Delete'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
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
          enabled: true // stockage managé : aucun compte à gérer pour des instances éphémères
        }
      }
      networkProfile: {
        networkApiVersion: '2020-11-01'
        networkInterfaceConfigurations: [
          {
            name: 'nic-${prefix}-api'
            properties: {
              primary: true
              deleteOption: 'Delete'
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: snetApp.id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-api')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    ilb
  ]
}

// ---------- Mise à l'échelle automatique ----------
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'as-${prefix}-api'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'profil-cpu'
        capacity: {
          minimum: string(minInstances)
          maximum: string(maxInstances)
          default: string(minInstances)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
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
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
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

output nsgId string = nsgApp.id
output apiFrontendIp string = '10.${octet}.5.100'
```
Déploiement, associations au sous-réseau et tests :
```bash
az deployment group what-if -g "$RG_APP" --template-file scripts/catch-up/module-07/vmss-api.bicep \
  --parameters numero="$NN" adminPassword="$(cat ~/.arveo/web-admin.txt)"
az deployment group create -g "$RG_APP" -n vmss-api \
  --template-file scripts/catch-up/module-07/vmss-api.bicep \
  --parameters numero="$NN" adminPassword="$(cat ~/.arveo/web-admin.txt)" -o none
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" -n snet-app \
  --nsg "$(az network nsg show -g "$RG_APP" -n "nsg-${ST}-app" --query id -o tsv)" -o none
# a. six appels depuis web01 (instances prêtes 3 à 5 min après le déploiement)
vmrun web01 "for i in 1 2 3 4 5 6; do curl -s --max-time 3 http://10.${OCT}.5.100:8080/; done"
# b. zones des instances
az vm list -g "$RG_APP" --query "[?virtualMachineScaleSet].{Instance:name, Zone:zones[0]}" -o table
# c. SSH depuis web01 vers une instance
API1=$(az vm list -g "$RG_APP" -d --query "[?virtualMachineScaleSet] | [0].privateIps" -o tsv)
vmrun web01 "timeout 3 bash -c '</dev/tcp/${API1}/22' && echo OUVERT || echo FERME"
# d. profil de mise à l'échelle
az monitor autoscale show -g "$RG_APP" -n "as-${ST}-api" \
  --query "profiles[0].{Min:capacity.minimum, Max:capacity.maximum, Regles:length(rules)}" -o table
```
Sortie attendue (noms d'instances variables) :
```
{"service":"api-suivi-colis","instance":"api07ab12cd","zone":"1"}
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
{"service":"api-suivi-colis","instance":"api07ab12cd","zone":"1"}
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
{"service":"api-suivi-colis","instance":"api07ab12cd","zone":"1"}
Instance                  Zone
------------------------  ------
vmss-st07-api_1a2b3c4d    1
vmss-st07-api_5e6f7a8b    2
FERME
Min    Max    Regles
-----  -----  --------
2      4      2
```
La passerelle NAT reste associée à `snet-app` (lab 07.2) : la commande `subnet update --nsg` ne modifie que le NSG.

### Pourquoi
- **a.** Flexible : instances = VMs standard (gestion, extensions, sauvegarde comme n'importe quelle VM), répartition à la fois sur les zones et les domaines d'erreur, mode recommandé par Microsoft pour les nouveaux déploiements. Uniforme reste pertinent pour des parcs très homogènes à très grande échelle.
- **b.** Perte d'une instance : la sonde la retire, l'instance restante sert seule ; la mise à l'échelle recrée une instance pour revenir au minimum de 2. Avec un minimum de 1, une réduction nocturne laisserait une seule instance : sa perte couperait l'API jusqu'à la recréation. Sur un abonnement sans restriction, un VMSS en zones 1, 2 et 3 survit en plus à la perte d'une zone entière (instances réparties, frontal zone-redondant).
- **c.** Un sous-réseau déclaré en Bicep est envoyé en entier (PUT) : toute propriété absente du fichier (passerelle NAT, table de routes, délégation) est supprimée. Le sous-réseau appartient au réseau (module 4, `rg-st<NN>-spoke`) ; l'équipe applicative n'y ajoute que des associations ciblées.
- **Load Balancer interne zone-redondant** : son IP frontale survit à la perte d'une zone ; IP statique `10.<OCT>.5.100` pour que le portail v2 (lab 07.6) la référence de façon stable.
- **NSG** : `Deny-VNet-Inbound` (4000) bloque tout le reste du trafic interne, y compris les autres stagiaires et `web01` sur le port 22 ; la sonde (`168.63.129.16`) n'appartient pas à l'étiquette `VirtualNetwork`, la règle `Allow-AzureLoadBalancer` la rend explicite.
- **Règle de réduction plus lente** (10 min, seuil 25 %) que la règle d'augmentation (5 min, 70 %) : évite les oscillations.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `curl` vers `10.<OCT>.5.100:8080` sans réponse | Instances encore en cours de configuration (cloud-init) | Attendre 3 à 5 min ; `az vm run-command invoke -g ... -n <INSTANCE> --command-id RunShellScript --scripts "curl -s localhost:8080"` |
| Toujours sans réponse après 5 min | NSG sans autorisation de la sonde, ou passerelle NAT absente de `snet-app` (nginx non installé) | Vérifier `nsg-st<NN>-app` et `natGateway` de `snet-app` |
| `platformFaultDomainCount` refusé | Valeur > 1 avec des zones en mode Flexible | `platformFaultDomainCount: 1` (répartition par zone) |
| `PUT` de `snet-app` a supprimé la passerelle NAT | Sous-réseau redéclaré dans le Bicep | Réassocier par `az network vnet subnet update --nat-gateway` ; retirer le sous-réseau du fichier |
| Autoscale : `metricResourceUri` invalide | ID du VMSS mal formé ou ressource dans un autre groupe | Utiliser `vmss.id` |
| Une seule instance répond | Hachage du Load Balancer sur 6 appels | Relancer 10 à 20 appels ; vérifier l'état de santé des deux instances |

### Variantes acceptables
- CLI : `az network lb create --subnet <ID_SNET_APP> --private-ip-address 10.<OCT>.5.100 --frontend-ip-zone 1 2 3` `[À VÉRIFIER]` option de zone du frontal, puis `az vmss create --orchestration-mode Flexible --zones 1 2 3 --platform-fault-domain-count 1 --instance-count 2 --lb lbi-st<NN>-api --backend-pool-name bp-api --subnet <ID_SNET_APP> --public-ip-address "" --nsg "" --custom-data scripts/labs/module-07/cloud-init-api.yaml`, puis `az monitor autoscale create` (S7.3).
- Sonde TCP 8080 au lieu de HTTP : acceptée, mais moins fidèle (nginx peut écouter sans que l'application réponde).
- Règle NSG de la sonde omise : fonctionne grâce à la règle par défaut `AllowAzureLoadBalancerInBound` (65001), à condition qu'aucune règle personnalisée ne la masque.

---

## Lab 07.6 ⭐⭐ — Portail v2 par extension Custom Script

### Solution
```bash
SCRIPT_B64=$(sed "s/__OCT__/${OCT}/g" scripts/labs/module-07/portail-v2.sh | base64 -w0)
for VM in web01 web02; do
  az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-${VM}" \
    --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
    --protected-settings "{\"script\": \"${SCRIPT_B64}\"}" -o none
  az vm extension list -g "$RG_APP" --vm-name "vm-${ST}-${VM}" \
    --query "[].{VM:'${VM}', Nom:name, Etat:provisioningState}" -o tsv
done
LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
curl -s "http://${LB_IP}/"; curl -s "http://${LB_IP}/api/"
```
Sortie attendue :
```
web01	CustomScript	Succeeded
web02	CustomScript	Succeeded
<h1>Arveo - portail client v2</h1><p>Serveur : vm-st07-web02 - zone aucune</p>
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
```
Réapplication (étape 4) :
```bash
az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-web01" \
  --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
  --protected-settings "{\"script\": \"${SCRIPT_B64}\"}" -o none
vmrun web01 "grep -c 'Portail v2 deploye' /var/lib/waagent/custom-script/download/*/stdout"
az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-web01" \
  --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
  --protected-settings "{\"script\": \"${SCRIPT_B64}\"}" --force-update -o none
vmrun web01 "grep -c 'Portail v2 deploye' /var/lib/waagent/custom-script/download/*/stdout; tail -n 3 /var/log/azure/custom-script/handler.log"
```
Résultat attendu : un seul dossier `download/0/stdout` après la réapplication simple (configuration inchangée, aucune exécution), puis un dossier supplémentaire (`download/1/`) après `--force-update` `[À VÉRIFIER]` numérotation des dossiers selon la version de l'extension ; le journal du gestionnaire mentionne une nouvelle séquence d'exécution.

### Pourquoi
- **a.** Les paramètres protégés sont chiffrés jusqu'à la VM et ne sont jamais renvoyés par l'API (`az vm extension show` ne les affiche pas) ; un script peut contenir des adresses internes, des secrets ou des jetons. Les paramètres publics sont lisibles par tout lecteur de la ressource (rôle Lecteur).
- **b.** Une VM n'accepte qu'UNE extension Custom Script : la seconde configuration remplace la première (même ressource `CustomScript`), qui n'est pas réexécutée. Plusieurs étapes = un script d'orchestration unique, ou Run Command (plusieurs commandes nommées possibles).
- **c.** Non : l'extension est posée sur `web01` et `web02` uniquement. Pour un VMSS, l'extension se déclare dans le MODÈLE (`virtualMachineProfile.extensionProfile`) : chaque nouvelle instance la reçoit à sa création.
- **Attente de cloud-init dans le script** : appliqué juste après la création (rattrapage, Bicep), le script s'exécuterait pendant cloud-init, qui réécrirait ensuite la page v1.
- **Script idempotent** : fichiers réécrits entièrement, `nginx -t` avant `reload` ; une réexécution ne casse rien.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Extension `Failed`, `nginx: configuration file ... test failed` | `__OCT__` non remplacé ou `$uri` interprété | Vérifier le `sed` ; ne pas modifier les `\$` du script |
| `/api/` renvoie `502 Bad Gateway` | API absente ou non joignable (défi 07.5 non fait, NSG de `snet-app`) | Rattrapage M7, ou `vmrun web01 "curl -s http://10.<OCT>.5.100:8080/"` |
| `/api/` renvoie `504` après 3 s | Instances de l'API arrêtées ou sonde en échec | `az vm list -g rg-st<NN>-app -d --query "[?virtualMachineScaleSet].powerState"` |
| `Operation 'PUT' is not allowed ... another operation in progress` | Deux opérations d'extension simultanées sur la même VM | Attendre la fin de la première ; une extension à la fois |
| `--protected-settings` : JSON invalide | Guillemets mal échappés | Respecter `"{\"script\": \"${SCRIPT_B64}\"}"` |
| Page toujours en v1 sur une VM | Extension appliquée sur une seule VM | Répéter sur l'autre VM (la boucle de la solution) |

### Variantes acceptables
- `fileUris` vers le script stocké dans le compte de stockage du module 6 (SAS ou identité managée) + `commandToExecute` : utile pour de gros scripts ; impose un accès réseau au compte (private endpoint du module 6).
- Run Command managé (`az vm run-command create`) : plusieurs scripts nommés par VM, journal de sortie dans un blob ; adapté aux opérations ponctuelles.
- Bicep : ressource `virtualMachines/extensions` (rattrapage `main.bicep`, `replace()` de `__OCT__`).

---

## Lab 07.7 ⭐⭐ — Agent Azure Monitor et règle de collecte

### Solution
```bash
az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" \
  --query "{Region:location, Tarif:sku.name, Retention:retentionInDays, ID:customerId}" -o table
for VM in web01 web02; do
  az vm identity assign -g "$RG_APP" -n "vm-${ST}-${VM}" -o none
  az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-${VM}" \
    --publisher Microsoft.Azure.Monitor --name AzureMonitorLinuxAgent \
    --enable-auto-upgrade true -o none
done
az deployment group create -g "$RG_APP" -n dcr-arveo \
  --template-file scripts/labs/module-07/dcr-arveo-linux.bicep \
  --parameters numero="$NN" -o none
VM_ID=$(az vm show -g "$RG_APP" -n "vm-${ST}-web01" --query id -o tsv)
az monitor data-collection rule association list --resource "$VM_ID" \
  --query "[].{Association:name, Regle:dataCollectionRuleId}" -o tsv | sed 's#/subscriptions/.*/##'
vmrun web01 "logger -p auth.warning 'Arveo test AMA ${ST}'"
WS=$(az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" \
  --query customerId -o tsv)
az monitor log-analytics query -w "$WS" -o table --analytics-query \
  "Heartbeat | where TimeGenerated > ago(15m) | summarize Dernier=max(TimeGenerated) by Computer"
az monitor log-analytics query -w "$WS" -o table --analytics-query \
  "Syslog | where SyslogMessage has 'Arveo test AMA' | project TimeGenerated, Computer, Facility, SeverityLevel"
```
Sortie attendue (après 5 à 10 min, GUID et horodatages variables, colonnes techniques omises) :
```
Region         Tarif      Retention    ID
-------------  ---------  -----------  ------------------------------------
francecentral  PerGB2018  30           1b2c3d4e-0000-0000-0000-000000000000
dcra-vm-st07-web01	dcr-st07-linux
Computer       Dernier
-------------  ----------------------------
vm-st07-web01  2026-10-07T15:58:12.0000000Z
vm-st07-web02  2026-10-07T15:58:09.0000000Z
TimeGenerated                 Computer       Facility    SeverityLevel
----------------------------  -------------  ----------  ---------------
2026-10-07T15:57:40.0000000Z  vm-st07-web01  auth        warning
```

### Pourquoi
- **a.** L'agent s'authentifie auprès d'Azure Monitor (téléchargement de la configuration DCR, envoi des données) avec l'identité managée de la VM : aucune clé d'espace de travail à distribuer, contrairement à l'ancien agent Log Analytics.
- **b.** Créer une seconde règle de collecte de type Windows (journaux d'événements, compteurs Windows) vers le même espace de travail et l'associer à la VM Windows, sur laquelle on installe `AzureMonitorWindowsAgent`. Les règles sont indépendantes et cumulables.
- **c.** La règle de collecte `dcr-st<NN>-linux` (`facilityNames`) : modification dans le fichier Bicep et redéploiement ; les agents récupèrent la nouvelle configuration sans réinstallation.
- **Espace de travail du socle (`log-st<NN>-shared`, module 3)** : ressource transverse, partagée par toutes les charges (réseau, VMs, PaaS) ; un espace par application multiplierait les requêtes croisées et les droits à gérer au module 10.
- **Mise à jour automatique de l'agent** : correctifs appliqués par Azure, pas de version figée à maintenir.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `ResourceNotFound` sur l'espace de travail au déploiement de la DCR | `log-st<NN>-shared` absent (module 3 non fait) | `./scripts/catch-up/module-03/deploy.sh <NN>` puis redéployer la DCR |
| Extension AMA `Failed` | Pas de sortie Internet (passerelle NAT absente) ou pas d'identité managée | Vérifier `natGateway` de `snet-web` ; `az vm identity assign` puis réappliquer l'extension |
| `Heartbeat` vide après 15 min | Règle non associée, ou agent installé avant l'identité | Vérifier les associations ; redémarrer l'agent : `vmrun web01 "systemctl restart azuremonitoragent"` |
| `association list` : commande inconnue | Extension CLI `monitor-control-service` absente | `az config set extension.use_dynamic_install=yes_without_prompt` (bloc de variables) |
| `log-analytics query` : `PathNotFoundError` ou espace introuvable | Nom de l'espace passé au lieu de l'ID client | Utiliser `customerId` (GUID) |
| Déploiement DCR : `InvalidPayload` sur les compteurs | Noms de compteurs Linux différents de ceux attendus | Comparer avec une règle créée par le portail (compteurs `[À VÉRIFIER]` dans le fichier) |
| Syslog absent, `Heartbeat` présent | Niveau trop faible (`auth.info`) ou facilité non collectée | `logger -p auth.warning` ; vérifier `facilityNames` |

### Variantes acceptables
- Portail : VM → **Supervision** → **Insights** → **Activer** : installe l'agent et crée une règle `MSVMI-*` (données de VM Insights, tables `InsightsMetrics`, `VMProcess`) ; complémentaire de la règle Syslog.
- Azure Policy (initiative « Activer Azure Monitor pour les VMs ») : installation de l'agent et association de la règle à toute VM nouvelle, à l'échelle d'un groupe d'administration ; démonstration possible au module 10.

---

## Bonus

1. **Nom public du portail** :
   ```bash
   OLD=$(az network dns record-set a show -g "$RG_HUB" -z "arveo-${ST}.fr" -n www \
     --query "ARecords[0].ipv4Address" -o tsv)
   az network dns record-set a remove-record -g "$RG_HUB" -z "arveo-${ST}.fr" -n www \
     -a "$OLD" --keep-empty-record-set -o none
   az network dns record-set a add-record -g "$RG_HUB" -z "arveo-${ST}.fr" -n www -a "$LB_IP" -o none
   NS=$(az network dns zone show -g "$RG_HUB" -n "arveo-${ST}.fr" --query "nameServers[0]" -o tsv)
   nslookup "www.arveo-${ST}.fr" "$NS"
   curl -s -H "Host: www.arveo-${ST}.fr" "http://${LB_IP}/"
   ```
   Résultat attendu : `nslookup` renvoie l'IP de `pip-st<NN>-lbe-web` ; la zone n'étant pas déléguée (domaine fictif), la résolution publique ne fonctionne qu'en interrogeant directement le serveur de noms Azure.
2. **Connexion Entra ID** :
   ```bash
   az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-web02" \
     --publisher Microsoft.Azure.ActiveDirectory --name AADSSHLoginForLinux -o none
   az role assignment create --assignee "$(az ad signed-in-user show --query id -o tsv)" \
     --role "Virtual Machine Administrator Login" \
     --scope "$(az group show -n "$RG_APP" --query id -o tsv)" -o none
   ```
   Connexion Bastion avec « Microsoft Entra ID » `[À VÉRIFIER]` prise en charge selon la SKU de Bastion ; à défaut, `az ssh vm` depuis un poste ayant un accès réseau. Traçabilité : l'utilisateur nominatif (`st<NN>@<DOMAINE>`) apparaît dans `/var/log/auth.log` et dans les journaux de connexion Entra ID, au lieu du compte partagé `arveoadmin`. Retrait de l'accès = retrait du rôle, sans toucher à la VM.
3. **Groupe à haute disponibilité** :
   ```bash
   az vm availability-set create -g "$RG_APP" -n "avail-${ST}-web" \
     --platform-fault-domain-count 2 --platform-update-domain-count 5 -o none
   az vm create -g "$RG_APP" -n "vm-${ST}-test-as" --availability-set "avail-${ST}-web" --zone 2 \
     --image Ubuntu2404 --size Standard_B2s_v2 --public-ip-address "" --nsg "" \
     --subnet "$SNET_WEB" --admin-username arveoadmin --generate-ssh-keys -o none
   az vm availability-set delete -g "$RG_APP" -n "avail-${ST}-web"
   ```
   Résultat attendu : la création de la VM échoue (zone et groupe à haute disponibilité mutuellement exclusifs, message `[À VÉRIFIER]` libellé exact) ; aucune VM créée, seul le groupe est à supprimer.
4. **Mise à l'échelle sous charge** : la métrique `Percentage CPU` du VMSS est une MOYENNE sur toutes les instances. Avec 2 instances `B2s_v2` (1 vCPU), une instance à 100 % et l'autre à 5 % donnent 52,5 % < 70 % : aucune augmentation. Il faut charger toutes les instances (ou baisser le seuil). L'historique (`Autoscale scale up` dans le journal d'activité) apparaît après la fenêtre de 5 min et le délai de traitement du moteur de mise à l'échelle.

## QCM — Réponses
1. **B** — `s` = taille compatible avec les disques Premium SSD ; `a` = AMD, `d` = disque temporaire, `p` = ARM.
2. **B** — `deallocate` libère le matériel : le calcul n'est plus facturé ; `stop` arrête l'OS mais conserve l'allocation (facturée).
3. **C** — le disque temporaire est local à l'hôte et perdu à la désallocation, au redimensionnement ou en cas de panne de l'hôte.
4. **A** — depuis le 31 mars 2026, les nouveaux VNets ont des sous-réseaux privés : il faut une méthode de sortie explicite (passerelle NAT, pare-feu, LB, IP publique).
5. **B** — Basic (et au-delà) atteint les VMs des VNets appairés ; Developer est limité au VNet où il est activé.
6. **C** — deux VMs dans deux zones : 99,99 % ; groupe à haute disponibilité : 99,95 % ; VM unique Premium/Ultra : 99,9 %.
7. **B** — l'appartenance à un groupe à haute disponibilité se définit uniquement à la création ; il faut recréer la VM.
8. **A** — la passerelle NAT assure la sortie du sous-réseau ; désactiver le SNAT de la règle évite une double méthode de sortie et l'épuisement des ports SNAT du LB.
9. **B** — sans changement de configuration, l'extension n'est pas réexécutée ; `--force-update` (ou un horodatage différent) force une nouvelle exécution.
10. **B** — agent AMA (extension) + règle de collecte de données + association de la règle à la VM ; MMA est retiré depuis le 31 août 2024.
