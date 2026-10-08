# Module 07 — Exercices

Fil rouge : **serveurs du portail client et de l'API de suivi des colis d'Arvéo**. Le portail web tourne sur deux VMs réparties dans deux zones derrière un Load Balancer public ; l'API tourne dans un groupe identique (VMSS) Flexible derrière un Load Balancer interne. Aucune VM n'a d'IP publique : administration par Azure Bastion depuis le hub, sortie Internet par une passerelle NAT. Les VMs web sont supervisées par l'agent Azure Monitor (données exploitées au module 10) et sauvegardées au module 9.

| Ressource | Nom (stagiaire 07) | Groupe | Lab |
|---|---|---|---|
| Bastion et son IP publique | `bas-st07-hub`, `pip-st07-bastion` | `rg-st07-hub` | 07.2 (script) |
| Passerelle NAT | `ng-st07-app`, `pip-st07-natgw` (sur `snet-web` et `snet-app`) | `rg-st07-spoke` | 07.2 |
| Serveur web 1 (zone 1) | `vm-st07-web01`, `nic-st07-web01` (`10.7.4.11`), `disk-st07-web01-data` | `rg-st07-app` | 07.2 |
| Serveur web 2 (zone 2) | `vm-st07-web02`, `nic-st07-web02` (`10.7.4.12`) | `rg-st07-app` | 07.3 |
| Load Balancer public | `lbe-st07-web`, `pip-st07-lbe-web`, pool `bp-web` | `rg-st07-app` | 07.4 |
| API | `vmss-st07-api`, `lbi-st07-api` (`10.7.5.100`), `nsg-st07-app`, `as-st07-api` | `rg-st07-app` | 07.5 |
| Supervision | `log-st07-shared` (`rg-st07-shared`), `dcr-st07-linux` | shared / app | 07.7 |

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
RG_APP="rg-${ST}-app"
RG_SHARED="rg-${ST}-shared"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
DIAG_SA=$(az storage account list -g "$RG_SHARED" \
  --query "[?starts_with(name, 'starveost${NN}diag')].name | [0]" -o tsv)   # module 3
