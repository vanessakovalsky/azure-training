# Module 04 — Exercices

Fil rouge : construction du **réseau hub-spoke Arvéo** dans `rg-stNN-hub` et `rg-stNN-spoke`, socle de la liaison VPN avec Lyon (M5), des private endpoints (M6) et des VMs applicatives (M7).

| Ressource | Nom (stagiaire 07) | Groupe | Lab |
|---|---|---|---|
| Hub + sous-réseaux réservés + passerelle VPN | `vnet-st07-hub`, `vpngw-st07-hub` | `rg-st07-hub` | 04.1 (script) |
| Spokes applicatif et données | `vnet-st07-spoke-app`, `vnet-st07-spoke-data` | `rg-st07-spoke` | 04.1 |
| VMs de test | `vm-st07-test-web`, `vm-st07-test-data` | `rg-st07-spoke` | 04.1 (script) |
| NSG et ASG | `nsg-st07-web`, `nsg-st07-data`, `asg-st07-data` | `rg-st07-spoke` | 04.2 |
| Pare-feu, peerings, tables de routes | `afw-st07-hub`, `rt-st07-spoke-app`, `rt-st07-spoke-data` | hub / spoke | 04.3 |
| Règles du pare-feu | groupe `rcg-arveo` dans `afwp-st07-hub` | `rg-st07-hub` | 04.4 |
| Zones DNS | `arveo.internal`, `arveo-st07.fr` | `rg-st07-hub` | 04.5 |

Variables utilisées dans tous les labs :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<URL_DEPOT>` = adresse du dépôt Git de la formation, communiquée par la formatrice

Tags obligatoires sur chaque ressource (stratégie du module 2) : `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

