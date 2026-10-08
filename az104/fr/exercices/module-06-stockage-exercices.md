# Module 06 — Exercices

Fil rouge : **migration des données d'Arvéo vers Azure**. Les preuves de livraison scannées par les chauffeurs (« POD », proof of delivery) rejoignent un compte Blob protégé, à cycle de vie automatisé et répliqué vers un compte d'archive ; ce compte n'est joignable que depuis le réseau Arvéo. Le serveur de fichiers de Lyon, créé au module 5, est synchronisé avec Azure Files par Azure File Sync, puis son contenu est exporté avec AzCopy. Les comptes créés ici sont réutilisés aux modules 8 (application web), 9 (sauvegarde) et 10 (supervision).

| Ressource | Nom (stagiaire 07, session `2610`) | Groupe | Lab |
|---|---|---|---|
| Compte de données (Blob) | `starveost07data2610`, conteneur `pod` | `rg-st07-data` | 06.1, 06.2 |
| Compte d'archive | `starveost07arch2610`, conteneurs `pod-replica`, `partage-lyon`, `pod-sync` | `rg-st07-data` | 06.2, 06.6 |
| Accès aux données | rôle Storage Blob Data Contributor, stratégie `sap-transporteurs` | `rg-st07-data` | 06.3 |
| Private endpoint | `pe-st07-blob` (`10.7.9.4`), carte `nic-st07-pe-blob` | `rg-st07-data` (dans `snet-pe`) | 06.4 |
| Zone DNS privée | `privatelink.blob.core.windows.net` | `rg-st07-hub` | 06.4 |
| Compte de fichiers | `starveost07files2610`, partage `partage-lyon` | `rg-st07-data` | 06.5 |
| Synchronisation | `sss-st07`, groupe `sg-partage-lyon` | `rg-st07-data` | 06.5 |
| Serveur de Lyon | `vm-st07-lyon-fs`, disque `disk-st07-lyon-fs-data` (`F:`) | `rg-st07-lyon` | 06.5 |

Variables utilisées dans tous les labs :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<SES>` = code de session à 4 caractères (minuscules et chiffres), communiqué par la formatrice (ex. `2610`)
- `<URL_DEPOT>` = adresse du dépôt Git de la formation, communiquée par la formatrice
- `<DOMAINE>` = domaine du tenant de formation (ex. `arveoformation.onmicrosoft.com`)

Tags obligatoires sur chaque ressource (stratégie du module 2) : `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