az config set extension.use_dynamic_install=yes_without_prompt -o none
cd ~/formation 2>/dev/null || git clone <URL_DEPOT> ~/formation && cd ~/formation
vmrun() {   # vmrun <web01|web02> "<COMMANDE BASH>" : exécution sur vm-stNN-<nom> (rg-stNN-app)
  az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
echo "$ST $OCT $RG_APP $RG_SPOKE $DIAG_SA"
```
Résultat attendu (stagiaire 07 ; nom du compte avec suffixe éventuel du module 3) :
```
st07 7 rg-st07-app rg-st07-spoke starveost07diag
```

**État de départ** : fin du module 6 pour le réseau, c'est-à-dire l'état laissé par le nettoyage du jour 2 : hub `vnet-st<NN>-hub` (sous-réseau `AzureBastionSubnet` créé au M4), spokes app et données SANS pare-feu ni table de routes, NSG `nsg-st<NN>-web` (HTTP/HTTPS entrants), groupe `rg-st<NN>-app` vide. Socle du module 3 dans `rg-st<NN>-shared` : espace de travail `log-st<NN>-shared` et compte de diagnostic `starveost<NN>diag`. Le module 7 n'utilise aucune ressource de stockage du module 6. Stagiaire en retard : `./scripts/catch-up/module-07/deploy.sh <NN>` (10 à 20 min) produit l'état de FIN du module 7.

---

## Exercice 07.1 ⭐ — Dimensionner les charges Arvéo (en binôme)
**Durée** : 10 min · **Objectif** : dimensionner une VM (taille, disques, option tarifaire) pour une charge Arvéo et justifier le choix (objectif 8)
**Contexte** : la DSI d'Arvéo prépare le budget de migration de quatre charges du datacenter de Lyon. Pour chacune, elle attend une proposition argumentée.
**Prérequis** : slides de la séquence S7.1.

| N° | Charge | Profil relevé à Lyon |
|---|---|---|
| 1 | Portail client web | 2 serveurs, 2 vCPU et 4 Go chacun, CPU moyen 15 %, pics à 60 % de 8 h à 10 h |
| 2 | Base de données de l'ERP (SQL Server) | 8 vCPU, 64 Go, 24 h/24 pendant au moins 3 ans, licences SQL Server avec Software Assurance |
| 3 | Calcul nocturne des tournées | 16 vCPU, 32 Go, 4 h par nuit, traitement relançable en cas d'interruption |
| 4 | Serveur de fichiers « Lyon » | 2 To de partages SMB, accès modéré, conservé 6 mois pendant la migration |

### Étapes
1. Pour chaque charge, proposer : famille et taille, type de disque, option tarifaire.
2. Vérifier pour la charge 1 que la taille retenue est disponible dans les trois zones de France Central :
   ```bash
   az vm list-skus -l francecentral --size Standard_B2s_v2 --resource-type virtualMachines \
     --query "[].{Taille:name, Zones:join(',', locationInfo[0].zones)}" -o table
   ```
   Résultat attendu : une ligne `Standard_B2s_v2` avec les zones `1,2,3` (ordre variable).
3. Relever le quota régional de vCPU de l'abonnement partagé :
   ```bash
   Q="[?name.value=='cores' || name.value=='standardBSv2Family']"
   az vm list-usage -l francecentral -o table \
     --query "$Q.{Quota:name.localizedValue, Utilise:currentValue, Limite:limit}"
   ```
   Résultat attendu : deux lignes (`Total Regional vCPUs`, `Standard BSv2 Family vCPUs`), valeurs variables.
4. Pour la charge 4, se demander si une VM est la bonne réponse (module 6).

### Critères de réussite
- [ ] Une proposition (taille, disque, option tarifaire) par charge, chacune justifiée par un critère du profil.
- [ ] La charge 3 utilise une option tarifaire adaptée à un traitement interruptible.
- [ ] Le quota restant est comparé au besoin du module (8 vCPU par stagiaire en France Central).

---

## Lab 07.2 ⭐ — Première VM sans IP publique, accès par Bastion (guidé)
**Durée** : 25 min · **Objectif** : déployer une VM sans IP publique par CLI, puis l'administrer par Azure Bastion (objectif 8)
**Contexte** : le premier serveur du portail client Arvéo est déployé en zone 1. La sécurité impose : aucune IP publique sur les serveurs, administration par un point d'entrée unique dans le hub, sortie Internet contrôlée par une IP fixe (déclarée chez les partenaires de transport).
**Prérequis** : bloc de variables exécuté ; spokes du M4 présents.

### Étapes
1. **(13:32, avant l'exposé S7.1)** Lancer la création de Bastion (5 à 10 min) :
   ```bash
   ./scripts/labs/module-07/bastion.sh "$NN"
   ```
   Résultat attendu :
   ```
   == Sous-réseau AzureBastionSubnet de vnet-st07-hub
   10.7.1.0/26
   == IP publique pip-st07-bastion
      créée
   == Bastion bas-st07-hub (SKU Basic)
      déploiement lancé en arrière-plan (5 à 10 min)
   Suivi : az network bastion show -g rg-st07-hub -n bas-st07-hub --query provisioningState -o tsv
   ```
2. Créer la passerelle NAT et l'associer aux deux sous-réseaux du spoke app :
   ```bash
   az network public-ip create -g "$RG_SPOKE" -n "pip-${ST}-natgw" -l "$LOC" \
     --sku Standard --allocation-method Static --tags $TAGS -o none
   az network nat gateway create -g "$RG_SPOKE" -n "ng-${ST}-app" -l "$LOC" \
     --public-ip-addresses "pip-${ST}-natgw" --idle-timeout 4 --tags $TAGS -o none
   for SNET in snet-web snet-app; do
     az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
       -n "$SNET" --nat-gateway "ng-${ST}-app" -o none
   done
   az network vnet subnet list -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
     --query "[].{Nom:name, NAT:natGateway.id}" -o tsv | sed 's#/subscriptions/.*/##'
   ```
   Résultat attendu :
   ```
   snet-web	ng-st07-app
   snet-app	ng-st07-app
   ```
3. Générer le mot de passe administrateur des VMs Arvéo (conservé hors du dépôt Git) :
   ```bash
   mkdir -p ~/.arveo
   [[ -s ~/.arveo/web-admin.txt ]] || ( umask 077; echo "Arv-$(openssl rand -hex 8)-Z9" > ~/.arveo/web-admin.txt )
   ADMIN_PW=$(cat ~/.arveo/web-admin.txt)
   echo "${#ADMIN_PW} caractères"
   ```
   Résultat attendu : `23 caractères`.
4. Créer la carte réseau (IP fixe) puis la VM en zone 1, sans IP publique, configurée par cloud-init :
   ```bash
   SNET_WEB=$(az network vnet subnet show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
     -n snet-web --query id -o tsv)
   az network nic create -g "$RG_APP" -n "nic-${ST}-web01" -l "$LOC" --subnet "$SNET_WEB" \
     --private-ip-address "10.${OCT}.4.11" --tags $TAGS -o none
   az vm create -g "$RG_APP" -n "vm-${ST}-web01" -l "$LOC" --zone 1 --nics "nic-${ST}-web01" \
     --image Ubuntu2404 --size Standard_B2s_v2 \
     --os-disk-name "osdisk-${ST}-web01" --storage-sku StandardSSD_LRS \
     --admin-username arveoadmin --authentication-type password \
     --admin-password "$ADMIN_PW" \
     --custom-data scripts/labs/module-07/cloud-init-web.yaml \
     --boot-diagnostics-storage "$DIAG_SA" --tags $TAGS \
     --query "{Etat:powerState, IP:privateIpAddress, Zone:zones}" -o table
   ```
   Résultat attendu (2 à 3 min) :
   ```
   Etat        IP         Zone
   ----------  ---------  ------
   VM running  10.7.4.11  1
   ```
5. Attendre la fin de cloud-init, puis vérifier la page web et l'IP de sortie :
   ```bash
   vmrun web01 "cloud-init status --wait >/dev/null; curl -s localhost; curl -s --max-time 5 https://api.ipify.org; echo"
   az network public-ip show -g "$RG_SPOKE" -n "pip-${ST}-natgw" --query ipAddress -o tsv
   ```
   Résultat attendu (1 à 3 min) :
   ```
   <h1>Arveo - portail client v1</h1><p>Serveur : vm-st07-web01 - zone 1</p>
   <IP_NAT>
   <IP_NAT>
   ```
   La même adresse apparaît deux fois : la VM sort par la passerelle NAT.
6. Créer un disque de données de 32 Gio dans la zone de la VM, l'attacher au LUN 0, puis le formater et le monter sur `/srv/arveo` :
   ```bash
   az disk create -g "$RG_APP" -n "disk-${ST}-web01-data" -l "$LOC" --zone 1 \
     --size-gb 32 --sku StandardSSD_LRS --tags $TAGS -o none
   az vm disk attach -g "$RG_APP" --vm-name "vm-${ST}-web01" \
     --name "disk-${ST}-web01-data" --lun 0 --caching ReadOnly -o none
   vmrun web01 "$(cat scripts/labs/module-07/init-data-disk.sh)"
   ```
   Résultat attendu (nom du périphérique et taille arrondie variables) :
   ```
   /dev/sdc1     32G /srv/arveo
   ```
7. Vérifier que Bastion est prêt (`Succeeded`), puis se connecter dans le portail : `vm-st<NN>-web01` → **Se connecter** → **Se connecter via Bastion** → type d'authentification **Mot de passe VM**, utilisateur `arveoadmin`, mot de passe de `~/.arveo/web-admin.txt`. Dans le terminal ouvert :
   ```bash
   hostname; df -h /srv/arveo | tail -n 1; curl -s localhost
   ```
   Résultat attendu :
   ```
   vm-st07-web01
   /dev/sdc1        32G   24K   30G   1% /srv/arveo
   <h1>Arveo - portail client v1</h1><p>Serveur : vm-st07-web01 - zone 1</p>
   ```
8. Lister les ressources créées par `az vm create` et vérifier qu'aucune IP publique ni aucun NSG n'a été créé implicitement :
   ```bash
   az resource list -g "$RG_APP" --query "[].{Nom:name, Type:type}" -o table
   ```
9. Dans le portail, ouvrir `vm-st<NN>-web01` → **Aide** → **Diagnostics de démarrage** : afficher la capture d'écran et le journal série (fin du démarrage, ligne `cloud-init` finale). Vérifier le compte utilisé :
   ```bash
   az vm show -g "$RG_APP" -n "vm-${ST}-web01" \
     --query "diagnosticsProfile.bootDiagnostics.storageUri" -o tsv
   ```
   Résultat attendu : `https://starveost07diag.blob.core.windows.net/`.

### Critères de réussite
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web01 -d --query "[zones[0], publicIps, privateIps]" -o tsv` affiche `1`, une valeur vide et `10.<OCT>.4.11`.
- [ ] L'IP de sortie relevée à l'étape 5 est celle de `pip-st<NN>-natgw`.
- [ ] `vmrun web01 "findmnt -no SOURCE,TARGET /srv/arveo"` affiche une partition montée sur `/srv/arveo`.
- [ ] Session Bastion ouverte sur `vm-st<NN>-web01`.
- [ ] Diagnostics de démarrage actifs vers `starveost<NN>diag` (capture d'écran visible dans le portail).

---

## Exercice 07.3 ⭐⭐ — Deuxième serveur web en Bicep (semi-autonome)
**Durée** : 15 min · **Objectif** : déployer une VM de façon reproductible par Bicep, dans une autre zone (objectif 8)
**Contexte** : l'équipe d'exploitation d'Arvéo veut un modèle unique pour tous les serveurs web, versionné dans le dépôt Git. Le second serveur du portail est créé en zone 2 à partir de ce modèle.
**Prérequis** : lab 07.2 terminé (passerelle NAT, mot de passe).

**Énoncé** :
1. Copier `scripts/labs/module-07/vm-web-squelette.bicep` en `scripts/labs/module-07/vm-web.bicep` (même dossier, pour `loadTextContent`).
2. Compléter les cinq `TODO` : zone, image Ubuntu Server 24.04 LTS, disque OS (`osdisk-st<NN>-<nomCourt>`, SSD Standard LRS, supprimé avec la VM), données personnalisées `cloud-init-web.yaml`, authentification par mot de passe.
3. Compiler sans erreur ni avertissement, puis prévisualiser le déploiement de `web02` (zone 2, IP `10.<OCT>.4.12`) avec `what-if`. Si le compte de diagnostic du module 3 porte un suffixe, passer `diagStorageName="$DIAG_SA"`.
4. Déployer, puis vérifier la page servie par `vm-st<NN>-web02` (zone affichée : 2).
5. Relancer `what-if` avec les mêmes paramètres, puis avec `zone=3`. Relever les deux résultats.
6. Répondre par écrit :
   - a. Pourquoi le disque OS de `web02` n'a-t-il pas besoin d'une zone déclarée ?
   - b. Que se passerait-il au déploiement avec `zone=3` ? Comment déplacer une VM d'une zone à une autre ?
   - c. Modifier `cloud-init-web.yaml` puis redéployer : la page de `web02` change-t-elle ? Pourquoi ?

**Indices** :
- Propriété de zone : `zones: [ zone ]` au même niveau que `properties`.
- Image : objet `imageReference` (`publisher`, `offer`, `sku`, `version`).
- Disque OS : `createOption: 'FromImage'`, `deleteOption: 'Delete'`, `managedDisk.storageAccountType`.
- Données personnalisées : `base64(loadTextContent('cloud-init-web.yaml'))`.
- Linux : `linuxConfiguration.disablePasswordAuthentication`.
- Compilation : `az bicep build --file <FICHIER>` ; prévisualisation : `az deployment group what-if -g <GROUPE> --template-file <FICHIER> --parameters ...`.
- Mot de passe : `adminPassword="$(cat ~/.arveo/web-admin.txt)"` (jamais en clair dans un fichier).

**Critères de réussite** :
- [ ] `az bicep build --file scripts/labs/module-07/vm-web.bicep` ne produit ni erreur ni avertissement.
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web02 --query "[zones[0], storageProfile.osDisk.name]" -o tsv` affiche `2` et `osdisk-st<NN>-web02`.
- [ ] `vmrun web02 "curl -s localhost"` affiche `vm-st<NN>-web02 - zone 2`.
- [ ] Les résultats de l'étape 5 et les trois réponses de l'étape 6 sont rédigés.

---

## Lab 07.4 ⭐⭐ — Load Balancer public et bascule entre zones (semi-autonome)
**Durée** : 20 min · **Objectif** : rendre le portail hautement disponible derrière un Load Balancer et prouver la bascule (objectif 8)
**Contexte** : les clients d'Arvéo accèdent au portail par une adresse publique unique. La perte d'un serveur, ou d'une zone entière de France Central, ne doit pas interrompre le service.
**Prérequis** : `vm-st<NN>-web01` (zone 1) et `vm-st<NN>-web02` (zone 2) en fonctionnement.

**Énoncé** :
1. Créer dans `rg-st<NN>-app` l'IP publique zone-redondante `pip-st<NN>-lbe-web` et le Load Balancer Standard `lbe-st<NN>-web` (frontal `fe-web`, pool `bp-web`).
2. Créer la sonde `hp-http` (HTTP, port 80, chemin `/`) et la règle `rule-http` (TCP 80 → 80) SANS SNAT sortant.
3. Ajouter les cartes `nic-st<NN>-web01` et `nic-st<NN>-web02` au pool `bp-web`.
4. Depuis Cloud Shell, envoyer 10 requêtes sur l'IP publique du Load Balancer et compter les réponses par serveur.
5. Simuler une panne : arrêter nginx sur `web01`, attendre 15 s, renvoyer 10 requêtes. Afficher l'état de santé du pool (métrique ou portail), puis redémarrer nginx.
6. Répondre par écrit :
   - a. Pourquoi désactiver le SNAT sortant de la règle ? Par où sortent les VMs du pool ?
   - b. Quelle règle du NSG `nsg-st<NN>-web` laisse passer les clients ? Que se passerait-il sans NSG sur `snet-web` ?
   - c. Pourquoi les VMs de test du module 4 (`vm-st<NN>-test-web`) ne doivent-elles PAS rejoindre ce pool ?

**Indices** :
- `az network public-ip create --sku Standard --zone 1 2 3` ; `az network lb create --sku Standard --public-ip-address --frontend-ip-name --backend-pool-name`.
- `az network lb probe create --protocol Http --path /` ; `az network lb rule create --disable-outbound-snat true`.
- Nom de la configuration IP des cartes : `ipconfig1` ; ajout au pool : `az network nic ip-config address-pool add`.
- Comptage : `for i in $(seq 10); do curl -s http://<IP>/ ; echo; done | grep -o 'vm-st[0-9]*-web0[12]' | sort | uniq -c`.
- Panne : `vmrun web01 "systemctl stop nginx"` puis `systemctl start nginx`.
- Santé : métrique `DipAvailability` du Load Balancer (`az monitor metrics list --resource <ID_LB> --metric DipAvailability --interval PT1M`) ou **Insights** du Load Balancer dans le portail.

**Critères de réussite** :
- [ ] `az network lb address-pool show -g rg-st<NN>-app --lb-name lbe-st<NN>-web -n bp-web --query "length(backendIPConfigurations)"` renvoie `2`.
- [ ] L'étape 4 montre des réponses des DEUX serveurs (zones 1 et 2).
- [ ] Pendant la panne, 10 requêtes sur 10 sont servies par `web02`, sans erreur.
- [ ] Les trois réponses de l'étape 6 sont rédigées.

---

## Défi 07.5 ⭐⭐⭐ — API de suivi des colis en VMSS (autonome)
**Durée** : 30 min · **Objectif** : déployer un groupe identique zone-redondant avec mise à l'échelle automatique derrière un Load Balancer interne (objectif 8)
**Contexte** : l'API de suivi des colis est appelée par le portail (et demain par les applications mobiles des chauffeurs). Sa charge varie fortement selon l'heure de livraison. L'API ne doit jamais être exposée sur Internet : seul le portail (`snet-web`) peut l'appeler, et l'administration passe par Bastion.

**Exigences** :

| Élément | Exigence |
|---|---|
| Instances | VMSS Flexible `vmss-st<NN>-api`, `Standard_B2s_v2`, Ubuntu 24.04, zones 1, 2 et 3, dans `snet-app` |
| Configuration | `scripts/labs/module-07/cloud-init-api.yaml` (nginx sur 8080, réponse JSON) |
| Équilibrage | Load Balancer interne Standard `lbi-st<NN>-api`, frontal statique `10.<OCT>.5.100` zone-redondant, TCP 8080, sonde HTTP `/` |
| Mise à l'échelle | `as-st<NN>-api` : 2 à 4 instances ; +1 si CPU moyen > 70 % sur 5 min ; -1 si < 25 % sur 10 min |
| Filtrage | `nsg-st<NN>-app` sur `snet-app` : 8080 depuis `snet-web`, 22 depuis `AzureBastionSubnet`, sonde du Load Balancer, refus du reste du trafic VNet |

**Énoncé** :
1. Déployer l'ensemble, de préférence en Bicep (fichier `vmss-api.bicep` dans un dossier personnel), sinon en CLI documentée. Contraintes : aucune IP publique, sous-réseau `snet-app` NON redéclaré en Bicep, passerelle NAT conservée sur `snet-app`.
2. Prouver le fonctionnement par quatre tests :
   - a. depuis `web01`, six appels à `http://10.<OCT>.5.100:8080/` : au moins deux instances différentes répondent ;
   - b. les instances sont réparties dans au moins deux zones ;
   - c. depuis `web01`, connexion TCP au port 22 d'une instance : refusée ou expirée ;
   - d. le profil de mise à l'échelle affiche min 2, max 4 et deux règles.
3. Répondre par écrit :
   - a. Pourquoi l'orchestration Flexible plutôt qu'Uniforme ici ?
   - b. Que se passe-t-il pour l'API si la zone 1 de France Central est perdue ? Et si le minimum était 1 ?
   - c. Pourquoi associer le NSG et la passerelle NAT au sous-réseau par CLI plutôt qu'en redéclarant `snet-app` dans le Bicep ?

**Critères de réussite** :
- [ ] `az vmss show -g rg-st<NN>-app -n vmss-st<NN>-api --query "[orchestrationMode, zones]" -o json` affiche `Flexible` et les trois zones.
- [ ] Les quatre tests donnent le résultat attendu.
- [ ] `az network vnet subnet show -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-app -n snet-app --query "[natGateway.id, networkSecurityGroup.id]" -o tsv` renvoie `ng-st<NN>-app` et `nsg-st<NN>-app`.
- [ ] Redéploiement du même fichier : `what-if` sans changement sur le VMSS ni sur le Load Balancer.
- [ ] Les trois réponses de l'étape 3 sont rédigées.

---

## Lab 07.6 ⭐⭐ — Portail v2 par extension Custom Script (semi-autonome)
**Durée** : 15 min · **Objectif** : automatiser la configuration des VMs par l'extension Custom Script (objectif 8)
**Contexte** : la version 2 du portail relaie les appels `/api/` vers l'API de suivi des colis. Elle doit être déployée sur les deux serveurs web existants, sans connexion interactive, de façon rejouable.
**Prérequis** : lab 07.4 terminé ; défi 07.5 terminé ou rattrapage exécuté (sinon `/api/` répond `502`).

**Énoncé** :
1. Lire `scripts/labs/module-07/portail-v2.sh` : repérer ce qu'il modifie et pourquoi il attend la fin de cloud-init.
2. Remplacer `__OCT__` par l'octet du stagiaire, encoder le script en base64 et l'appliquer par l'extension Custom Script (Linux, version 2.1) à `vm-st<NN>-web01` puis `vm-st<NN>-web02`, en paramètre PROTÉGÉ.
3. Vérifier l'état des extensions, puis la page d'accueil (`v2`) et `/api/` à travers `lbe-st<NN>-web`.
4. Réappliquer l'extension sur `web01` avec exactement les mêmes paramètres : le script s'exécute-t-il ? Le prouver avec le journal du gestionnaire. Recommencer avec l'option de réexécution forcée.
5. Répondre par écrit :
   - a. Pourquoi un paramètre protégé plutôt qu'un paramètre public pour le script ?
   - b. Que se passerait-il en appliquant ensuite une seconde extension Custom Script avec un autre script ?
   - c. Les instances de `vmss-st<NN>-api` ajoutées par la mise à l'échelle recevraient-elles ce script ? Où le déclarer pour qu'elles le reçoivent ?

**Indices** :
- Encodage : `sed "s/__OCT__/${OCT}/g" <FICHIER> | base64 -w0`.
- `az vm extension set --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 --protected-settings '{"script": "<BASE64>"}'`.
- État : `az vm extension list ... --query "[].{Nom:name, Etat:provisioningState}"`.
- Journal : `vmrun web01 "tail -n 5 /var/log/azure/custom-script/handler.log"`.
- Réexécution : option `--force-update`.

**Critères de réussite** :
- [ ] `CustomScript` en `Succeeded` sur les deux VMs.
- [ ] `curl -s http://<IP_LB>/` affiche `portail client v2` et `curl -s http://<IP_LB>/api/` renvoie le JSON de l'API (`"service":"api-suivi-colis"`).
- [ ] La différence entre réapplication simple et `--force-update` est prouvée par le journal.
- [ ] Les trois réponses de l'étape 5 sont rédigées.

---

## Lab 07.7 ⭐⭐ — Agent Azure Monitor et règle de collecte (semi-autonome)
**Durée** : 20 min · **Objectif** : installer l'agent Azure Monitor par extension et collecter Syslog et performances des VMs web (objectif 8, préparation de l'objectif 11)
**Contexte** : l'équipe d'exploitation d'Arvéo veut centraliser les journaux d'authentification et les compteurs de performance des serveurs web dans l'espace de travail unique du socle (module 3), exploité au module 10.
**Prérequis** : `vm-st<NN>-web01` et `vm-st<NN>-web02` en fonctionnement, sortie Internet par la passerelle NAT.

