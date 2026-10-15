# Module 04 — Corrections

Exemples donnés pour le stagiaire 07 (`NN=07`, `OCT=7`). Toutes les solutions supposent le bloc de variables des exercices exécuté dans Cloud Shell (Bash).

## Lab 04.1 ⭐ — Plan d'adressage et réseaux hub-spoke

### Solution
Plan d'adressage du stagiaire 07 :

| Réseau ou sous-réseau | Plage | Adresses attribuables |
|---|---|---|
| `vnet-st07-hub` | `10.7.0.0/22` | 1 024 adresses à répartir (pas de réservation au niveau du VNet) |
| `GatewaySubnet` | `10.7.0.0/27` | 32 − 5 = 27 |
| `AzureFirewallSubnet` | `10.7.0.64/26` | 64 − 5 = 59 |
| `AzureFirewallManagementSubnet` | `10.7.0.128/26` | 59 |
| `AzureBastionSubnet` | `10.7.1.0/26` | 59 |
| `snet-shared` | `10.7.2.0/24` | 251 |
| `vnet-st07-spoke-app` / `snet-web` / `snet-app` | `10.7.4.0/22` / `10.7.4.0/24` / `10.7.5.0/24` | 251 + 251 (réserve `10.7.6.0/23`) |
| `vnet-st07-spoke-data` / `snet-data` / `snet-pe` | `10.7.8.0/22` / `10.7.8.0/24` / `10.7.9.0/24` | 251 + 251 (réserve `10.7.10.0/23`) |
| Sous-réseau Lyon du stagiaire | `10.200.7.0/24` | 251 |

Commandes : celles des étapes du lab, sans modification.

### Pourquoi
- Un /22 par réseau : 4 /24 par VNet, dont 2 en réserve de croissance ; les blocs `10.NN.0.0/22`, `10.NN.4.0/22`, `10.NN.8.0/22` sont alignés (adresse de début multiple de 4 sur le troisième octet), condition d'un préfixe /22 valide.
- Deuxième octet = numéro du stagiaire : aucun chevauchement entre stagiaires, aucun avec Lyon (`10.200.0.0/16`), plage lisible au premier coup d'œil dans les journaux.
- Hub créé par le script de la passerelle avec TOUS ses sous-réseaux : une passerelle en cours de provisionnement verrouille les modifications du VNet pendant 30 à 45 min.
- `$((10#$NN))` : Bash interprète `07` en base 10 (sans `10#`, `08` et `09` sont des octaux invalides) et retire le zéro en tête, refusé par Azure dans une adresse IP.
- `check-ip-address` : `.0` à `.3` et `.255` réservés dans un /24 (réseau, passerelle par défaut, deux adresses DNS Azure, diffusion) ; première adresse attribuable `.4`.
- IP publique Standard + `--zone 1 2 3` : zone-redondante, exigée par les SKU de passerelle `AZ` et recommandée partout ailleurs ; supprimée aussitôt car facturée à l'heure, même inutilisée.
- VMs de test sans IP publique ni NSG de carte : aucun accès entrant depuis Internet, filtrage porté uniquement par les NSG de sous-réseau de l'exercice 04.2, tests par `run-command` (canal de l'agent Azure, pas le réseau).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `InvalidAddressPrefixFormat` ou adresse `10.07.4.0` | Variable `NN` utilisée à la place de `OCT` | Utiliser `10.${OCT}...` ; vérifier `echo $OCT` |
| `bash: 10#08: value too great for base` | Syntaxe `$((NN))` sans `10#` | `OCT=$((10#$NN))` |
| `NetcfgInvalidSubnet` / `InvalidCIDRNotation` | Préfixe non aligné (ex. `10.7.5.0/22`) | Début du bloc multiple de sa taille : `10.7.4.0/22` |
| `NetcfgSubnetRangesOverlap` | Sous-réseau chevauchant un autre du même VNet | Comparer avec `az network vnet subnet list` |
| `RequestDisallowedByPolicy` sur le VNet ou l'IP publique | `--tags` oublié ou région non autorisée (M2) | Ajouter `--tags $TAGS`, vérifier `LOC` |
| Le script de passerelle échoue sur `vnet-gateway create` : quota ou `PublicIPCountLimitReached` | Quota d'IP publiques ou de passerelles de l'abonnement partagé | Prévenir la formatrice (demande de quota J-10) |
| `test-vms.sh` : `RequestDisallowedByPolicy` sur un disque | Disque OS implicite créé sans tags, stratégie « tag obligatoire » du M2 en refus | Formatrice : exclusion `Microsoft.Compute/disks` ou effet « hériter du tag du groupe » |
| `SkuNotAvailable` pour les VMs de test | Taille indisponible en France Central ou quota vCPU atteint | `VM_SIZE=Standard_F1als_v7 ./scripts/labs/module-04/test-vms.sh $NN` ou `VM_SIZE=Standard_F1alds_v7 …` selon disponibilité (le script choisit automatiquement selon NN) |
| `--tags $TAGS` crée un seul tag `Projet` contenant tout le texte | Variable entre guillemets (`"$TAGS"`) | Laisser `$TAGS` sans guillemets (découpage en trois paires) |