**Bloc de variables** : à recoller dans Cloud Shell (Bash) au début de CHAQUE lab (session fermée après 20 min d'inactivité).
```bash
NN=<NN>
SES=<SES>
OCT=$((10#$NN))
ST="st${NN}"
RG_HUB="rg-${ST}-hub"
RG_SPOKE="rg-${ST}-spoke"
RG_LYON_ST="rg-${ST}-lyon"
RG_DATA="rg-${ST}-data"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
SA_DATA="starveost${NN}data${SES}"
SA_ARCH="starveost${NN}arch${SES}"
SA_FILES="starveost${NN}files${SES}"
SSS="sss-${ST}"
WORK="$HOME/arveo-m06"
mkdir -p "$WORK"
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
echo "$ST $SA_DATA $SA_ARCH $SA_FILES"
```
Résultat attendu (stagiaire 07, session `2610`) :
```
st07 starveost07data2610 starveost07arch2610 starveost07files2610
```

**État de départ** : fin du module 5 après nettoyage du jour 2 (VNets hub et spokes, `snet-pe` dans le spoke données, zone `arveo.internal`, serveur `vm-st<NN>-lyon-fs` et VMs de test arrêtés, pare-feu et passerelles VPN supprimés). Le groupe `rg-st<NN>-data` est vide. Stagiaire dont le serveur de Lyon manque : `./scripts/labs/module-05/lyon-vm.sh <NN>` avant le démarrage ci-dessous.

**Démarrage du jour 3 (09:00, avant l'exposé)** : préparation du serveur de Lyon, en arrière-plan pendant les labs 06.1 à 06.4.
```bash
./scripts/labs/module-06/lyon-fs-prep.sh "$NN"
```
Résultat attendu :
```
== Démarrage des VMs
   vm-st07-lyon-fs démarrée
== Disque de données
   disk-st07-lyon-fs-data créé (32 Go)
   disk-st07-lyon-fs-data attaché (LUN 0)
== Identité managée
   ID de principal : <GUID>
== Préparation Windows (commande d'exécution managée prep-afs)
   prep-afs lancée en arrière-plan (10 à 15 min)
Suivi : ./scripts/labs/module-06/lyon-fs-prep.sh 07 --status
```
Le script démarre aussi `vm-st<NN>-test-data` (défi 06.4), attache un disque de données au serveur de Lyon, lui attribue une identité managée et lance, sur le serveur, l'initialisation du volume `F:`, la création du contenu du partage, l'installation de l'agent Azure File Sync et des modules PowerShell.

---

## Lab 06.1 ⭐ — Compte de données et redondance (guidé)
**Durée** : 13 min · **Objectif** : créer un compte de stockage et justifier sa redondance pour un besoin donné (objectif 7)
**Contexte** : la DSI d'Arvéo stocke les preuves de livraison dans Azure. Exigences : aucune donnée publique, chiffrement en transit moderne, copie dans une seconde région lisible même si France Central est indisponible, et conservation longue en niveau Archive.
**Prérequis** : bloc de variables exécuté, préparation du serveur de Lyon lancée.

### Étapes
1. Tester la disponibilité de deux noms : un nom invalide, puis le nom du compte de données.
   ```bash
   az storage account check-name --name "st-${NN}-data" \
     --query "[nameAvailable, reason]" -o tsv
   az storage account check-name --name "$SA_DATA" --query nameAvailable -o tsv
   ```
   Résultat attendu :
   ```
   false	AccountNameInvalid
   true
   ```
   Si le second test renvoie `false` : nom déjà pris (autre session) ; prévenir la formatrice, qui fournit un autre code de session.

2. Créer le compte en LRS, accès anonyme désactivé, TLS 1.2 minimum.
   ```bash
   az storage account create -g "$RG_DATA" -n "$SA_DATA" -l "$LOC" \
     --kind StorageV2 --sku Standard_LRS --access-tier Hot \
     --min-tls-version TLS1_2 --allow-blob-public-access false \
     --tags $TAGS \
     --query "[provisioningState, primaryLocation, sku.name]" -o tsv
   ```
   Résultat attendu (30 s à 1 min) :
   ```
   Succeeded	francecentral	Standard_LRS
   ```

3. Afficher les points de terminaison des quatre services.
   ```bash
   az storage account show -g "$RG_DATA" -n "$SA_DATA" \
     --query "primaryEndpoints.{Blob:blob, Fichiers:file, Files_attente:queue, Tables:table}" -o table
   ```
   Résultat attendu :
   ```
   Blob                                             Fichiers                                         Files_attente                                     Tables
   -----------------------------------------------  -----------------------------------------------  ------------------------------------------------  ------------------------------------------------
   https://starveost07data2610.blob.core.windows.net/  https://starveost07data2610.file.core.windows.net/  https://starveost07data2610.queue.core.windows.net/  https://starveost07data2610.table.core.windows.net/
   ```

4. Passer le compte en RA-GRS, puis lire la région secondaire et son point de terminaison.
   ```bash
   az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Standard_RAGRS \
     --query "{SKU:sku.name, Secondaire:secondaryLocation, Etat:statusOfSecondary}" -o table
   az storage account show -g "$RG_DATA" -n "$SA_DATA" \
     --query secondaryEndpoints.blob -o tsv
   ```
   Résultat attendu :
   ```
   SKU             Secondaire    Etat
   --------------  ------------  ---------
   Standard_RAGRS  francesouth   available
   https://starveost07data2610-secondary.blob.core.windows.net/
   ```

5. Lire l'état de la réplication géographique (horodatage de la dernière synchronisation).
   ```bash
   az storage account show -g "$RG_DATA" -n "$SA_DATA" --expand geoReplicationStats \
     --query "geoReplicationStats.{Etat:status, DerniereSynchro:lastSyncTime}" -o table
   ```
   Résultat attendu (état `Bootstrap` les premières minutes, puis `Live` ; horodatage variable) :
   ```
   Etat    DerniereSynchro
   ------  -------------------------
   Live    2026-10-08T07:21:44+00:00
   ```

6. Tenter de passer le compte en Premium, puis lire le message d'erreur.
   ```bash
   az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Premium_LRS -o none
   ```
   Résultat attendu : erreur indiquant que la conversion entre niveaux de performance n'est pas prise en charge (`[À VÉRIFIER]` libellé exact).

7. Répondre par écrit :
   - a. Pourquoi RA-GRS plutôt que ZRS ou RA-GZRS, au regard des quatre exigences du contexte ?
   - b. Que signifie un horodatage `DerniereSynchro` antérieur de 10 min à l'heure actuelle, en cas de basculement ?
   - c. Comment obtenir un compte Premium avec les mêmes données ?

### Critères de réussite
- [ ] `az storage account show -g rg-st<NN>-data -n starveost<NN>data<SES> --query "[sku.name, minimumTlsVersion, allowBlobPublicAccess]" -o tsv` affiche `Standard_RAGRS`, `TLS1_2`, `False`.
- [ ] Le point de terminaison secondaire se termine par `-secondary.blob.core.windows.net/`.
- [ ] Les trois réponses de l'étape 7 sont rédigées.

---

## Lab 06.2 ⭐⭐ — Protection, réplication et cycle de vie des preuves de livraison (semi-autonome)
**Durée** : 30 min · **Objectif** : automatiser la protection et le cycle de vie des blobs (objectif 7)
**Contexte** : chaque jour, les chauffeurs d'Arvéo déposent leurs preuves de livraison signées. La direction juridique exige : aucune perte par écrasement ou suppression accidentelle (14 jours pour réagir), une copie de conformité dans un compte séparé, et la politique de conservation interne suivante, sans intervention manuelle.

| Âge (depuis la dernière modification) | Niveau ou action |
|---|---|
| 0 à 30 jours | Hot (litiges clients) |
| 30 à 90 jours | Cool |
| 90 à 180 jours | Cold |
| 180 jours à 10 ans | Archive |
| Plus de 10 ans (3 650 jours) | Suppression |
| Versions antérieures de plus de 90 jours | Suppression |

**Prérequis** : lab 06.1 terminé, bloc de variables exécuté. Dans ce lab, les opérations sur les données utilisent la clé du compte (`--auth-mode key`) ; l'accès par Entra ID est traité en 06.3.

**Énoncé** :
1. Activer sur `starveost<NN>data<SES>` : versioning, flux de modifications, suppression réversible des blobs (14 jours) et des conteneurs (14 jours).
2. Générer les données d'exemple (fournies, hors objectif) :
   ```bash
   mkdir -p "$WORK/pod"
   for i in $(seq -w 1 20); do
     echo "Preuve de livraison ${i} - tournée T${i} - signée" > "$WORK/pod/pod-0${i}.txt"
   done
   ls "$WORK/pod" | wc -l
   ```
   Résultat attendu : `20`.
3. Créer le conteneur privé `pod`, puis y déposer les 20 fichiers sous le préfixe `2026/10/`.
4. Écraser `2026/10/pod-001.txt` avec un nouveau contenu (`Preuve de livraison 01 - CORRIGÉE`), puis lister les versions de ce blob : identifiant, version courante ou non.
5. Créer un conteneur `tmp`, le supprimer, l'afficher parmi les conteneurs supprimés, puis le restaurer.
6. Créer le compte d'archive `starveost<NN>arch<SES>` (Standard LRS, niveau par défaut Cool, TLS 1.2, accès anonyme désactivé, tags), activer son versioning et créer son conteneur `pod-replica`.
7. Créer la règle de réplication d'objets `pod` → `pod-replica` (blobs créés depuis le 1er janvier 2026) sur le compte de destination, puis l'appliquer au compte source. Après 2 à 5 min, compter les blobs de `pod-replica`.
8. Écrire `lifecycle-pod.json` traduisant la politique de conservation du contexte, l'appliquer au compte de données, puis afficher la règle appliquée.
9. Archiver `2026/10/pod-003.txt`, tenter de le télécharger, relever l'erreur, puis lancer sa réhydratation standard vers Hot et afficher son état d'archive.
10. Répondre par écrit :
    - a. Pourquoi aucun blob n'a-t-il encore changé de niveau sous l'effet de la règle de cycle de vie ?
    - b. Le compte de données est en RA-GRS : qu'apporte en plus la réplication d'objets vers `starveost<NN>arch<SES>` ?
    - c. Pourquoi les versions antérieures ont-elles leur propre action de suppression dans la règle ?

**Indices** :
- Propriétés du service Blob : `az storage account blob-service-properties update --enable-versioning --enable-change-feed --enable-delete-retention --delete-retention-days --enable-container-delete-retention --container-delete-retention-days`.
- Dépôt en masse : `az storage blob upload-batch -d <CONTENEUR> -s <DOSSIER> --destination-path <PREFIXE> --account-name <COMPTE> --auth-mode key`.
- Versions : `az storage blob list ... --prefix <NOM> --include v --query "[].{Version:versionId, Courante:isCurrentVersion}"`.
- Conteneurs supprimés : `az storage container list --include-deleted --query "[?deleted]"` ; restauration : `az storage container restore -n <NOM> --deleted-version <VERSION>`.
- Réplication : `az storage account or-policy create` sur la destination (options `--source-account`, `--destination-account`, `--source-container`, `--destination-container`, `--min-creation-time`), puis `or-policy show` (destination) redirigé vers `or-policy create --policy "@-"` (source).
- Cycle de vie : structure `{"rules": [{"enabled", "name", "type": "Lifecycle", "definition": {"filters", "actions"}}]}` ; actions `tierToCool`, `tierToCold`, `tierToArchive`, `delete` de `baseBlob` et `version` ; application par `az storage account management-policy create --policy @lifecycle-pod.json`.
- Archive et réhydratation : `az storage blob set-tier --tier Archive`, puis `--tier Hot --rehydrate-priority Standard` ; état : `az storage blob show --query "properties.{Niveau:blobTier, Archive:rehydrationStatus}"`.

**Critères de réussite** :
- [ ] `az storage account blob-service-properties show -g rg-st<NN>-data -n starveost<NN>data<SES> --query "[isVersioningEnabled, changeFeed.enabled, deleteRetentionPolicy.days, containerDeleteRetentionPolicy.days]" -o tsv` affiche `True`, `True`, `14`, `14`.
- [ ] Au moins deux versions de `2026/10/pod-001.txt`, dont une seule courante.
- [ ] Conteneur `tmp` présent et actif.
- [ ] `pod-replica` contient 20 blobs.
- [ ] `az storage account management-policy show -g rg-st<NN>-data --account-name starveost<NN>data<SES> --query "policy.rules[0].definition.actions.baseBlob"` affiche les quatre actions et leurs seuils.
- [ ] `2026/10/pod-003.txt` en état `rehydrate-pending-to-hot`.
- [ ] Les trois réponses de l'étape 10 sont rédigées.

---

## Exercice 06.3 ⭐⭐ — Accès délégué : SAS, Entra ID et fin des clés (semi-autonome)
**Durée** : 15 min (dont 5 min avant la pause) · **Objectif** : restreindre l'accès aux données par SAS et Entra ID, puis le prouver (objectif 7)
**Contexte** : les transporteurs sous-traitants consultent les preuves de livraison de leurs tournées pendant 48 h ; l'application de facturation lit un blob précis. Le RSSI exige de pouvoir révoquer un accès sans couper les autres, puis la fin de l'usage des clés du compte.
**Prérequis** : lab 06.2 terminé.

**Énoncé** :
1. **(10:25, avant la pause)** S'attribuer le rôle « Storage Blob Data Contributor » sur le compte de données (propagation jusqu'à 10 min).
2. Lire la clé `key1` dans une variable (sans l'afficher), générer un SAS de compte (service Blob, types `sco`, permissions `rl`, 2 h, HTTPS) signé avec elle, puis lister les conteneurs du compte avec `curl` : code HTTP attendu `200`.
3. Créer sur le conteneur `pod` la stratégie d'accès stockée `sap-transporteurs` (`rl`, 2 h), générer un SAS de service qui s'y réfère, puis lister les blobs de `pod` avec `curl` : `200`.
4. Supprimer la stratégie `sap-transporteurs`, attendre 30 s, puis rejouer le test de l'étape 3.
5. Régénérer `key1`, puis rejouer le test de l'étape 2.
6. Générer un SAS de délégation d'utilisateur en lecture sur `2026/10/pod-001.txt` (2 h), le conserver dans la variable `UD_URL`, puis télécharger le blob avec `curl` : contenu `CORRIGÉE` attendu.
7. Désactiver l'accès par clé partagée sur le compte de données. Lister les blobs de `pod` avec `--auth-mode key`, puis avec `--auth-mode login`, puis rejouer le téléchargement de l'étape 6.
8. Répondre par écrit :
   - a. Pourquoi l'étape 4 révoque-t-elle l'accès sans changer de clé ? Quel autre accès l'étape 5 a-t-elle coupé ?
   - b. Quel SAS fonctionne encore après l'étape 7, et pourquoi ?
   - c. Propriétaire du groupe `rg-st<NN>-data`, pourquoi faut-il encore un rôle de données à l'étape 1 ?

**Indices** :
- Rôle : `az role assignment create --assignee <UPN> --role "Storage Blob Data Contributor" --scope <ID_COMPTE>` ; UPN courant : `az account show --query user.name -o tsv`.
- Clé : `KEY1=$(az storage account keys list ... --query "[?keyName=='key1'].value" -o tsv)`.
- Date d'expiration : `END=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')`.
- SAS : `az storage account generate-sas`, `az storage container policy create`, `az storage container generate-sas --policy-name`, `az storage blob generate-sas --as-user --auth-mode login --full-uri`.
- Test HTTP : `curl -s -o /dev/null -w "%{http_code}\n" "<URL>"` ; liste des conteneurs : `https://<COMPTE>.blob.core.windows.net/?comp=list&<SAS>` ; liste des blobs : `https://<COMPTE>.blob.core.windows.net/pod?restype=container&comp=list&<SAS>`.
- Clé : `az storage account keys renew --key key1` ; désactivation : `az storage account update --allow-shared-key-access false`.

**Critères de réussite** :
- [ ] Codes HTTP relevés : `200` (étape 2), `200` (étape 3), `403` (étape 4), `403` (étape 5), `200` (étapes 6 et 7).
- [ ] `az storage account show -g rg-st<NN>-data -n starveost<NN>data<SES> --query allowSharedKeyAccess -o tsv` renvoie `false`.
- [ ] `echo "$UD_URL"` affiche une URL contenant `skoid=` (variable conservée pour le défi 06.4).
- [ ] Les trois réponses de l'étape 8 sont rédigées.

---

## Défi 06.4 ⭐⭐⭐ — Compte de données invisible d'Internet (autonome)
**Durée** : 15 min en séance (lecture commentée de la solution pour les autres) · **Objectif** : restreindre l'accès réseau au compte par private endpoint, puis le prouver (objectif 7)
**Contexte** : l'audit de sécurité refuse tout point de terminaison public pour les données nominatives (signatures des clients). Les applications Arvéo des spokes doivent continuer à lire les preuves de livraison ; plus rien ne doit répondre depuis Internet, même avec un SAS valide. La configuration doit être versionnée et rejouable, comme celle des modules 4 et 5.

**Énoncé** :
1. Écrire `storage-private.bicep`, déployé dans `rg-st<NN>-data`, qui :
   - redéclare le compte de données dans son état actuel (RA-GRS, TLS 1.2, accès anonyme et clé partagée désactivés) et désactive son accès réseau public ;
   - crée le private endpoint `pe-st<NN>-blob` (sous-ressource `blob`) dans `snet-pe` du spoke données, avec une carte nommée `nic-st<NN>-pe-blob` ;
   - crée, dans `rg-st<NN>-hub` et par un module, la zone `privatelink.blob.core.windows.net` liée au hub et aux deux spokes ;
   - associe la zone au private endpoint par un groupe de zones DNS.
2. Contraintes :
   - deux paramètres obligatoires seulement : numéro de stagiaire et code de session ;
   - noms et identifiants calculés à partir de ces paramètres ;
   - `what-if` avant déploiement : sur le compte, seules les propriétés d'accès réseau changent ;
   - IP du private endpoint fournie en sortie du déploiement.
3. AVANT le déploiement : vérifier que `UD_URL` (exercice 06.3) est encore valide depuis Cloud Shell (`200`).
4. Déployer, puis prouver par cinq tests :
   - a. `vm-st<NN>-test-data` résout `starveost<NN>data<SES>.blob.core.windows.net` en `10.<OCT>.9.4` ;
   - b. `vm-st<NN>-test-data` télécharge `UD_URL` : code `200` ;
   - c. Cloud Shell télécharge `UD_URL` : code `403` ;
   - d. Cloud Shell liste les blobs de `pod` avec `--auth-mode login` : refus ;
   - e. Cloud Shell résout le même nom : chaîne de CNAME et adresse publique.
5. Répondre par écrit :
   - a. Pourquoi un SAS valide ne suffit-il plus depuis Internet (test c) ?
   - b. La réplication d'objets et le cycle de vie fonctionnent-ils encore ? Pourquoi ?
   - c. Que faudrait-il pour que le serveur de Lyon utilise ce private endpoint ?

**Critères de réussite** :
- [ ] `az bicep build --file storage-private.bicep` ne produit aucune erreur.
- [ ] `az storage account show -g rg-st<NN>-data -n starveost<NN>data<SES> --query publicNetworkAccess -o tsv` renvoie `Disabled`.
- [ ] `az network private-endpoint show -g rg-st<NN>-data -n pe-st<NN>-blob --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv` renvoie `Approved`.
- [ ] Les cinq tests donnent le résultat attendu.
- [ ] Redéploiement du fichier : `what-if` sans changement sur le compte, le private endpoint ni la zone.
- [ ] Les trois réponses de l'étape 5 sont rédigées.

---

## Lab 06.5 ⭐⭐ — Synchroniser le serveur de fichiers de Lyon (semi-autonome)
**Durée** : 35 min · **Objectif** : synchroniser un partage Azure Files avec le serveur de Lyon (objectif 7)
**Contexte** : le serveur de fichiers de Lyon (`\\vm-st<NN>-lyon-fs\Commun`, dossier `F:\Partages\Commun`) arrive en fin de vie. Arvéo veut un partage Azure Files comme référence, le serveur gardé comme cache local jusqu'à la fermeture du site, sans ouvrir aucun port entrant à Lyon ni rétablir le VPN.
**Prérequis** : préparation du serveur de Lyon terminée ; bloc de variables exécuté.

**Énoncé** :
1. Vérifier la fin de la préparation du serveur :
   ```bash
   ./scripts/labs/module-06/lyon-fs-prep.sh "$NN" --status
   ```
   Résultat attendu (version de l'agent et du module variables) :
   ```
   Etat       Debut                             Fin
   ---------  --------------------------------  --------------------------------
   Succeeded  2026-10-08T07:03:12.4458215+00:00  2026-10-08T07:14:55.1172040+00:00
   Volume F: 32 Go
   Partage \\vm-st07-lyon-fs\Commun : 19 fichiers
   Agent Azure File Sync : 20.0.0.0
   Module Az.StorageSync : 2.5.0
   PREPARATION TERMINEE
   ```
2. Créer le compte `starveost<NN>files<SES>` (Standard v2, LRS, TLS 1.2, accès anonyme désactivé, grands partages de fichiers activés, tags), puis le partage `partage-lyon` (quota 100 Gio, niveau optimisé pour les transactions).
3. Créer le service de synchronisation `sss-st<NN>` (France Central, tags).
4. **Portail** : dans `sss-st<NN>`, créer le groupe de synchronisation `sg-partage-lyon` avec son point de terminaison cloud (abonnement de formation, compte `starveost<NN>files<SES>`, partage `partage-lyon`).
5. Inscrire le serveur de Lyon dans `sss-st<NN>` par son identité managée : attribuer d'abord à cette identité le rôle Contributeur sur le seul service de synchronisation, puis lancer l'inscription sur le serveur. Vérifier la présence du serveur dans « Serveurs inscrits ».
6. **Portail** : ajouter au groupe le point de terminaison serveur `F:\Partages\Commun` de `vm-st<NN>-lyon-fs`, hiérarchisation cloud activée avec 20 % d'espace libre sur le volume.
7. Après 3 à 5 min, lister la racine du partage, puis le dossier `Exploitation`.
8. **Serveur → Azure** : créer `F:\Partages\Commun\RH\note-migration.txt` sur le serveur, puis vérifier son arrivée dans le partage.
9. **Azure → serveur** : déposer `Qualite/consigne-qualite.txt` directement dans le partage ; vérifier son absence sur le serveur, forcer la détection des changements sur le dossier `Qualite`, puis vérifier à nouveau.
10. Répondre par écrit :
    - a. Pourquoi aucun port entrant ni VPN n'est-il nécessaire à Lyon ?
    - b. Pourquoi un disque `F:` plutôt que le dossier `C:\Partages` ?
    - c. Sans détection forcée, quand `consigne-qualite.txt` serait-il apparu sur le serveur ?

**Indices** :
- Compte : `az storage account create ... --enable-large-file-share` ; partage : `az storage share-rm create --storage-account <COMPTE> -n <PARTAGE> --quota 100 --access-tier TransactionOptimized`.
- Service de synchronisation : `az storagesync create -g <GROUPE> -n <NOM> -l <REGION> --tags ...` (extension `storagesync` installée à la demande).
- Groupe : portail, `sss-st<NN>` › Groupes de synchronisation › + Groupe de synchronisation.
- Identité du serveur : `az vm show ... --query identity.principalId -o tsv` ; ID du service : `az storagesync show ... --query id -o tsv` ; rôle : `az role assignment create --assignee-object-id <ID> --assignee-principal-type ServicePrincipal --role Contributor --scope <ID_SERVICE>`.
- Inscription (propagation du rôle : 1 à 5 min) : `lyon "Connect-AzAccount -Identity -Subscription '<ID_ABONNEMENT>' | Out-Null; Register-AzStorageSyncServer -ResourceGroupName '<GROUPE>' -StorageSyncServiceName '<SERVICE>' | Select-Object FriendlyName, ServerId, AgentVersion | Format-List"`.
- Point de terminaison serveur : groupe `sg-partage-lyon` › + Ajouter un point de terminaison de serveur.
- Contenu du partage : `az storage file list --share-name partage-lyon --account-name <COMPTE> [--path <DOSSIER>] --query "[].name" -o tsv`.
- Fichier sur le serveur : `lyon "Set-Content F:\Partages\Commun\RH\note-migration.txt 'Migration Azure J3'"` ; test : `lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"`.
- Dépôt dans le partage : `az storage file upload --share-name partage-lyon --source <FICHIER> --path Qualite/consigne-qualite.txt --account-name <COMPTE>`.
- Détection forcée (sur le serveur, identité managée) : `Get-AzStorageSyncCloudEndpoint -ResourceGroupName ... -StorageSyncServiceName ... -SyncGroupName ...` puis `Invoke-AzStorageSyncChangeDetection -InputObject <POINT_CLOUD> -DirectoryPath 'Qualite' -Recursive`.

**Critères de réussite** :
- [ ] Portail, `sg-partage-lyon` : point de terminaison serveur à l'état d'intégrité sain (coche verte), dernière synchronisation récente.
- [ ] `az storage file list --share-name partage-lyon --account-name starveost<NN>files<SES> --path Exploitation --query "length(@)" -o tsv` renvoie `12`.
- [ ] `note-migration.txt` présent dans le dossier `RH` du partage.
- [ ] `lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"` renvoie `True` après la détection forcée.
- [ ] Les trois réponses de l'étape 10 sont rédigées.

---

## Lab 06.6 ⭐ — Exporter et synchroniser avec AzCopy (guidé)
**Durée** : 15 min · **Objectif** : transférer des données avec AzCopy et choisir une méthode de transfert (objectif 7)
**Contexte** : avant la fermeture de Lyon, la DSI exige une copie figée du partage dans le compte d'archive, et un dépôt différentiel quotidien des preuves de livraison numérisées localement. Elle prépare aussi le transfert des 40 To d'historique du datacenter.
**Prérequis** : lab 06.5 terminé (partage synchronisé), compte d'archive du lab 06.2.

### Étapes
1. Vérifier la version d'AzCopy de Cloud Shell.
   ```bash
   azcopy --version
   ```
   Résultat attendu (version variable) :
   ```
   azcopy version 10.30.1
   ```

2. Générer deux SAS de 2 h : lecture et liste sur le partage, puis SAS de compte d'archive (Blob, types `sco`, permissions `racwl`).
   ```bash
   END=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')
   KEY_F=$(az storage account keys list -g "$RG_DATA" -n "$SA_FILES" --query "[0].value" -o tsv)
   KEY_A=$(az storage account keys list -g "$RG_DATA" -n "$SA_ARCH" --query "[0].value" -o tsv)
   SAS_F=$(az storage share generate-sas -n partage-lyon --account-name "$SA_FILES" \
     --account-key "$KEY_F" --permissions rl --expiry "$END" --https-only -o tsv)
   SAS_B=$(az storage account generate-sas --account-name "$SA_ARCH" --account-key "$KEY_A" \
     --services b --resource-types sco --permissions racwl --expiry "$END" --https-only -o tsv)
   echo "${#SAS_F} ${#SAS_B}"
   ```
   Résultat attendu : deux longueurs non nulles (ex. `121 135`).

3. Copier le partage entier vers le compte d'archive (copie de compte à compte, côté serveur).
   ```bash
   azcopy copy "https://${SA_FILES}.file.core.windows.net/partage-lyon?${SAS_F}" \
     "https://${SA_ARCH}.blob.core.windows.net/?${SAS_B}" --recursive
   ```
   Résultat attendu (fin du résumé ; nombre de fichiers selon le lab 06.5) :
   ```
   Number of File Transfers: 21
   Number of File Transfers Completed: 21
   Number of File Transfers Failed: 0
   Final Job Status: Completed
   ```

4. Lister le conteneur créé (même nom que le partage).
   ```bash
   azcopy list "https://${SA_ARCH}.blob.core.windows.net/partage-lyon?${SAS_B}" | head -5
   ```
   Résultat attendu (ordre variable) :
   ```
   INFO: Exploitation/tournee-01.csv;  Content Length: 52.00 B
   INFO: Exploitation/tournee-02.csv;  Content Length: 52.00 B
   INFO: Qualite/audit-2024.bin;  Content Length: 100.00 MiB
   ```

5. Synchroniser le dossier local des preuves de livraison avec un conteneur `pod-sync`, modifier un fichier, puis synchroniser à nouveau.
   ```bash
   azcopy make "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}"
   azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
     | grep -E "Number of Copy Transfers Completed|Final Job Status"
   echo "Preuve de livraison 07 - RÉSERVE CLIENT" > "$WORK/pod/pod-007.txt"
   azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
     | grep -E "Number of Copy Transfers Completed|Final Job Status"
   ```
   Résultat attendu :
   ```
   Successfully created the resource.
   Number of Copy Transfers Completed: 20
   Final Job Status: Completed
   Number of Copy Transfers Completed: 1
   Final Job Status: Completed
   ```

6. **Portail** : ouvrir le « Navigateur de stockage » de `starveost<NN>arch<SES>`, parcourir `partage-lyon` puis `pod-replica`, et passer `Qualite/audit-2024.bin` en niveau Cold. Ouvrir ensuite le navigateur de stockage de `starveost<NN>data<SES>` et relever le message affiché.

7. Calculer la durée de transfert des 40 To d'historique de Lyon sur le lien Internet du site (100 Mbit/s), en supposant le lien saturé, puis à 70 % d'efficacité. Conclure : réseau ou Data Box, sachant que le datacenter ferme ses salles serveurs dans 3 semaines ?

### Critères de réussite
- [ ] `azcopy list ".../partage-lyon?$SAS_B" | wc -l` renvoie le nombre de fichiers du partage.
- [ ] La seconde synchronisation transfère exactement `1` fichier.
- [ ] `az storage blob show --account-name starveost<NN>arch<SES> -c partage-lyon -n Qualite/audit-2024.bin --auth-mode key --query properties.blobTier -o tsv` renvoie `Cold`.
- [ ] Le message du navigateur de stockage du compte de données est relevé et expliqué.
- [ ] Le calcul de l'étape 7 et la conclusion sont rédigés.

---

## Bonus 🚀
1. **Hiérarchisation forcée** : sur le serveur de Lyon, forcer la hiérarchisation de `F:\Partages\Commun\Qualite\audit-2024.bin` (cmdlet `Invoke-StorageSyncCloudTiering` du module de l'agent, `C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll`). Comparer ses attributs et l'espace occupé sur le volume avant et après, puis rappeler le fichier (`Invoke-StorageSyncFileRecall`).
2. **Compte de fichiers restreint** : limiter `starveost<NN>files<SES>` aux réseaux sélectionnés (IP publique de sortie du site de Lyon, communiquée par la formatrice, et exception des services Microsoft approuvés). Vérifier que la synchronisation continue (fichier créé sur le serveur), puis que Cloud Shell ne liste plus le partage. Rétablir ensuite l'accès pour le lab 06.6 ou la suite. `[À VÉRIFIER]` prérequis réseau d'Azure File Sync avec pare-feu de stockage.
3. **Bicep complet** : lire `scripts/catch-up/module-06/main.bicep`, identifier les ressources du lab 06.5 (service, groupe, points de terminaison, rôles) et expliquer pourquoi la règle de réplication d'objets est créée par Azure CLI dans `deploy.sh` plutôt qu'en Bicep.

## Nettoyage
- **Fin de matinée (12:28)** :
  ```bash
  ./scripts/cleanup/module-06-storage.sh "$NN"
  ```
  Arrête (deallocate) `vm-st<NN>-lyon-fs`, `vm-st<NN>-test-data` et `vm-st<NN>-test-web`. Relançable sans risque.
- Conservés : comptes de stockage, private endpoint, zone DNS, service de synchronisation, serveur inscrit, disque de données (réutilisés aux modules 8, 9 et 10).
- Suppression complète du stockage en fin de formation : `./scripts/cleanup/module-06-storage.sh <NN> --purge` (points de terminaison, serveur inscrit, service de synchronisation, private endpoint, comptes).
- Côté Lyon (formatrice) : passerelle NAT `natgw-lyon` conservée jusqu'au module 9 (agent MARS), supprimée en fin de J4 (`lyon-nat.sh cleanup`).
- Rattrapage complet du module : `./scripts/catch-up/module-06/deploy.sh <NN> <SES>` (15 à 25 min).
- Coûts : stockage au Go et aux opérations (négligeable en lab), réplication géographique et réplication d'objets (Go transférés), private endpoint à l'heure et au Go traité, disque StandardSSD 32 Go, VM Windows B2s_v2 tant qu'elle tourne, passerelle NAT partagée à l'heure `[À VÉRIFIER]` calculatrice de prix Azure.