**Énoncé** :
1. Vérifier l'espace de travail Log Analytics `log-st<NN>-shared` créé au module 3 dans `rg-st<NN>-shared` : région, tarification, rétention, ID client.
2. Attribuer une identité managée affectée par le système aux deux VMs web.
3. Installer l'extension `AzureMonitorLinuxAgent` (éditeur `Microsoft.Azure.Monitor`) sur les deux VMs, mise à jour automatique activée.
4. Lire puis déployer `scripts/labs/module-07/dcr-arveo-linux.bicep` dans `rg-st<NN>-app`. Lister les associations de règles de collecte de `web01`.
5. Générer un événement Syslog d'avertissement sur `web01`, puis, après 5 à 10 min, interroger l'espace de travail : dernières pulsations (`Heartbeat`) par ordinateur et dernier événement Syslog de `web01`.
6. Répondre par écrit :
   - a. Pourquoi l'agent a-t-il besoin d'une identité managée ?
   - b. Comment collecter les mêmes données sur une future VM Windows sans modifier la règle existante ?
   - c. Quelle ressource faudrait-il modifier pour collecter aussi la facilité `cron` ?

**Indices** :
- `az monitor log-analytics workspace show --query "{Region:location, Tarif:sku.name, Retention:retentionInDays, ID:customerId}"` ; absent : rattrapage du module 3.
- `az vm identity assign` ; `az vm extension set --publisher Microsoft.Azure.Monitor --name AzureMonitorLinuxAgent --enable-auto-upgrade true`.
- Déploiement : `az deployment group create -g <GROUPE> --template-file <FICHIER> --parameters numero=<NN>`.
- Associations : `az monitor data-collection rule association list --resource <ID_VM>`.
- Événement : `vmrun web01 "logger -p auth.warning 'Arveo test AMA st<NN>'"`.
- Requête : `az monitor log-analytics query -w <ID_CLIENT_ESPACE> --analytics-query "<KQL>" -o table` ; ID client : propriété `customerId` de l'espace de travail.