## Exercice 04.2 ⭐⭐ — Filtrer avec NSG et ASG

### Solution
```bash
# 1. NSG du sous-réseau web
az network nsg create -g "$RG_SPOKE" -n "nsg-${ST}-web" -l "$LOC" --tags $TAGS -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-web" \
  -n Allow-HTTP-HTTPS-Inbound --priority 100 --direction Inbound \
  --access Allow --protocol Tcp --destination-port-ranges 80 443 -o none
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
  -n snet-web --network-security-group "nsg-${ST}-web" -o none

# 2. ASG et carte réseau de la VM de données
az network asg create -g "$RG_SPOKE" -n "asg-${ST}-data" -l "$LOC" --tags $TAGS -o none
az network nic ip-config update -g "$RG_SPOKE" --nic-name "nic-${ST}-test-data" \
  -n ipconfig1 --application-security-groups "asg-${ST}-data" -o none

# 3. NSG du sous-réseau données
az network nsg create -g "$RG_SPOKE" -n "nsg-${ST}-data" -l "$LOC" --tags $TAGS -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-data" \
  -n Allow-SQL-From-Web --priority 100 --direction Inbound --access Allow \
  --protocol Tcp --source-address-prefixes "10.${OCT}.4.0/24" \
  --destination-asgs "asg-${ST}-data" --destination-port-ranges 1433 -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-data" \
  -n Deny-VNet-Inbound --priority 4000 --direction Inbound --access Deny \
  --protocol '*' --source-address-prefixes VirtualNetwork \
  --destination-address-prefixes '*' --destination-port-ranges '*' -o none
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
  -n snet-data --network-security-group "nsg-${ST}-data" -o none

# 4. Règles entrantes effectives
az network nic list-effective-nsg -g "$RG_SPOKE" -n "nic-${ST}-test-data" \
  --query "value[0].effectiveSecurityRules[?direction=='Inbound'].{Nom:name, Prio:priority, Acces:access}" \
  -o table
```
Sortie attendue (étape 4) :
```
Nom                                                 Prio    Acces
--------------------------------------------------  ------  -------
securityRules/Allow-SQL-From-Web                    100     Allow
securityRules/Deny-VNet-Inbound                     4000    Deny
defaultSecurityRules/AllowVnetInBound               65000   Allow
defaultSecurityRules/AllowAzureLoadBalancerInBound  65001   Allow
defaultSecurityRules/DenyAllInBound                 65500   Deny
```

IP flow verify (étape 5) :
```bash
test_flux() {   # test_flux <IP_SOURCE> <PORT_DESTINATION>
  az network watcher test-ip-flow -g "$RG_SPOKE" --vm "vm-${ST}-test-data" \
    --direction Inbound --protocol TCP \
    --local "10.${OCT}.8.10:$2" --remote "$1:50000" \
    --query "[access, ruleName]" -o tsv | paste -sd' '
}
test_flux "10.${OCT}.4.10" 1433   # cas a
test_flux "10.${OCT}.5.20" 1433   # cas b
test_flux "10.${OCT}.4.10" 22     # cas c
test_flux "10.${OCT}.9.20" 1433   # cas d
```
Sortie attendue (20 à 40 s par test) :
```
Allow securityRules/Allow-SQL-From-Web
Deny defaultSecurityRules/DenyAllInBound
Deny defaultSecurityRules/DenyAllInBound
Deny securityRules/Deny-VNet-Inbound
```

Explication attendue (étape 6) : sans peering, l'étiquette `VirtualNetwork` de la carte `nic-st07-test-data` ne contient que l'espace d'adressage du spoke données (`10.7.8.0/22`). Les sources `10.7.4.10` et `10.7.5.20` n'y figurent pas : ni `Deny-VNet-Inbound` ni `AllowVnetInBound` ne s'appliquent, la règle par défaut `DenyAllInBound` tranche. La source `10.7.9.20` appartient au même VNet : sans la règle explicite de priorité 4000, `AllowVnetInBound` (65000) l'aurait AUTORISÉE.

