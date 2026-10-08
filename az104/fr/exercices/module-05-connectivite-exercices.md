# Module 05 — Exercices

Fil rouge : **liaison du réseau Arvéo avec le site de Lyon**. Le hub reçoit le rôle de point d'entrée unique : sa passerelle VPN est partagée avec les spokes (transit), un tunnel IPsec le relie au datacenter de Lyon, et tout flux Lyon ↔ spokes traverse le pare-feu. Un spoke de reprise d'activité (PRA) est préparé en West Europe. Le serveur de fichiers de Lyon créé ici est repris au module 6 (Azure File Sync).

| Ressource | Nom (stagiaire 07) | Groupe | Lab |
|---|---|---|---|
| Transit de passerelle | options des liens `peer-hub-to-spoke-*`, `peer-spoke-*-to-hub` | hub / spoke | 05.1 |
| Spoke PRA (West Europe) | `vnet-st07-spoke-pra`, liens `peer-hub-to-spoke-pra`, `peer-spoke-pra-to-hub` | `rg-st07-spoke` / `rg-st07-hub` | 05.1 |
| Serveur de Lyon | `vm-st07-lyon-fs` (`10.200.7.10`), carte `nic-st07-lyon-fs` | `rg-st07-lyon` | 05.2 (script) |
| Passerelle locale et connexion | `lng-st07-lyon`, `cn-st07-hub-to-lyon` | `rg-st07-hub` | 05.2 |
| Routage et filtrage hybrides | `rt-st07-gateway`, groupe `rcg-lyon`, règle `Allow-SQL-From-Lyon` | hub / spoke | 05.3 |

Côté Lyon (formatrice, lecture seule pour les stagiaires) : `vnet-lyon` (`10.200.0.0/16`), sous-réseau `snet-st07` (`10.200.7.0/24`), passerelle `vpngw-lyon`, passerelle locale `lng-lyon-st07` et connexion `cn-lyon-to-st07`, dans `rg-formation-lyon`.

Variables utilisées dans tous les labs :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<URL_DEPOT>` = adresse du dépôt Git de la formation, communiquée par la formatrice
- `<CLE_PARTAGEE>` = clé partagée du tunnel, transmise par la formatrice au lab 05.2

Tags obligatoires sur chaque ressource (stratégie du module 2) : `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