**Critères de réussite** :
- [ ] `AzureMonitorLinuxAgent` en `Succeeded` sur les deux VMs.
- [ ] L'association `dcra-vm-st<NN>-web01` pointe vers `dcr-st<NN>-linux`.
- [ ] La requête `Heartbeat` renvoie une ligne par VM web, datée de moins de 15 min.
- [ ] L'événement `Arveo test AMA` est retrouvé dans la table `Syslog`.
- [ ] Les trois réponses de l'étape 6 sont rédigées.

---

## Bonus 🚀
1. **Nom public du portail** : mettre à jour l'enregistrement `www` de la zone publique `arveo-st<NN>.fr` (module 4), qui pointe encore vers l'IP du pare-feu supprimé, pour qu'il désigne `pip-st<NN>-lbe-web`. Vérifier la résolution avec `nslookup www.arveo-st<NN>.fr <SERVEUR_DE_NOMS_AZURE>`.
2. **Connexion Entra ID** : installer l'extension `AADSSHLoginForLinux` sur `web02`, attribuer à son propre compte le rôle « Connexion administrateur aux machines virtuelles » sur `rg-st<NN>-app`, puis se connecter par Bastion avec l'authentification Microsoft Entra ID `[À VÉRIFIER]` prise en charge par la SKU Basic. Comparer la traçabilité avec le compte local `arveoadmin`.
3. **Groupe à haute disponibilité** : tenter de créer `vm-st<NN>-test-as` dans un groupe `avail-st<NN>-web` AVEC `--zone 1`. Interpréter l'erreur. Supprimer immédiatement toute ressource créée.
4. **Mise à l'échelle sous charge** : sur une instance de l'API, lancer `timeout 900 yes > /dev/null &` (deux fois, une par vCPU si `B2s_v2`) et observer l'historique de mise à l'échelle (`az monitor activity-log list --resource-group rg-st<NN>-app --offset 30m`). Expliquer pourquoi une seule instance chargée ne suffit pas toujours à déclencher l'augmentation.

## Nettoyage
- **Fin du jour 3 (16:55)** :
  ```bash
  ./scripts/cleanup/module-07-vm.sh "$NN"
  ```
  Le script supprime Bastion et son IP publique (5 à 10 min), désactive la mise à l'échelle automatique et désalloue les VMs web et les instances de l'API. Relançable sans risque si la session Cloud Shell se ferme.
- Conservés pour le jour 4 : VMs (désallouées) et disques, Load Balancers, passerelle NAT, NSG, extensions, règle de collecte (modules 8 à 10) ; socle du module 3 inchangé.
- Bonus 3 : supprimer `vm-st<NN>-test-as`, ses disques et `avail-st<NN>-web` s'ils ont été créés.
- Coûts : Bastion Basic et IP publiques facturés à l'heure ; passerelle NAT à l'heure et au Go traité ; Load Balancer Standard selon les règles et les données traitées ; VMs B2s_v2/B2s_v2 à l'heure (désallouées : disques seuls) ; Log Analytics au Go ingéré `[À VÉRIFIER]` calculatrice de prix Azure.