### Pourquoi
- NSG au niveau sous-réseau : une règle couvre toutes les VMs présentes et futures du sous-réseau ; aucun NSG de carte, donc un seul point d'évaluation.
- Destination en ASG, source en plage IP : les cartes d'un ASG doivent toutes être dans le même VNet, et une règle qui utilise des ASG en source ET en destination exige des cartes dans un même VNet. Le web et les données sont dans deux spokes distincts.
- `Deny-VNet-Inbound` en priorité 4000 : sous les règles d'autorisation métier (100 à 3999), au-dessus des règles par défaut (65000+) ; neutralise `AllowVnetInBound`, trop large pour un sous-réseau de données.
- Pas de refus « tout depuis Internet » : déjà assuré par `DenyAllInBound` ; `AllowAzureLoadBalancerInBound` conservée pour les sondes d'intégrité (M7).
- `list-effective-nsg` : vision fusionnée des NSG de sous-réseau et de carte, telle que la plateforme l'applique ; nécessite une VM démarrée.
- IP flow verify : test logique côté plateforme, sans paquet réel ; donne la règle décisive, ce qu'un `curl` en échec ne donne jamais.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `SecurityRuleInvalidAddressPrefix` / ASG refusé | ASG d'un autre VNet en source et destination | Source en plage IP `10.<OCT>.4.0/24` |
| `ApplicationSecurityGroupsNotInSameVnet` `[À VÉRIFIER]` libellé | Carte d'un autre VNet ajoutée à `asg-stNN-data` | Retirer la carte ; un ASG = un VNet |
| `list-effective-nsg` : `NetworkInterfaceNotAttachedToVM` ou erreur VM arrêtée | VM désallouée ou encore en création | `az vm start` ou attendre `VM running` |
| `test-ip-flow` : `AuthorizationFailed` sur `NetworkWatcherRG` | Droits Network Watcher manquants | Formatrice : rôle Contributeur de réseau sur `NetworkWatcherRG` |
| `test-ip-flow` : `NetworkWatcherNotFound` | Network Watcher non activé en France Central | Formatrice : `az network watcher configure -g NetworkWatcherRG -l francecentral --enabled true` |
| Cas d décidé par `AllowVnetInBound` | Règle `Deny-VNet-Inbound` absente, en sens `Outbound` ou avec une source autre que `VirtualNetwork` | `az network nsg rule list -g $RG_SPOKE --nsg-name nsg-$ST-data -o table` |
| `Rule name ... already exists` à la relance | Script rejoué | Sans gravité : `rule create` sur un nom existant met la règle à jour `[À VÉRIFIER]` selon la version de la CLI |

### Variantes acceptables
- Règle de refus avec destination `asg-stNN-data` au lieu de `*` : équivalente aujourd'hui, mais moins protectrice si une VM sans ASG est ajoutée au sous-réseau.
- NSG créé par Bicep : préférable en production (cohérent avec le M3), plus long à écrire dans le temps imparti.
- `--destination-port-ranges 80 443` remplacé par deux règles distinctes : correct, mais deux priorités à gérer.

## Exercice 04.3 ⭐⭐ — Pare-feu, peerings et routes

### Solution
```bash
# 1. Déploiement du pare-feu (avant l'exposé)
az deployment group create -g "$RG_HUB" -n firewall \
  -f scripts/labs/module-04/firewall.bicep -p numero="$NN" --no-wait

# 2. Peerings
HUB_ID=$(az network vnet show -g "$RG_HUB" -n "vnet-${ST}-hub" --query id -o tsv)
APP_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" --query id -o tsv)
DATA_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-data" --query id -o tsv)

az network vnet peering create -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-app --remote-vnet "$APP_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
az network vnet peering create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
  -n peer-spoke-app-to-hub --remote-vnet "$HUB_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
az network vnet peering create -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-data --remote-vnet "$DATA_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
az network vnet peering create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
  -n peer-spoke-data-to-hub --remote-vnet "$HUB_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
```
Sortie attendue :
```
Initiated
Connected
Initiated
Connected
```

Test avant routage (étape 3) :
```bash
az vm run-command invoke -g "$RG_SPOKE" -n "vm-${ST}-test-web" \
  --command-id RunShellScript \
  --scripts "curl -s -m 5 http://10.${OCT}.8.10:1433 || echo ECHEC" \
  --query "value[0].message" -o tsv
```
Sortie attendue :
```
Enable succeeded: 
[stdout]
ECHEC

[stderr]
```

Fin du déploiement et IP du pare-feu (étape 4) :
```bash
az deployment group wait --created -g "$RG_HUB" -n firewall
FW_IP=$(az deployment group show -g "$RG_HUB" -n firewall \
  --query properties.outputs.firewallPrivateIp.value -o tsv)
echo "$FW_IP"
```
Sortie attendue :
```
10.7.0.68
```