**Bloc de variables** : à recoller dans Cloud Shell (Bash) au début de CHAQUE lab (session fermée après 20 min d'inactivité).
```bash
NN=<NN>
OCT=$((10#$NN))
ST="st${NN}"
RG_HUB="rg-${ST}-hub"
RG_SPOKE="rg-${ST}-spoke"
RG_LYON_ST="rg-${ST}-lyon"
RG_LYON="rg-formation-lyon"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
cd ~/formation 2>/dev/null || git clone <URL_DEPOT> ~/formation && cd ~/formation
tester() {   # tester <web|data> "<COMMANDE BASH>" : exécution sur vm-stNN-test-<web|data>
  az vm run-command invoke -g "$RG_SPOKE" -n "vm-${ST}-test-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
lyon() {     # lyon "<COMMANDE POWERSHELL>" : exécution sur vm-stNN-lyon-fs
  az vm run-command invoke -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" \
    --command-id RunPowerShellScript --scripts "$1" \
    --query "value[0].message" -o tsv
}
echo "$ST $OCT $RG_HUB $RG_SPOKE $RG_LYON_ST"
```
Résultat attendu (stagiaire 07) :
```
st07 7 rg-st07-hub rg-st07-spoke rg-st07-lyon
```

**État de départ** : fin du module 4 (hub, passerelle `vpngw-st<NN>-hub` en `Succeeded`, spokes appairés au hub, pare-feu `afw-st<NN>-hub` et ses règles, tables de routes des spokes, VMs de test démarrées). Stagiaire en retard : `./scripts/catch-up/module-04/deploy.sh <NN>` (10 à 20 min) pendant l'exposé S5.1.

---

## Lab 05.1 ⭐⭐ — Transit de passerelle et peering global (semi-autonome)
**Durée** : 40 min · **Objectif** : configurer le transit de passerelle et un peering global, puis vérifier leur état (objectif 6)
**Contexte** : Arvéo ne paiera qu'une passerelle VPN, celle du hub ; les spokes doivent l'utiliser pour joindre Lyon. La DSI prépare aussi un plan de reprise d'activité en West Europe : un spoke PRA, vide pour l'instant, doit être relié au hub de France Central et profiter du même accès à Lyon. Une seconde plage d'adresses lui sera ajoutée en cours de projet.
**Prérequis** : module 4 terminé (ou rattrapage), bloc de variables exécuté.

**Énoncé** :
1. Vérifier que `vpngw-st<NN>-hub` est en `Succeeded`, puis lister les liens de peering du hub avec leur état et leurs quatre options.
2. Activer le transit de passerelle sur les liens existants : `allowGatewayTransit` sur `peer-hub-to-spoke-app` et `peer-hub-to-spoke-data`, puis `useRemoteGateways` sur `peer-spoke-app-to-hub` et `peer-spoke-data-to-hub`.
3. Créer `vnet-st<NN>-spoke-pra` dans `rg-st<NN>-spoke`, région **West Europe**, plage `10.<OCT>.12.0/23`, sous-réseau `snet-pra` (`10.<OCT>.12.0/24`), tags obligatoires.
4. Créer le peering global hub ↔ PRA : `peer-hub-to-spoke-pra` (accès, trafic relayé, transit de passerelle) puis `peer-spoke-pra-to-hub` (accès, trafic relayé, passerelle distante).
5. Afficher, pour les trois liens du hub : nom, état, niveau de synchronisation, transit de passerelle ; pour les trois liens des spokes : nom et `useRemoteGateways`.
6. Ajouter la plage `10.<OCT>.14.0/23` au spoke PRA. Relever le niveau de synchronisation des liens du hub, synchroniser le lien concerné, puis vérifier.
7. Avec le saut suivant de Network Watcher, déterminer par où partirait un paquet de `vm-st<NN>-test-web` vers `10.<OCT>.12.4` (adresse du spoke PRA).
8. Répondre par écrit :
   - a. Pourquoi l'ordre « hub d'abord, spoke ensuite » est-il imposé à l'étape 2 ?
   - b. Le spoke app joint-il directement le spoke PRA grâce au peering global ? Que montre l'étape 7 ?
   - c. Pourquoi le spoke PRA n'a-t-il pas besoin de sa propre passerelle pour joindre Lyon ?

**Indices** :
- État de la passerelle : `az network vnet-gateway show ... --query provisioningState -o tsv`.
- Mise à jour d'un lien existant : `az network vnet peering update ... --set allowGatewayTransit=true` (ou `useRemoteGateways=true`).
- Création d'un lien avec options : `az network vnet peering create --allow-vnet-access --allow-forwarded-traffic --allow-gateway-transit` (lien du hub) ou `--use-remote-gateways` (lien du spoke). ID du VNet distant : `az network vnet show ... --query id -o tsv`.
- Projection JMESPath : `--query "[].{Nom:name, Etat:peeringState, Sync:peeringSyncLevel, Transit:allowGatewayTransit}" -o table`.
- Plage supplémentaire : `az network vnet update --address-prefixes <PLAGE1> <PLAGE2>` (liste complète) ; synchronisation : `az network vnet peering sync`.
- Saut suivant : `az network watcher show-next-hop -g <GROUPE_VM> --vm <VM> --source-ip <IP> --dest-ip <IP>`.

**Critères de réussite** :
- [ ] `az network vnet peering list -g rg-st<NN>-hub --vnet-name vnet-st<NN>-hub --query "[].[name, peeringState, peeringSyncLevel, allowGatewayTransit]" -o tsv` affiche trois liens `Connected`, `FullyInSync`, `True`.
- [ ] Les trois liens `peer-spoke-*-to-hub` ont `useRemoteGateways` à `true`.
- [ ] `az network vnet show -g rg-st<NN>-spoke -n vnet-st<NN>-spoke-pra --query "[location, addressSpace.addressPrefixes]" -o tsv` affiche `westeurope` et les deux plages.
- [ ] Les trois réponses de l'étape 8 sont rédigées.

---

## Lab 05.2 ⭐⭐ — Tunnel VPN site-à-site vers Lyon (semi-autonome)
**Durée** : 25 min (dont 2 min AVANT l'exposé S5.2) · **Objectif** : établir un tunnel VPN site-à-site entre le hub et le site de Lyon simulé (objectif 6)
**Contexte** : l'équipe réseau de Lyon a configuré son côté du tunnel (`lng-lyon-st<NN>`, `cn-lyon-to-st<NN>`) et transmis la clé partagée. Il reste à déclarer Lyon dans Azure, à monter le tunnel et à vérifier qu'un serveur de Lyon voit le réseau Arvéo.
**Prérequis** : lab 05.1 terminé ; clé partagée `<CLE_PARTAGEE>` reçue.

**Énoncé** :
1. **(14:30, avant l'exposé)** Lancer la création du serveur de fichiers de Lyon :
   ```bash
   ./scripts/labs/module-05/lyon-vm.sh "$NN"
   ```
   Résultat attendu :
   ```
   Carte nic-st07-lyon-fs créée (10.200.7.10)
   VM vm-st07-lyon-fs : création lancée en arrière-plan (5 à 10 min)
   Mot de passe administrateur (arveoadmin) : /home/<UTILISATEUR>/.arveo/lyon-fs-admin.txt
   Suivi : az vm list -g rg-st07-lyon -d --query "[].{Nom:name, Etat:powerState, IP:privateIps}" -o table
   ```
2. Relever l'IP publique de `vpngw-lyon` (`pip-lyon-vpngw`, groupe `rg-formation-lyon`) et celle de sa propre passerelle (`pip-st<NN>-vpngw`). Lire la passerelle locale `lng-lyon-st<NN>` créée par la formatrice : quelle IP et quelle plage déclare-t-elle ? Pourquoi un `/20` ?
3. Créer la passerelle de réseau local `lng-st<NN>-lyon` (France Central) : IP de `vpngw-lyon`, plage `10.200.<OCT>.0/24`.
4. Créer la connexion `cn-st<NN>-hub-to-lyon` de type IPsec entre `vpngw-st<NN>-hub` et `lng-st<NN>-lyon`, avec la clé partagée reçue.
5. Suivre l'état de la connexion jusqu'à `Connected` (1 à 5 min), puis relever les compteurs d'octets entrants et sortants.
6. Afficher les routes effectives de `nic-st<NN>-lyon-fs` dont le saut suivant est `VirtualNetworkGateway`.
7. Depuis `vm-st<NN>-lyon-fs`, interroger `http://10.<OCT>.4.10` (serveur web de test du spoke app) : constater l'échec.
8. Déterminer le saut suivant de `vm-st<NN>-lyon-fs` vers `10.<OCT>.4.10`, puis celui de `vm-st<NN>-test-web` vers `10.200.<OCT>.10`.
9. Expliquer l'échec de l'étape 7 en suivant le paquet aller puis la réponse.

**Indices** :
- IP publique : `az network public-ip show -g <GROUPE> -n <NOM> --query ipAddress -o tsv` (lecture autorisée sur tout l'abonnement).
- Passerelle locale : `az network local-gateway show` (lecture) et `az network local-gateway create --gateway-ip-address --local-address-prefixes`.
- Connexion : `az network vpn-connection create --vnet-gateway1 <PASSERELLE> --local-gateway2 <LNG> --shared-key <CLE>` ; ne jamais coller la clé dans un fichier versionné.
- État : propriétés `connectionStatus`, `ingressBytesTransferred`, `egressBytesTransferred` de `az network vpn-connection show`.
- Routes effectives : `az network nic show-effective-route-table` (VM démarrée).
- Test depuis Lyon : `lyon "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://<IP>).Content.Trim() } catch { 'ECHEC' }"` (30 à 60 s).
- Saut suivant d'une VM de West Europe : Network Watcher de West Europe, même commande `show-next-hop`.
- Étape 9 : routes de `GatewaySubnet` (aucune UDR à ce stade) et route `0.0.0.0/0` de `snet-web` (module 4).

**Critères de réussite** :
- [ ] `az network vpn-connection show -g rg-st<NN>-hub -n cn-st<NN>-hub-to-lyon --query connectionStatus -o tsv` renvoie `Connected`.
- [ ] Les routes effectives de `nic-st<NN>-lyon-fs` contiennent `10.<OCT>.0.0/20` vers `VirtualNetworkGateway`.
- [ ] Les deux sauts suivants de l'étape 8 sont relevés (`VirtualNetworkGateway`, `VirtualAppliance`).
- [ ] L'explication de l'étape 9 nomme le chemin aller, le chemin retour et la raison du rejet.

---

## Défi 05.3 ⭐⭐⭐ — Flux hybrides Lyon ↔ Arvéo sous IaC (autonome)
**Durée** : 50 min · **Objectif** : router le trafic hybride à travers le pare-feu et prouver les flux autorisés et bloqués (objectif 6)
**Contexte** : la DSI valide la matrice de flux entre le site de Lyon et Azure pendant la période de migration. Les applications de Lyon doivent joindre le portail web et la base de données d'Azure ; aucun flux ne doit partir d'Azure vers Lyon. La configuration doit être versionnée et rejouable, au même titre que les règles du module 4.

**Matrice de flux** :

| Source | Destination | Protocole / port | Décision |
|---|---|---|---|
| Lyon `10.200.<OCT>.0/24` | `snet-web` | TCP 80, 443 | Autoriser |
| Lyon `10.200.<OCT>.0/24` | `snet-data` | TCP 1433 | Autoriser |
| Lyon `10.200.<OCT>.0/24` | Tout autre port ou réseau Arvéo | Tout | Refuser |
| Spokes app et données | Lyon | Tout | Refuser |

**Énoncé** :
1. Écrire `lyon-connectivity.bicep`, déployé dans `rg-st<NN>-hub`, qui :
   - crée la table de routes `rt-st<NN>-gateway` (routes vers les deux spokes par le pare-feu) et l'associe à `GatewaySubnet` ;
   - ajoute le groupe de collections `rcg-lyon` (priorité 300) à la stratégie EXISTANTE `afwp-st<NN>-hub` ;
   - ajoute au NSG existant `nsg-st<NN>-data` la règle `Allow-SQL-From-Lyon` (priorité 110), par un module.
2. Contraintes :
   - un seul paramètre obligatoire : le numéro de stagiaire ;
   - IP privée du pare-feu LUE sur la ressource existante, jamais saisie ;
   - plages calculées à partir du numéro ;
   - ressources existantes référencées (`existing`), jamais redéclarées, à l'exception de `GatewaySubnet`.
3. Prévisualiser avec `what-if`, déployer, puis prouver la matrice par cinq tests :
   - a. Lyon → `http://10.<OCT>.4.10` : réponse `vm-st<NN>-test-web` ;
   - b. Lyon → `http://10.<OCT>.8.10:1433` : réponse `vm-st<NN>-test-data` ;
   - c. Lyon → `http://10.<OCT>.8.10` (port 80) : échec ;
   - d. `vm-st<NN>-test-web` → `10.200.<OCT>.10`, port 3389 : échec ;
   - e. saut suivant de `vm-st<NN>-lyon-fs` vers `10.<OCT>.8.10` et de `vm-st<NN>-test-data` vers `10.200.<OCT>.10`.
4. Répondre par écrit :
   - a. Pourquoi le test b échouerait-il encore avec la seule règle du pare-feu ?
   - b. Pourquoi `rt-st<NN>-gateway` ne contient-elle ni route `0.0.0.0/0` ni route vers le hub ?
   - c. Que deviendrait le tunnel si la propagation des routes de passerelle était désactivée sur cette table ?

**Critères de réussite** :
- [ ] `az bicep build --file lyon-connectivity.bicep` ne produit aucune erreur.
- [ ] `az network vnet subnet show -g rg-st<NN>-hub --vnet-name vnet-st<NN>-hub -n GatewaySubnet --query routeTable.id -o tsv` se termine par `rt-st<NN>-gateway`.
- [ ] Les cinq tests donnent le résultat attendu.
- [ ] Redéploiement du fichier : `what-if` sans aucun changement de règle ni de route.
- [ ] Les trois réponses de l'étape 4 sont rédigées.

---

## Étude de cas 05.4 — Choisir la connectivité hybride (collectif)
**Durée** : 5 min · **Objectif** : justifier le choix VPN, ExpressRoute ou Virtual WAN pour un besoin donné (objectif 6)
**Contexte** : le comité de direction d'Arvéo demande une recommandation pour trois besoins à venir.

**Énoncé** : pour chaque besoin, nommer la solution, donner deux arguments et un risque.
1. **Migration du datacenter de Lyon** : 40 To de données à transférer en 3 mois ; l'ERP restera 18 mois en production hybride (base à Lyon, serveurs applicatifs dans Azure) avec une latence garantie exigée par l'éditeur.
2. **Réseau des agences** : 14 agences régionales (box fibre, aucune équipe informatique locale) et 60 commerciaux nomades doivent accéder aux applications Azure ; les agences doivent aussi joindre Lyon.
3. **Après la fermeture de Lyon (fin 2027)** : plus aucun serveur sur site, budget réseau réduit de moitié, seuls les postes du siège (200 utilisateurs, Internet professionnel) accèdent aux applications.

**Critères de réussite** :
- [ ] Une solution argumentée par besoin, avec au moins un critère chiffré (débit, délai, nombre de sites ou coût).
- [ ] Un risque ou une limite identifié pour chaque solution.

---

## Bonus 🚀
1. **Résolution DNS depuis Lyon** : depuis `vm-st<NN>-lyon-fs`, résoudre `sql.arveo.internal` (`Resolve-DnsName`). Expliquer le résultat et proposer, sans le déployer, l'architecture qui permettrait cette résolution (cours S4.4).
2. **PRA joignable depuis Lyon** : compléter `lyon-connectivity.bicep` pour que le flux Lyon → `snet-pra` (TCP 443) traverse le pare-feu, puis vérifier par `show-next-hop` depuis `vm-st<NN>-lyon-fs` vers `10.<OCT>.12.4`. Quelles ressources faut-il en plus côté PRA pour un routage symétrique, et dans quelle région ?
3. **Stratégie IPsec effective** : lister la stratégie IPsec/IKE personnalisée de `cn-st<NN>-hub-to-lyon` (`az network vpn-connection ipsec-policy list`). Interpréter un résultat vide, puis expliquer pourquoi imposer une stratégie d'un seul côté du tunnel peut l'empêcher de s'établir.

## Nettoyage
- **Fin du jour 2 (16:55)**, dans cet ordre, en arrière-plan si possible :
  ```bash
  ./scripts/cleanup/module-05-vpn.sh "$NN"
  ./scripts/cleanup/module-04-firewall.sh "$NN"
  ```
  `module-05-vpn.sh` supprime la connexion, la passerelle locale, la passerelle VPN (10 à 20 min) et son IP publique, désactive le transit de passerelle et arrête `vm-st<NN>-lyon-fs`. Relançable sans risque si la session Cloud Shell se ferme pendant la suppression.
- Conservés : VNets (dont le spoke PRA), peerings, `rt-st<NN>-gateway`, groupe `rcg-lyon`, règle `Allow-SQL-From-Lyon`, serveur de Lyon arrêté (repris au module 6).
- Côté Lyon : la formatrice supprime connexions, passerelles locales et `vpngw-lyon` (`lyon-site.sh cleanup`).
- Recréation ultérieure si besoin : `./scripts/prereq-vpn-gateways.sh <NN>` (45 min), puis `PSK='<CLE_PARTAGEE>' ./scripts/catch-up/module-05/deploy.sh <NN>`.
- Coûts : passerelles VPN VpnGw1AZ et IP publiques facturées à l'heure, trafic de peering global et sortie VPN facturés au Go, VM Windows B2s_v2 et son disque `[À VÉRIFIER]` calculatrice de prix Azure.