**Bloc de variables** : à recoller dans Cloud Shell (Bash) au début de CHAQUE lab (session fermée après 20 min d'inactivité).
```bash
NN=<NN>
OCT=$((10#$NN))
ST="st${NN}"
RG_HUB="rg-${ST}-hub"
RG_SPOKE="rg-${ST}-spoke"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
cd ~/formation 2>/dev/null || git clone <URL_DEPOT> ~/formation && cd ~/formation
echo "$ST $OCT $RG_HUB $RG_SPOKE"
```
Résultat attendu (stagiaire 07) :
```
st07 7 rg-st07-hub rg-st07-spoke
```
`OCT` = numéro sans zéro en tête, seule forme valide dans une adresse IP (`10.7.0.0`, jamais `10.07.0.0`).

---

## Lab 04.1 ⭐ — Plan d'adressage et réseaux hub-spoke (guidé)
**Durée** : 30 min · **Objectif** : concevoir un plan d'adressage sans chevauchement et déployer les réseaux hub-spoke (objectif 5)
**Contexte** : Arvéo regroupe dans un hub la connectivité (VPN vers Lyon) et la sécurité (pare-feu), et isole le portail web et les données dans deux spokes. La passerelle VPN demande 30 à 45 min de provisionnement : elle est lancée en tout premier.
**Prérequis** : module 3 terminé ; Cloud Shell en Bash ; bloc de variables exécuté.

### Étapes
1. **(09:00, avant l'exposé)** Lancer le script de pré-déploiement du hub et de la passerelle VPN.
   ```bash
   ./scripts/prereq-vpn-gateways.sh "$NN"
   ```
   Résultat attendu (moins de 2 min) :
   ```
   == Réseau vnet-st07-hub (10.7.0.0/22) dans rg-st07-hub
      créé avec GatewaySubnet 10.7.0.0/27
      sous-réseau AzureFirewallSubnet 10.7.0.64/26 créé
      sous-réseau AzureFirewallManagementSubnet 10.7.0.128/26 créé
      sous-réseau AzureBastionSubnet 10.7.1.0/26 créé
      sous-réseau snet-shared 10.7.2.0/24 créé
   == IP publique pip-st07-vpngw (Standard, zones 1 2 3)
   == Passerelle vpngw-st07-hub (VpnGw1AZ, route-based)
      déploiement lancé en arrière-plan (30 à 45 min)
   Suivi : az network vnet-gateway show -g rg-st07-hub -n vpngw-st07-hub --query provisioningState -o tsv
   ```

2. Compléter sur papier le plan d'adressage de son numéro (modèle : stagiaire 07, cours S4.1).

   | Réseau ou sous-réseau | Plage du stagiaire `<NN>` | Adresses attribuables |
   |---|---|---|
   | `vnet-st<NN>-hub` | | |
   | `GatewaySubnet` | | |
   | `AzureFirewallSubnet` | | |
   | `vnet-st<NN>-spoke-app` / `snet-web` / `snet-app` | | |
   | `vnet-st<NN>-spoke-data` / `snet-data` / `snet-pe` | | |
   | Sous-réseau Lyon du stagiaire | | |

   Résultat attendu : aucune plage commune entre deux lignes de réseaux différents ; nombre d'adresses = taille du bloc − 5.

3. Inspecter le hub créé par le script.
   ```bash
   az network vnet subnet list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
     --query "[].{Nom:name, Plage:addressPrefix}" -o table
   ```
   Résultat attendu :
   ```
   Nom                            Plage
   -----------------------------  -------------
   GatewaySubnet                  10.7.0.0/27
   AzureFirewallSubnet            10.7.0.64/26
   AzureFirewallManagementSubnet  10.7.0.128/26
   AzureBastionSubnet             10.7.1.0/26
   snet-shared                    10.7.2.0/24
   ```

4. Créer le spoke applicatif avec ses deux sous-réseaux.
   ```bash
   az network vnet create -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" -l "$LOC" \
     --address-prefixes "10.${OCT}.4.0/22" \
     --subnet-name snet-web --subnet-prefixes "10.${OCT}.4.0/24" \
     --tags $TAGS -o none
   az network vnet subnet create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
     -n snet-app --address-prefixes "10.${OCT}.5.0/24" -o none
   ```
   Résultat attendu : aucune sortie, retour à l'invite en moins de 30 s.

5. Créer le spoke données avec `snet-data` (`10.<OCT>.8.0/24`) et `snet-pe` (`10.<OCT>.9.0/24`, private endpoints du M6).
   ```bash
   az network vnet create -g "$RG_SPOKE" -n "vnet-${ST}-spoke-data" -l "$LOC" \
     --address-prefixes "10.${OCT}.8.0/22" \
     --subnet-name snet-data --subnet-prefixes "10.${OCT}.8.0/24" \
     --tags $TAGS -o none
   az network vnet subnet create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
     -n snet-pe --address-prefixes "10.${OCT}.9.0/24" -o none
   ```

6. Vérifier les trois espaces d'adressage.
   ```bash
   az network vnet list \
     --query "[?starts_with(name, 'vnet-${ST}-')].{Nom:name, Plage:addressSpace.addressPrefixes[0], Region:location}" \
     -o table
   ```
   Résultat attendu :
   ```
   Nom                   Plage        Region
   --------------------  -----------  -------------
   vnet-st07-hub         10.7.0.0/22  francecentral
   vnet-st07-spoke-app   10.7.4.0/22  francecentral
   vnet-st07-spoke-data  10.7.8.0/22  francecentral
   ```

7. Constater les adresses réservées : `.3` est réservée, `.10` est libre.
   ```bash
   az network vnet check-ip-address -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" \
     --ip-address "10.${OCT}.4.3" --query available
   az network vnet check-ip-address -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" \
     --ip-address "10.${OCT}.4.10" --query available
   ```
   Résultat attendu :
   ```
   false
   true
   ```

8. Créer une IP publique Standard de test, l'examiner, puis la supprimer.
   ```bash
   az network public-ip create -g "$RG_SPOKE" -n "pip-${ST}-test" -l "$LOC" \
     --sku Standard --allocation-method Static --zone 1 2 3 --tags $TAGS -o none
   az network public-ip show -g "$RG_SPOKE" -n "pip-${ST}-test" \
     --query "{IP:ipAddress, SKU:sku.name, Attribution:publicIPAllocationMethod, Zones:join(',', zones)}" \
     -o table
   az network public-ip delete -g "$RG_SPOKE" -n "pip-${ST}-test"
   ```
   Résultat attendu (adresse propre à chaque stagiaire) :
   ```
   IP               SKU       Attribution    Zones
   ---------------  --------  -------------  -------
   <IP_ATTRIBUEE>   Standard  Static         1,2,3
   ```

9. Lancer la création des deux VMs de test (utilisées en S4.2, S4.3 et S4.4).
   ```bash
   ./scripts/labs/module-04/test-vms.sh "$NN"
   ```
   Résultat attendu :
   ```
   Carte nic-st07-test-web créée (10.7.4.10)
   VM vm-st07-test-web : création lancée en arrière-plan (2 à 4 min)
   Carte nic-st07-test-data créée (10.7.8.10)
   VM vm-st07-test-data : création lancée en arrière-plan (2 à 4 min)
   ```

10. Suivre la passerelle VPN.
    ```bash
    az network vnet-gateway show -g "$RG_HUB" -n "vpngw-${ST}-hub" --query provisioningState -o tsv
    ```
    Résultat attendu : `Updating` (déploiement en cours), puis `Succeeded` vers 09:45.

### Critères de réussite
- [ ] Tableau d'adressage complété, sans chevauchement.
- [ ] `az network vnet list` (étape 6) affiche trois VNets en `/22` consécutifs.
- [ ] `az network vnet subnet list -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-data -o table` affiche `snet-data` et `snet-pe`.
- [ ] `az vm list -g rg-st<NN>-spoke -d --query "[].{Nom:name, IP:privateIps}" -o table` affiche les deux VMs en `.4.10` et `.8.10`.

---

## Exercice 04.2 ⭐⭐ — Filtrer avec NSG et ASG (semi-autonome)
**Durée** : 30 min · **Objectif** : filtrer les flux avec NSG et ASG, puis vérifier les règles effectives (objectif 5)
**Contexte** : la future base de données d'Arvéo (spoke données) ne doit accepter que le trafic SQL issu du sous-réseau web. Le sous-réseau web recevra le trafic HTTP/HTTPS d'un équilibreur de charge (M7). La DSI exige des règles lisibles, nommées par rôle plutôt que par adresse.
**Prérequis** : Lab 04.1 terminé, VMs de test à l'état `VM running`.

**Énoncé** :
1. Créer `nsg-st<NN>-web` et l'associer à `snet-web` avec une règle entrante `Allow-HTTP-HTTPS-Inbound` (TCP 80 et 443, toute source, priorité 100).
2. Créer le groupe de sécurité d'application `asg-st<NN>-data` et y placer la carte réseau `nic-st<NN>-test-data`.
3. Créer `nsg-st<NN>-data`, l'associer à `snet-data`, avec deux règles entrantes :
   - `Allow-SQL-From-Web` (priorité 100) : TCP 1433 depuis `snet-web` vers `asg-st<NN>-data` ;
   - `Deny-VNet-Inbound` (priorité 4000) : tout trafic depuis l'étiquette `VirtualNetwork` refusé.
4. Afficher les règles entrantes effectives de la carte `nic-st<NN>-test-data` (nom, priorité, action).
5. Avec IP flow verify, tester les quatre flux entrants vers `10.<OCT>.8.10` et noter la règle décisive de chacun :

   | Cas | Source | Port de destination |
   |---|---|---|
   | a | `10.<OCT>.4.10` (snet-web) | 1433 |
   | b | `10.<OCT>.5.20` (snet-app) | 1433 |
   | c | `10.<OCT>.4.10` (snet-web) | 22 |
   | d | `10.<OCT>.9.20` (snet-pe, même VNet) | 1433 |

6. Expliquer par écrit pourquoi les cas b et c ne sont PAS décidés par `Deny-VNet-Inbound`, alors que le cas d l'est.

**Indices** :
- `az network asg create`, `az network nic ip-config update --application-security-groups` (configuration IP `ipconfig1`).
- `az network nsg rule create --help` : `--source-address-prefixes`, `--destination-asgs`, `--destination-port-ranges`.
- Règles effectives : `az network nic list-effective-nsg` (VM démarrée obligatoire) ; filtrer `effectiveSecurityRules` sur `direction`.
- IP flow verify : `az network watcher test-ip-flow --vm ... --local <IP>:<PORT> --remote <IP>:<PORT>`.
- Cas b et c : comparer le contenu de l'étiquette `VirtualNetwork` (cours S4.2) avec la topologie actuelle (aucun peering).

**Critères de réussite** :
- [ ] `az network vnet subnet show -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-data -n snet-data --query networkSecurityGroup.id -o tsv` se termine par `nsg-st<NN>-data`.
- [ ] `az network nic show -g rg-st<NN>-spoke -n nic-st<NN>-test-data --query "ipConfigurations[0].applicationSecurityGroups[0].id" -o tsv` se termine par `asg-st<NN>-data`.
- [ ] Cas a : `Allow` par `Allow-SQL-From-Web` ; cas d : `Deny` par `Deny-VNet-Inbound`.
- [ ] Explication des cas b et c rédigée (étiquette `VirtualNetwork` sans peering).

---

## Exercice 04.3 ⭐⭐ — Pare-feu, peerings et routes (semi-autonome)
**Durée** : 20 min (dont 3 min AVANT l'exposé S4.3) · **Objectif** : forcer le trafic inter-spokes et sortant à travers Azure Firewall par des routes UDR (objectif 5)
**Contexte** : la DSI d'Arvéo veut un point de contrôle unique pour les flux entre spokes et vers Internet. Le pare-feu est décrit par un fichier Bicep validé par l'équipe réseau ; il reste à le déployer, à relier les spokes au hub et à y diriger le trafic.
**Prérequis** : exercice 04.2 terminé ; passerelle VPN `Succeeded` (sinon, peering côté hub refusé tant que la passerelle est en cours de mise à jour).

**Énoncé** :
1. **(Avant l'exposé)** Lire `scripts/labs/module-04/firewall.bicep`, puis lancer son déploiement dans `rg-st<NN>-hub` sous le nom `firewall`, sans attendre la fin :
   ```bash
   az deployment group create -g "$RG_HUB" -n firewall \
     -f scripts/labs/module-04/firewall.bicep -p numero="$NN" --no-wait
   ```
   Questions de lecture : quelles ressources sont créées ? Pourquoi deux IP publiques ? Quel sous-réseau porte chaque configuration IP ? Que filtre la stratégie à sa création ?
2. Créer les quatre liens de peering (hub ↔ spoke app, hub ↔ spoke données), trafic relayé autorisé des deux côtés ; noms : `peer-hub-to-spoke-app`, `peer-spoke-app-to-hub`, `peer-hub-to-spoke-data`, `peer-spoke-data-to-hub`.
3. Depuis `vm-st<NN>-test-web`, tester `http://10.<OCT>.8.10:1433` : constater l'échec et l'expliquer.
4. Attendre la fin du déploiement du pare-feu et récupérer son IP privée dans la variable `FW_IP`.
5. Créer `rt-st<NN>-spoke-app` (associée à `snet-web` et `snet-app`) et `rt-st<NN>-spoke-data` (associée à `snet-data`) : propagation BGP désactivée, route `default-via-fw` `0.0.0.0/0` → `VirtualAppliance` `$FW_IP`.
6. Afficher les routes effectives de `nic-st<NN>-test-web`, puis le saut suivant de `10.<OCT>.4.10` vers `10.<OCT>.8.10`.
7. Refaire le test de l'étape 3 : l'échec persiste. Expliquer en quoi sa cause diffère de celle de l'étape 3.

**Indices** :
- ID d'un VNet : `az network vnet show -g <GROUPE> -n <VNET> --query id -o tsv` (le VNet distant est dans un autre groupe).
- Peering : `az network vnet peering create --remote-vnet <ID> --allow-vnet-access --allow-forwarded-traffic` ; état : `peeringState`.
- Test depuis une VM sans IP publique : `az vm run-command invoke --command-id RunShellScript --scripts "<COMMANDE>" --query "value[0].message" -o tsv` (30 à 60 s par appel).
- Commande de test : `curl -s -m 5 http://<IP>:<PORT> || echo ECHEC`.
- Attente : `az deployment group wait --created`, puis sortie `firewallPrivateIp` du déploiement.
- Saut suivant : `az network watcher show-next-hop`.

**Critères de réussite** :
- [ ] `az network vnet peering list -g rg-st<NN>-hub --vnet-name vnet-st<NN>-hub --query "[].peeringState" -o tsv` affiche deux fois `Connected`.
- [ ] `az network firewall show -g rg-st<NN>-hub -n afw-st<NN>-hub --query provisioningState -o tsv` renvoie `Succeeded` (ou `az resource show` équivalent).
- [ ] Routes effectives de `nic-st<NN>-test-web` : `0.0.0.0/0` → `VirtualAppliance` `$FW_IP`, source `User`.
- [ ] `show-next-hop` renvoie `VirtualAppliance` et l'IP du pare-feu.
- [ ] Les deux causes d'échec (étapes 3 et 7) sont expliquées.

---

## Défi 04.4 ⭐⭐⭐ — Règles du pare-feu sous IaC (autonome)
**Durée** : 20 min · **Objectif** : définir la politique de filtrage du hub en Bicep et vérifier les flux autorisés et bloqués (objectif 5)
**Contexte** : la matrice de flux d'Arvéo est validée par la DSI. Elle doit être appliquée par un fichier versionné, rejouable sur chaque environnement, et prouvée par des tests reproductibles.

**Matrice de flux** :

| Source | Destination | Protocole / port | Décision |
|---|---|---|---|
| `snet-web` | `snet-data` | TCP 1433 | Autoriser |
| `snet-data` | `snet-web` | Tout | Refuser |
| Spokes app et données | Dépôts Ubuntu `*.ubuntu.com` | HTTP 80, HTTPS 443 | Autoriser |
| Spokes app et données | Tout autre site Internet | Tout | Refuser |

**Énoncé** :
1. Écrire `firewall-rules.bicep` qui ajoute le groupe de collections `rcg-arveo` à la stratégie EXISTANTE `afwp-st<NN>-hub`.
2. Contraintes :
   - un seul paramètre obligatoire : le numéro de stagiaire ;
   - plages calculées à partir du numéro, aucune adresse saisie en dur pour un stagiaire donné ;
   - liste des FQDN autorisés fournie en paramètre avec `*.ubuntu.com` par défaut ;
   - stratégie référencée, jamais redéclarée.
3. Prévisualiser avec `what-if`, déployer, puis prouver la matrice par cinq tests exécutés sur les VMs de test :
   - a. web → `http://10.<OCT>.8.10:1433` : réponse `vm-st<NN>-test-data` ;
   - b. données → `http://10.<OCT>.4.10` : échec ;
   - c. web → `http://azure.archive.ubuntu.com/ubuntu/` : code HTTP `200` ;
   - d. web → `http://www.example.com` : code HTTP `470` (refus du pare-feu) ;
   - e. web → `https://www.example.com` : échec.
4. Expliquer pourquoi le test d renvoie une réponse HTTP alors que le test e échoue sans réponse.

**Critères de réussite** :
- [ ] `az bicep build --file firewall-rules.bicep` ne produit aucune erreur.
- [ ] `az network firewall policy rule-collection-group show -g rg-st<NN>-hub --policy-name afwp-st<NN>-hub -n rcg-arveo --query provisioningState -o tsv` renvoie `Succeeded` (ou `az resource show` équivalent).
- [ ] Les cinq tests donnent le résultat attendu.
- [ ] Redéploiement du fichier : `what-if` sans aucun changement.

---

## Exercice 04.5 ⭐⭐ — Zones DNS privée et publique (semi-autonome)
**Durée** : 30 min · **Objectif** : résoudre des noms avec des zones Azure DNS publiques et privées (objectif 5)
**Contexte** : les applications d'Arvéo doivent joindre la base de données par un nom stable, indépendant de l'adresse du serveur. Le futur site public sera publié derrière le pare-feu.
**Prérequis** : défi 04.4 terminé (ou script de rattrapage), VMs de test démarrées.

**Énoncé** :
1. Créer la zone privée `arveo.internal` dans `rg-st<NN>-hub` et trois liens de réseau virtuel :
   - `link-hub` vers `vnet-st<NN>-hub`, sans auto-enregistrement ;
   - `link-spoke-app` et `link-spoke-data` vers les spokes, avec auto-enregistrement.
2. Ajouter l'enregistrement A `sql` → `10.<OCT>.8.10`.
3. Lister les enregistrements de la zone : les deux VMs de test doivent y apparaître sans action manuelle.
4. Depuis `vm-st<NN>-test-web` :
   - résoudre `sql.arveo.internal` et `vm-st<NN>-test-data.arveo.internal` ;
   - interroger `http://sql.arveo.internal:1433`.
5. Créer la zone publique `arveo-st<NN>.fr` dans `rg-st<NN>-hub` et l'enregistrement A `www` → IP publique `pip-st<NN>-fw`.
6. Depuis Cloud Shell, interroger `www.arveo-st<NN>.fr` directement sur le premier serveur de noms de la zone, puis sur un résolveur public.
7. Expliquer les deux résultats de l'étape 6.

**Indices** :
- `az network private-dns zone create`, `az network private-dns link vnet create` (`--registration-enabled` obligatoire), `az network private-dns record-set a add-record`.
- Résolution sur la VM : `getent hosts <NOM>` dans `az vm run-command invoke`.
- Zone publique : `az network dns zone create`, `az network dns record-set a add-record` ; serveurs : propriété `nameServers` de la zone.
- Requête ciblée : `dig +short @<SERVEUR> <NOM>` (ou `nslookup <NOM> <SERVEUR>`).

**Critères de réussite** :
- [ ] `az network private-dns link vnet list -g rg-st<NN>-hub -z arveo.internal --query "[].{Nom:name, Auto:registrationEnabled, Etat:virtualNetworkLinkState}" -o table` affiche trois liens `Completed`, dont deux avec `True`.
- [ ] La liste des enregistrements contient `sql`, `vm-st<NN>-test-web` et `vm-st<NN>-test-data`.
- [ ] Depuis la VM web, `curl http://sql.arveo.internal:1433` renvoie `vm-st<NN>-test-data`.
- [ ] `dig` sur le serveur Azure renvoie l'IP de `pip-st<NN>-fw` ; l'explication de l'étape 7 est rédigée.

---

## Bonus 🚀
1. **Publication DNAT** : ajouter à `firewall-rules.bicep` une collection DNAT qui publie le port 80 de `vm-st<NN>-test-web` sur le port 8080 de l'IP publique du pare-feu ; tester depuis Cloud Shell `curl http://<IP_PUBLIQUE_FW>:8080`.
2. **Étiquette VirtualNetwork** : rejouer le cas b de l'exercice 04.2 (IP flow verify, `10.<OCT>.5.20` → `10.<OCT>.8.10:1433`) après la mise en place des UDR. Comparer la règle décisive et l'expliquer.
3. **Contrôle croisé** : depuis `vm-st<NN>-test-web`, tester `http://10.<OCT>.5.20` (adresse libre de `snet-app`) puis lire le saut suivant avec `show-next-hop` : le trafic intra-spoke passe-t-il par le pare-feu ?

## Nettoyage
- Fin de matinée : rien à supprimer, tout est réutilisé au module 5 (après-midi).
- **Fin du jour 2** (après le module 5) : `./scripts/cleanup/module-04-firewall.sh <NN>` supprime le pare-feu et ses deux IP publiques, dissocie les tables de routes et arrête les VMs de test. Stratégie, règles, tables de routes, NSG et zones DNS sont conservés.
- Recréation ultérieure si besoin : `./scripts/catch-up/module-04/deploy.sh <NN>`.
- Coûts : Azure Firewall Basic, IP publiques Standard et VMs B2s_v2 facturés à l'heure `[À VÉRIFIER]` calculatrice de prix Azure ; zones DNS et NSG : coût négligeable ou nul.