Tables de routes (étape 5) :
```bash
for spoke in app data; do
  az network route-table create -g "$RG_SPOKE" -n "rt-${ST}-spoke-${spoke}" -l "$LOC" \
    --disable-bgp-route-propagation true --tags $TAGS -o none
  az network route-table route create -g "$RG_SPOKE" \
    --route-table-name "rt-${ST}-spoke-${spoke}" -n default-via-fw \
    --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$FW_IP" -o none
done
for subnet in snet-web snet-app; do
  az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
    -n "$subnet" --route-table "rt-${ST}-spoke-app" -o none
done
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
  -n snet-data --route-table "rt-${ST}-spoke-data" -o none
```

Routes effectives et saut suivant (étape 6) :
```bash
az network nic show-effective-route-table -g "$RG_SPOKE" -n "nic-${ST}-test-web" \
  --query "value[?state=='Active' && nextHopType!='None'].{Source:source, Prefixe:addressPrefix[0], Saut:nextHopType, IP:nextHopIpAddress[0]}" \
  -o table
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.${OCT}.8.10" \
  --query "{Saut:nextHopType, IP:nextHopIpAddress}" -o table
```
Sortie attendue :
```
Source    Prefixe      Saut              IP
--------  -----------  ----------------  ---------
Default   10.7.4.0/22  VnetLocal
Default   10.7.0.0/22  VNetPeering
User      0.0.0.0/0    VirtualAppliance  10.7.0.68

Saut              IP
----------------  ---------
VirtualAppliance  10.7.0.68
```

Le test de l'étape 7 (même commande que l'étape 3) renvoie toujours `ECHEC`.

Réponses de lecture du fichier Bicep (étape 1) :
- Ressources : `pip-stNN-fw`, `pip-stNN-fw-mgmt`, stratégie `afwp-stNN-hub` (niveau Basic), pare-feu `afw-stNN-hub` ; le VNet du hub est seulement référencé (`existing`).
- Deux IP publiques : l'une pour le trafic (SNAT sortant, DNAT entrant), l'autre pour la gestion du service par la plateforme, exigée par le niveau Basic.
- `ipConfigurations` → `AzureFirewallSubnet` ; `managementIpConfiguration` → `AzureFirewallManagementSubnet`.
- Stratégie vide à la création : AUCUN flux autorisé (refus implicite).

Causes d'échec attendues :
- Étape 3 : pas de route vers `10.7.8.0/22` dans le spoke app (peering non transitif) ; le paquet suit la route système `10.0.0.0/8` → `None` et est abandonné avant même de quitter le spoke.
- Étape 7 : le paquet atteint le pare-feu (saut `VirtualAppliance`), qui le refuse faute de règle correspondante.

### Pourquoi
- Déploiement du pare-feu lancé avant l'exposé : 5 à 15 min de provisionnement absorbées par la théorie.
- Peering = deux objets : chaque VNet déclare son côté ; `Initiated` signale un lien sans réciproque, `Connected` un lien complet.
- `--allow-forwarded-traffic` côté spoke : le trafic venu de l'autre spoke arrive avec une adresse source hors du hub ; sans ce réglage, le spoke le rejette. Côté hub, utile au retour des flux relayés.
- `--allow-vnet-access` : autorise la communication directe hub ↔ spoke (pare-feu ↔ VMs).
- Aucune option de passerelle (`--allow-gateway-transit`, `--use-remote-gateways`) à ce stade : traitée au M5 avec la liaison VPN.
- Une table par spoke, route `0.0.0.0/0` unique : couvre l'Internet ET l'autre spoke (absent des routes système) ; le trafic intra-spoke reste en `VnetLocal`, préfixe plus long.
- Table associée aux DEUX spokes : routage symétrique ; une seule table produirait un retour hors pare-feu, rejeté par son suivi d'états.
- Propagation BGP désactivée : au M5, les routes de Lyon apprises par la passerelle n'atteindront pas les spokes ; le trafic vers Lyon passera par la route `0.0.0.0/0`, donc par le pare-feu.
- Routes `None` réservées (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`) : marquées `Invalid` en présence d'une UDR `0.0.0.0/0` `[À VÉRIFIER]` libellé d'état ; d'où le filtre `nextHopType!='None'` pour un affichage lisible.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `peering create` côté hub : `AnotherOperationInProgress` ou `ReferencedResourceNotProvisioned` | Passerelle VPN encore en `Updating` | Attendre `Succeeded` (`az network vnet-gateway show ... --query provisioningState`) puis relancer |
| `RemoteVnetHasOverlappingAddressSpace` / chevauchement | Plage d'un spoke identique au hub (erreur de `OCT`) | Corriger la plage du spoke (suppression et recréation) |
| `peeringState` reste `Initiated` | Lien réciproque non créé ou créé avec un mauvais ID | `az network vnet peering list` des deux côtés |
| `az deployment group wait` ne rend pas la main | Déploiement en échec ou toujours en cours | `az deployment group show -g ... -n firewall --query properties.provisioningState` ; en cas d'échec, `--query properties.error` |
| Déploiement du pare-feu : `AzureFirewallManagementSubnet` introuvable | Script de passerelle lancé avant sa mise à jour ou hub créé à la main | Relancer `./scripts/prereq-vpn-gateways.sh $NN` (idempotent, ajoute les sous-réseaux manquants) |
| `FW_IP` vide | Déploiement non terminé ou variable perdue (session fermée) | Relancer `az deployment group show ... --query properties.outputs.firewallPrivateIp.value -o tsv` |
| `run-command` : `Conflict` ou exécution très longue | Une commande `run-command` est déjà en cours sur la VM | Attendre la fin de la précédente (une seule à la fois par VM) |
| `show-effective-route-table` : erreur VM arrêtée | VM désallouée | `az vm start -g $RG_SPOKE -n vm-$ST-test-web` |

### Variantes acceptables
- Peerings et tables de routes en Bicep : recommandé en production ; c'est l'approche du script de rattrapage `scripts/catch-up/module-04/`.
- Routes spécifiques vers l'autre spoke (`10.<OCT>.8.0/22` → pare-feu) en plus de `0.0.0.0/0` : plus explicite, sans effet différent ici.
- Peering créé par le portail : une seule opération crée les deux liens ; acceptable, mais non reproductible.

## Défi 04.4 ⭐⭐⭐ — Règles du pare-feu sous IaC

### Solution
Fichier `firewall-rules.bicep` (identique à `scripts/catch-up/module-04/firewall-rules.bicep`) :
```bicep
// firewall-rules.bicep — règles du pare-feu Arvéo (solution du défi 04.4)
// Ajoute le groupe de collections rcg-arveo à la stratégie existante afwp-stNN-hub.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('FQDN autorisés en sortie depuis les spokes (HTTP et HTTPS)')
param allowedFqdns array = [
  '*.ubuntu.com'
]

var prefix = 'st${numero}'
var octet = int(numero)
var webSubnet = '10.${octet}.4.0/24'
var dataSubnet = '10.${octet}.8.0/24'
var spokeApp = '10.${octet}.4.0/22'
var spokeData = '10.${octet}.8.0/22'

resource policy 'Microsoft.Network/firewallPolicies@2023-11-01' existing = {
  name: 'afwp-${prefix}-hub'
}

resource rcg 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: policy
  name: 'rcg-arveo'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-reseau-autoriser'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'web-vers-data-sql'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              webSubnet
            ]
            destinationAddresses: [
              dataSubnet
            ]
            destinationPorts: [
              '1433'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-application-autoriser'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'spokes-vers-depots-ubuntu'
            sourceAddresses: [
              spokeApp
              spokeData
            ]
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: allowedFqdns
          }
        ]
      }
    ]
  }
}
```

Contrôle, prévisualisation, déploiement :
```bash
az bicep build --file firewall-rules.bicep --stdout > /dev/null && echo "Syntaxe OK"
az deployment group what-if -g "$RG_HUB" -f firewall-rules.bicep -p numero="$NN"
az deployment group create -g "$RG_HUB" -n firewall-rules \
  -f firewall-rules.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
```
Sortie attendue du `what-if` (fin) :
```
  + Microsoft.Network/firewallPolicies/afwp-st07-hub/ruleCollectionGroups/rcg-arveo [2023-11-01]

Resource changes: 1 to create.
```
Puis `Succeeded` après 2 à 5 min (mise à jour du pare-feu associé).

Tests de la matrice :
```bash
tester() {   # tester <web|data> "<COMMANDE>" : n'affiche que la sortie standard
  az vm run-command invoke -g "$RG_SPOKE" -n "vm-${ST}-test-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
tester web  "curl -s -m 5 http://10.${OCT}.8.10:1433 || echo ECHEC"                     # a
tester data "curl -s -m 5 http://10.${OCT}.4.10 || echo ECHEC"                          # b
tester web  "curl -s -o /dev/null -w '%{http_code}' -m 10 http://azure.archive.ubuntu.com/ubuntu/"  # c
tester web  "curl -s -o /dev/null -w '%{http_code}' -m 10 http://www.example.com"       # d
tester web  "curl -s -o /dev/null -w '%{http_code}' -m 10 https://www.example.com || echo ' ECHEC'" # e
```
Sortie attendue (une ligne vide peut suivre chaque résultat) :
```
vm-st07-test-data
ECHEC
200
470
000 ECHEC
```

Explication attendue (étape 4) : en HTTP, le pare-feu lit l'en-tête `Host` en clair et répond lui-même par une page d'erreur HTTP 470 (« Action: Deny », `[À VÉRIFIER]` libellé exact). En HTTPS, il ne voit que le nom SNI de la négociation TLS ; sans inspection TLS (Premium uniquement), il ne peut pas répondre par une page HTTP et coupe la connexion : `curl` n'obtient aucun code (`000`).

### Pourquoi
- `existing` sur la stratégie : le fichier n'est propriétaire que de son groupe de collections ; aucun risque d'écraser le niveau (`Basic`) ou un autre groupe.
- Plages calculées par `int(numero)` : même fichier pour tous les stagiaires, aucune adresse saisie pour un stagiaire donné (même logique que `socle.bicep` du M3).
- Collections réseau (200) et application (300) dans un même groupe : lisibilité ; priorité 100 laissée libre pour une collection DNAT (bonus 1).
- Règle réseau pour SQL (TCP 1433 n'est pas du HTTP) ; règle d'application pour les dépôts Ubuntu (filtrage par FQDN, impossible en règle réseau au niveau Basic : pas de proxy DNS).
- Aucune règle de refus explicite : le refus implicite du pare-feu couvre la ligne « tout autre site » et le flux données → web ; une règle de refus n'aurait d'intérêt que pour la journalisation nommée.
- `*.ubuntu.com` : couvre `azure.archive.ubuntu.com` et `security.ubuntu.com` (mises à jour des VMs du M7).
- Le NSG `nsg-stNN-data` s'applique toujours après le pare-feu : le test a réussit parce que la source vue par la VM reste `10.<OCT>.4.10` (pas de SNAT pour les destinations privées) et correspond à `Allow-SQL-From-Web`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `BCP035` / `BCP037` sur `ruleCollections` | Propriété mal placée (`rules` hors de la collection, `ruleType` manquant) | Complétion de VS Code ; comparer avec la structure de la solution |
| `FirewallPolicyRuleCollectionGroupInvalidPriority` ou priorité < 100 | Priorité hors de 100 à 65000 | Priorités ≥ 100 |
| Déploiement en `Conflict` / `AnotherOperationInProgress` | Pare-feu encore en mise à jour (déploiement précédent) | Attendre 2 à 5 min, relancer |
| Test a : `ECHEC` alors que la règle existe | NSG `nsg-stNN-data` sans `Allow-SQL-From-Web`, ou ASG non attachée à la carte | IP flow verify (exercice 04.2), vérifier l'ASG de `nic-stNN-test-data` |
| Test c : `470` | FQDN mal saisi (`ubuntu.com` sans `*.`) ou source hors des plages | Vérifier `targetFqdns` et `sourceAddresses` |
| Test c : `000` (délai) | Table de routes non associée à `snet-web`, ou DNS de la VM indisponible | `show-effective-route-table` ; `tester web "getent hosts azure.archive.ubuntu.com"` |
| Test b : réponse `vm-stNN-test-web` | Règle réseau trop large (source `10.<OCT>.0.0/16` ou ports `*`) | Restreindre source, destination et port |
| `what-if` après redéploiement : `~` sur des propriétés non déclarées | Valeurs par défaut ajoutées par la plateforme | Bruit acceptable si aucune règle ne change |

### Variantes acceptables
- Règles créées avec Azure CLI (`az network firewall policy rule-collection-group create`, puis `collection add-filter-collection`, extension `azure-firewall`) : correct, mais hors de la contrainte IaC.
- Groupes d'adresses IP (`Microsoft.Network/ipGroups`) en source et destination : plus lisible à grande échelle, ressource supplémentaire.
- Étiquette FQDN `WindowsUpdate` ou liste de FQDN métier en paramètre `.bicepparam` : bonne pratique pour séparer règles et valeurs par environnement.
- Collection de refus explicite (priorité 4000) pour journaliser nommément les flux interdits : valide.

## Exercice 04.5 ⭐⭐ — Zones DNS privée et publique

### Solution
```bash
HUB_ID=$(az network vnet show -g "$RG_HUB" -n "vnet-${ST}-hub" --query id -o tsv)
APP_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" --query id -o tsv)
DATA_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-data" --query id -o tsv)

# 1. Zone privée et liens
az network private-dns zone create -g "$RG_HUB" -n arveo.internal --tags $TAGS -o none
az network private-dns link vnet create -g "$RG_HUB" -z arveo.internal \
  -n link-hub -v "$HUB_ID" --registration-enabled false --tags $TAGS -o none
az network private-dns link vnet create -g "$RG_HUB" -z arveo.internal \
  -n link-spoke-app -v "$APP_ID" --registration-enabled true --tags $TAGS -o none
az network private-dns link vnet create -g "$RG_HUB" -z arveo.internal \
  -n link-spoke-data -v "$DATA_ID" --registration-enabled true --tags $TAGS -o none

# 2. Enregistrement manuel
az network private-dns record-set a add-record -g "$RG_HUB" -z arveo.internal \
  -n sql -a "10.${OCT}.8.10" -o none

# 3. Contrôle
az network private-dns record-set list -g "$RG_HUB" -z arveo.internal \
  --query "[].{Nom:name, IP:aRecords[0].ipv4Address, Auto:isAutoRegistered}" -o table
```
Sortie attendue (étape 3, auto-enregistrement en 1 à 2 min) :
```
Nom                IP         Auto
-----------------  ---------  ------
@                             False
sql                10.7.8.10  False
vm-st07-test-data  10.7.8.10  True
vm-st07-test-web   10.7.4.10  True
```

Résolution depuis la VM web (étape 4, fonction `tester` du défi 04.4) :
```bash
tester web "getent hosts sql.arveo.internal vm-${ST}-test-data.arveo.internal; \
curl -s -m 5 http://sql.arveo.internal:1433"
```
Sortie attendue :
```
10.7.8.10       sql.arveo.internal
10.7.8.10       vm-st07-test-data.arveo.internal
vm-st07-test-data
```

Zone publique (étapes 5 et 6) :
```bash
az network dns zone create -g "$RG_HUB" -n "arveo-${ST}.fr" --tags $TAGS -o none
FW_PIP=$(az network public-ip show -g "$RG_HUB" -n "pip-${ST}-fw" --query ipAddress -o tsv)
az network dns record-set a add-record -g "$RG_HUB" -z "arveo-${ST}.fr" \
  -n www -a "$FW_PIP" -o none
NS1=$(az network dns zone show -g "$RG_HUB" -n "arveo-${ST}.fr" \
  --query "nameServers[0]" -o tsv)
echo "$NS1 / $FW_PIP"
dig +short @"$NS1" "www.arveo-${ST}.fr"
dig "www.arveo-${ST}.fr" | grep -o 'status: [A-Z]*'
```
Sortie attendue (serveurs et adresse propres à chaque zone) :
```
ns1-XX.azure-dns.com. / <IP_PUBLIQUE_FW>
<IP_PUBLIQUE_FW>
status: NXDOMAIN
```

Explication attendue (étape 7) : le serveur Azure de la zone fait autorité pour `arveo-st07.fr` et répond. Un résolveur ordinaire part de la racine puis des serveurs du `.fr` ; aucune délégation n'y pointe vers Azure (domaine ni acheté ni délégué) : la réponse est `NXDOMAIN`. Pour publier réellement, déclarer les quatre serveurs NS d'Azure chez le registraire du domaine.

### Pourquoi
- Zone dans le hub : ressource partagée, gérée une fois, liée à tous les VNets ; cohérent avec le modèle hub-spoke.
- Hub sans auto-enregistrement : aucune VM au M4 ; plus tard, un seul VNet ne peut enregistrer automatiquement que dans UNE zone.
- `sql` enregistré à la main : nom de service, indépendant du nom de la VM ; au remplacement du serveur, seul l'enregistrement change.
- Auto-enregistrement des spokes : inventaire DNS tenu à jour sans action ; l'enregistrement disparaît avec la VM.
- `.internal` : domaine de premier niveau réservé à l'usage privé, jamais délégué sur Internet, contrairement à un nom inventé en `.local` ou en `.com`.
- Résolution par `168.63.129.16` : non concernée par la route `0.0.0.0/0` vers le pare-feu (adresse de plateforme) ; aucune règle de pare-feu requise pour le DNS.
- Le test `curl http://sql.arveo.internal:1433` traverse le pare-feu : il prouve à la fois le DNS, la règle réseau du défi 04.4 et le NSG de l'exercice 04.2.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `getent hosts` ne renvoie rien | Lien manquant vers le VNet de la VM, ou lien encore en `InProgress` | `az network private-dns link vnet list ... -o table` ; attendre `Completed` |
| VMs absentes de la zone | Liens des spokes créés avec `--registration-enabled false` | `az network private-dns link vnet update ... --registration-enabled true` |
| `A virtual network can be linked to only one zone with registration` `[À VÉRIFIER]` libellé | Spoke déjà lié en auto-enregistrement à une autre zone | Désactiver l'auto-enregistrement de l'autre lien |
| `RequestDisallowedByPolicy` sur la zone ou un lien | Tags manquants (zone et liens sont des ressources taguables) | `--tags $TAGS` sur chaque création |
| `dig: command not found` | Outil absent de l'image Cloud Shell du jour | `nslookup www.arveo-<NN>.fr <SERVEUR>` |
| `dig @<SERVEUR>` : délai d'attente | Port 53 sortant filtré depuis le réseau du stagiaire (Cloud Shell non concerné) | Exécuter la commande dans Cloud Shell |
| `curl http://sql.arveo.internal:1433` : `ECHEC` alors que la résolution fonctionne | Règle réseau du défi 04.4 absente | Déployer `firewall-rules.bicep` ou le script de rattrapage |

### Variantes acceptables
- Enregistrement CNAME `sql` → `vm-stNN-test-data.arveo.internal` : valide, suit automatiquement l'adresse de la VM, mais lie le nom de service au nom de la VM.
- Enregistrement alias (`--target-resource`) pour `www` vers l'IP publique du pare-feu : recommandé en production (mis à jour si l'IP change), non pris en charge dans les zones privées.
- Zone privée par spoke : possible, mais multiplie les liens et casse la résolution croisée ; à éviter.

## Bonus

### 1. Publication DNAT
Ajouter dans `ruleCollections` de `firewall-rules.bicep`, avant les autres collections, et déclarer l'IP publique existante :
```bicep
resource pipFw 'Microsoft.Network/publicIPAddresses@2023-11-01' existing = {
  name: 'pip-${prefix}-fw'
}
```
```bicep
      {
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        name: 'rc-dnat-web'
        priority: 100
        action: {
          type: 'DNAT'
        }
        rules: [
          {
            ruleType: 'NatRule'
            name: 'web-http-8080'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              '*'
            ]
            destinationAddresses: [
              pipFw.properties.ipAddress
            ]
            destinationPorts: [
              '8080'
            ]
            translatedAddress: '10.${octet}.4.10'
            translatedPort: '80'
          }
        ]
      }
```
```bash
az deployment group create -g "$RG_HUB" -n firewall-rules \
  -f firewall-rules.bicep -p numero="$NN" --query properties.provisioningState -o tsv
curl -s -m 10 "http://${FW_PIP}:8080"
```
Sortie attendue :
```
Succeeded
vm-st07-test-web
```
Le retour de la VM web suit la route `0.0.0.0/0` vers le pare-feu (routage symétrique) ; le NSG `nsg-stNN-web` autorise le port 80 depuis toute source. Supprimer la collection (redéploiement sans elle) après le test : l'IP publique expose la VM.

### 2. Étiquette VirtualNetwork après les UDR
```bash
test_flux "10.${OCT}.5.20" 1433
```
Sortie attendue :
```
Deny securityRules/Deny-VNet-Inbound
```
Le cas b est désormais décidé par `Deny-VNet-Inbound` : l'étiquette `VirtualNetwork` inclut les préfixes des routes UDR, ici `0.0.0.0/0`, et couvre donc toute adresse `[À VÉRIFIER]` comportement constaté dans le tenant. Conséquence : `AllowVnetInBound` autoriserait aussi tout trafic arrivé par le pare-feu ; d'où l'intérêt de la règle de refus explicite.

### 3. Trafic intra-spoke
```bash
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.${OCT}.5.20" \
  --query "{Saut:nextHopType, IP:nextHopIpAddress}" -o table
```
Sortie attendue :
```
Saut       IP
---------  ----
VnetLocal
```
Le préfixe `10.<OCT>.4.0/22` (`VnetLocal`) est plus long que `0.0.0.0/0` : le trafic entre `snet-web` et `snet-app` ne passe PAS par le pare-feu ; seuls les NSG le filtrent. Pour l'y forcer, ajouter une route `10.<OCT>.5.0/24` → pare-feu dans la table de `snet-web` (et la réciproque).

## QCM — Réponses
1. **C** — 32 adresses moins 5 réservées par Azure (réseau, passerelle, deux DNS, diffusion) = 27.
2. **B** — `AzureFirewallSubnet` est imposé (/26) ; `AzureFirewallManagementSubnet` s'y ajoute pour le niveau Basic.
3. **B** — La règle de plus petite priorité est évaluée en premier et la première correspondance s'applique.
4. **A** — Toutes les cartes réseau d'un ASG doivent appartenir au même réseau virtuel.
5. **B** — Le peering n'est pas transitif : il faut une UDR vers une appliance (pare-feu) du hub.
6. **B** — Le préfixe le plus long l'emporte : `10.7.4.0/22` (VnetLocal) avant `0.0.0.0/0`.
7. **C** — Azure Firewall traite les règles DNAT, puis réseau, puis application.
8. **B** — Azure Firewall refuse par défaut tout flux sans règle correspondante.
9. **B** — Une zone privée n'est résolue que dans les VNets qui lui sont liés.
10. **B** — Sans propagation BGP, les routes VPN n'atteignent pas les spokes : le trafic reste forcé vers le pare-feu.
