# Module 09 — Exercices

Fil rouge : **plan de sauvegarde et de reprise d'Arvéo**. Un coffre Recovery Services unique protège les deux serveurs du portail client (sauvegarde de VM, stratégie Améliorée), le partage `partage-lyon` migré au module 6 (instantanés gérés par le coffre) et les exports comptables du serveur de Lyon, non migrés (agent MARS). Chaque protection est prouvée par une restauration : fichier du partage, dossier du serveur de Lyon, données puis système de `web01`. Les travaux de sauvegarde alimentent la supervision du module 10.

| Ressource | Nom (stagiaire 07, session `2610`) | Groupe | Lab |
|---|---|---|---|
| Coffre Recovery Services | `rsv-st07-arveo` (France Central, stockage LRS) | `rg-st07-shared` | 09.1 (script de 09:00) |
| Stratégie des VMs | `pol-vm-arveo` (Améliorée, 22:00, instantanés 7 j, 30 j + 12 semaines) | `rg-st07-shared` | 09.1 |
| VMs protégées | `vm-st07-web01` (script de 09:00), `vm-st07-web02` | `rg-st07-app` | 09.1 |
| Stratégie et partage protégé | `pol-files-arveo`, `partage-lyon` de `starveost07files2610` | `rg-st07-shared` / `rg-st07-data` | 09.2 |
| Serveur protégé par MARS | `vm-st07-lyon-fs`, dossier `F:\Compta` | `rg-st07-lyon` | 09.3 |
| Disques restaurés (temporaires) | disque OS et disque LUN 0 de `web01`, noms générés | `rg-st07-app` | 09.4 |

Variables utilisées dans tous les labs :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<SES>` = code de session à 4 caractères du module 6 (ex. `2610`)
- `<URL_DEPOT>` = adresse du dépôt Git de la formation, communiquée par la formatrice

Tags obligatoires sur chaque ressource (stratégie du module 2) : `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

**Bloc de variables** : à recoller dans Cloud Shell (Bash) au début de CHAQUE lab (session fermée après 20 min d'inactivité).
```bash
NN=<NN>
SES=<SES>
OCT=$((10#$NN))
ST="st${NN}"
RG_SHARED="rg-${ST}-shared"
RG_APP="rg-${ST}-app"
RG_DATA="rg-${ST}-data"
RG_LYON_ST="rg-${ST}-lyon"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
VAULT="rsv-${ST}-arveo"
SA_FILES="starveost${NN}files${SES}"
DIAG_SA=$(az storage account list -g "$RG_SHARED" \
  --query "[?starts_with(name, 'starveost${NN}diag')].name | [0]" -o tsv)   # module 3
az config set extension.use_dynamic_install=yes_without_prompt -o none
cd ~/formation 2>/dev/null || git clone <URL_DEPOT> ~/formation && cd ~/formation
vmrun() {   # vmrun <web01|web02> "<COMMANDE BASH>" : exécution sur vm-stNN-<nom> (rg-stNN-app)
  az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
lyon() {    # lyon "<COMMANDE POWERSHELL>" : exécution sur vm-stNN-lyon-fs
  az vm run-command invoke -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" \
    --command-id RunPowerShellScript --scripts "$1" \
    --query "value[0].message" -o tsv
}
bkitem() {  # bkitem <VM|AzureFileShare> <NOM> : noms internes CONT et ITEM d'un élément protégé
  local BMT=AzureIaasVM; [[ "$1" == "AzureFileShare" ]] && BMT=AzureStorage
  read -r CONT ITEM < <(az backup item list -g "$RG_SHARED" -v "$VAULT" \
    --backup-management-type "$BMT" --workload-type "$1" \
    --query "[?properties.friendlyName=='$2'] | [0].[properties.containerName, name]" -o tsv)
  echo "CONT=${CONT} ITEM=${ITEM}"
}
echo "$ST $VAULT $SA_FILES $DIAG_SA"
```
Résultat attendu (stagiaire 07, session `2610` ; nom du compte de diagnostic avec suffixe éventuel du module 3) :
```
st07 rsv-st07-arveo starveost07files2610 starveost07diag
```

**État de départ** : fin du module 7 pour le calcul, VMs `web01` et `web02` redémarrées au début du jour 4 (portail v2 servi par `lbe-st<NN>-web`, disque de données de `web01` monté sur `/srv/arveo`) ; fin du module 6 pour le stockage (`partage-lyon` synchronisé avec `F:\Partages\Commun` du serveur de Lyon, serveur arrêté en fin de matinée du J3) ; passerelle NAT `natgw-lyon` de la formatrice active jusqu'à la fin du J4. Le module 9 n'utilise aucune ressource du module 8. Stagiaire en retard : `./scripts/catch-up/module-09/deploy.sh <NN> <SES>` (15 à 25 min, sauvegardes comprises) produit l'état de FIN du module 9.

---

## Lab 09.1 ⭐ — Coffre Arvéo, stratégie Améliorée, protection de `web02` (guidé)
**Durée** : 5 min en séance (+ 2 min à 09:00) · **Objectif** : configurer un coffre Recovery Services et une stratégie conformes au besoin d'Arvéo, puis protéger une VM (objectif 10)
**Contexte** : la DSI d'Arvéo fixe pour le portail client un RPO de 24 h, une rétention de 30 jours et de 12 semaines, et une restauration en quelques minutes pendant une semaine. La sauvegarde initiale d'une VM prenant du temps, le coffre et la protection de `web01` ont été lancés dès 09:00 par script ; le lab en vérifie le résultat et protège `web02`.
**Prérequis** : bloc de variables exécuté ; état de départ conforme.

### Étapes
1. **(J4, 09:00, au démarrage du module 8)** Lancer la préparation de la sauvegarde (2 min, sauvegarde de `web01` en arrière-plan) :
   ```bash
   ./scripts/labs/module-09/lancer-sauvegarde.sh "$NN"
   ```
   Résultat attendu (date de conservation et identifiant variables) :
   ```
   == Démarrage des VMs
      vm-st07-web01 : démarrée
      vm-st07-web02 : démarrée
      vm-st07-lyon-fs : démarrage lancé (agent MARS, lab 09.3)
   == Données métier de web01 (/srv/arveo/contrats)
      5 fichiers dans /srv/arveo/contrats
   == Coffre rsv-st07-arveo (rg-st07-shared, francecentral)
      créé ; stockage de sauvegarde : LocallyRedundant
   == Stratégie pol-vm-arveo (Améliorée, 22:00, instantanés 7 j)
      créée
   == Protection de vm-st07-web01
      protection activée
   == Sauvegarde immédiate de vm-st07-web01 (conservée jusqu'au 07-11-2026)
      travail lancé : <ID_TRAVAIL>
   Suivi : az backup job list -g rg-st07-shared -v rsv-st07-arveo -o table
   ```

2. **(11:10)** Lire la configuration du stockage et de la sécurité du coffre :
   ```bash
   Q="{Stockage:[0].properties.storageModelType, Etat:[0].properties.storageTypeState,"
   Q="$Q CRR:[0].properties.crossRegionRestoreFlag, SuppReversible:[1].properties.softDeleteFeatureState}"
   az backup vault backup-properties show -g "$RG_SHARED" -n "$VAULT" --query "$Q" -o table
   ```
   Résultat attendu :
   ```
   Stockage          Etat    CRR    SuppReversible
   ----------------  ------  -----  ----------------
   LocallyRedundant  Locked  False  Enabled
   ```
   `Locked` : un élément est protégé, la redondance du coffre ne peut plus changer.

3. Lire la stratégie `pol-vm-arveo` et son fichier source :
   ```bash
   az backup policy show -g "$RG_SHARED" -v "$VAULT" -n pol-vm-arveo \
     --query "{Type:properties.policyType, Frequence:properties.schedulePolicy.scheduleRunFrequency, Instantanes:properties.instantRpRetentionRangeInDays, Jours:properties.retentionPolicy.dailySchedule.retentionDuration.count, Semaines:properties.retentionPolicy.weeklySchedule.retentionDuration.count}" \
     -o table
   grep -E '"(scheduleRunTimes|timeZone|daysOfTheWeek)"' -A1 scripts/labs/module-09/pol-vm-arveo.json
   ```
   Résultat attendu (première commande) :
   ```
   Type    Frequence    Instantanes    Jours    Semaines
   ------  -----------  -------------  -------  ----------
   V2      Daily        7              30       12
   ```

4. Suivre les travaux du coffre :
   ```bash
   az backup job list -g "$RG_SHARED" -v "$VAULT" -o table \
     --query "[].{Element:properties.entityFriendlyName, Operation:properties.operation, Etat:properties.status, Debut:properties.startTime}"
   ```
   Résultat attendu (la sauvegarde de `web01` peut encore être `InProgress`) :
   ```
   Element        Operation        Etat        Debut
   -------------  ---------------  ----------  --------------------------------
   vm-st07-web01  Backup           InProgress  2026-10-08T07:03:41.118230+00:00
   vm-st07-web01  ConfigureBackup  Completed   2026-10-08T07:02:55.402871+00:00
   ```

5. Protéger `web02` avec la même stratégie, puis lancer sa première sauvegarde :
   ```bash
   VM02_ID=$(az vm show -g "$RG_APP" -n "vm-${ST}-web02" --query id -o tsv)
   az backup protection enable-for-vm -g "$RG_SHARED" -v "$VAULT" \
     --vm "$VM02_ID" --policy-name pol-vm-arveo -o none
   bkitem VM "vm-${ST}-web02"
   az backup protection backup-now -g "$RG_SHARED" -v "$VAULT" \
     --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
     --retain-until "$(date -d '+30 days' +%d-%m-%Y)" --query "properties.status" -o tsv
   ```
   Résultat attendu (1 à 2 min ; format exact des noms internes `[À VÉRIFIER]`) :
   ```
   CONT=iaasvmcontainerv2;rg-st07-app;vm-st07-web02 ITEM=VM;iaasvmcontainerv2;rg-st07-app;vm-st07-web02
   InProgress
   ```

6. Préparer le lab 09.3 : attribuer à l'identité managée du serveur de Lyon (créée au module 6) le rôle « Contributeur de sauvegarde » sur le SEUL coffre, puis lancer l'installation de l'agent MARS en arrière-plan (10 à 15 min) :
   ```bash
   LYON_MI=$(az vm show -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" --query identity.principalId -o tsv)
   VAULT_ID=$(az backup vault show -g "$RG_SHARED" -n "$VAULT" --query id -o tsv)
   az role assignment create --assignee-object-id "$LYON_MI" \
     --assignee-principal-type ServicePrincipal --role "Backup Contributor" \
     --scope "$VAULT_ID" --query roleDefinitionName -o tsv
   ./scripts/labs/module-09/mars-lyon.sh "$NN"
   ```
   Résultat attendu :
   ```
   Backup Contributor
   == Serveur vm-st07-lyon-fs
      en fonctionnement
   == Phrase secrète MARS
      générée : /home/<UTILISATEUR>/.arveo/mars-passphrase.txt (32 caractères)
   == Installation et inscription de l'agent MARS (commande d'exécution managée mars-install)
      mars-install lancée en arrière-plan (10 à 15 min)
   Suivi : ./scripts/labs/module-09/mars-lyon.sh 07 --status
   ```

### Critères de réussite
- [ ] `az backup vault backup-properties show -g rg-st<NN>-shared -n rsv-st<NN>-arveo --query "[0].properties.storageModelType" -o tsv` renvoie `LocallyRedundant`.
- [ ] `az backup item list -g rg-st<NN>-shared -v rsv-st<NN>-arveo --backup-management-type AzureIaasVM --query "[].{VM:properties.friendlyName, Strategie:properties.policyName}" -o table` affiche `web01` et `web02` avec `pol-vm-arveo`.
- [ ] Un travail `Backup` existe pour chaque VM (`InProgress` ou `Completed`).
- [ ] `mars-lyon.sh <NN> --status` affiche une exécution `Running` ou `Succeeded`.

---

## Lab 09.2 ⭐⭐ — Sauvegarder et restaurer le partage `partage-lyon` (semi-autonome)
**Durée** : 10 min · **Objectif** : sauvegarder un partage Azure Files avec le coffre et restaurer un fichier supprimé (objectif 10)
**Contexte** : depuis le module 6, `partage-lyon` est la copie de référence du serveur de fichiers de Lyon ; File Sync propage AUSSI les suppressions. Exigence : RPO de 24 h, rétention de 30 jours, restauration d'un fichier par le support en moins d'une heure, sans dépendre du serveur de Lyon.
**Prérequis** : lab 09.1 terminé ; partage synchronisé (module 6).

**Énoncé** :
1. Lire `scripts/labs/module-09/pol-files-arveo.json` : heure de sauvegarde, fuseau horaire, rétention.
2. Créer la stratégie `pol-files-arveo` dans le coffre à partir de ce fichier.
3. Protéger le partage `partage-lyon` du compte `starveost<NN>files<SES>` avec cette stratégie.
4. Lister les verrous du compte de stockage : relever le nom, le niveau et le créateur du verrou apparu.
5. Lancer une sauvegarde immédiate du partage (conservée 30 jours), attendre la fin du travail, puis lister les instantanés du partage.
6. Simuler l'erreur d'un utilisateur de Lyon (fourni) :
   ```bash
   az storage file delete --share-name partage-lyon --path Exploitation/tournee-03.csv \
     --account-name "$SA_FILES" -o none
   az storage file list --share-name partage-lyon --account-name "$SA_FILES" \
     --path Exploitation --query "length(@)" -o tsv
   ```
   Résultat attendu : `11` (un fichier de moins qu'au module 6).
7. Restaurer `Exploitation/tournee-03.csv` seul, à l'emplacement d'origine, depuis le point de récupération créé à l'étape 5. Vérifier sa présence dans le partage, puis, 2 à 5 min plus tard, sur le serveur de Lyon.
8. Répondre par écrit :
   - a. Où sont physiquement stockées les données du point de récupération ? Que deviendraient-elles si le compte de stockage était supprimé ?
   - b. Pourquoi Azure Backup pose-t-il un verrou sur le compte ? Quel script de nettoyage d'un module précédent en est affecté ?
   - c. Pourquoi sauvegarder le partage plutôt que `F:\Partages\Commun` sur le serveur de Lyon ?

**Indices** :
- Stratégie : `az backup policy create --backup-management-type AzureStorage --workload-type AzureFileShare --policy @<FICHIER>`.
- Protection : `az backup protection enable-for-azurefileshare --policy-name --storage-account --azure-file-share` (enregistre aussi le compte auprès du coffre ; 1 à 2 min).
- Verrous : `az lock list -g rg-st<NN>-data --query "[].{Nom:name, Niveau:level, Notes:notes}" -o table`.
- Noms internes : `bkitem AzureFileShare partage-lyon`.
- Sauvegarde : `az backup protection backup-now --backup-management-type AzureStorage --retain-until <JJ-MM-AAAA>` ; attente : `az backup job wait -n <ID_TRAVAIL>`.
- Instantanés : `az storage share list --account-name <COMPTE> --include-snapshots --query "[?name=='partage-lyon'].snapshot" -o tsv`.
- Points : `az backup recoverypoint list --backup-management-type AzureStorage --query "sort_by(@, &properties.recoveryPointTime)[-1].name" -o tsv`.
- Restauration : `az backup restore restore-azurefiles --restore-mode OriginalLocation --resolve-conflict Overwrite --source-file-type File --source-file-path <CHEMIN>`.
- Serveur : `lyon "Test-Path F:\Partages\Commun\Exploitation\tournee-03.csv"`.

**Critères de réussite** :
- [ ] `az backup item list -g rg-st<NN>-shared -v rsv-st<NN>-arveo --backup-management-type AzureStorage --workload-type AzureFileShare --query "[0].properties.[friendlyName, policyName]" -o tsv` renvoie `partage-lyon` et `pol-files-arveo`.
- [ ] Le verrou `AzureBackupProtectionLock` (niveau `CanNotDelete`) est présent sur le compte.
- [ ] Au moins un instantané de `partage-lyon` existe.
- [ ] Après restauration, le dossier `Exploitation` du partage compte de nouveau `12` fichiers et `Test-Path` renvoie `True` sur le serveur.
- [ ] Les trois réponses de l'étape 8 sont rédigées.

---

## Lab 09.3 ⭐⭐ — Agent MARS sur le serveur de Lyon (semi-autonome)
**Durée** : 15 min · **Objectif** : sauvegarder et restaurer un dossier d'un serveur sur site avec l'agent MARS (objectif 10)
**Contexte** : jusqu'à la fermeture de Lyon (6 mois), l'ancienne application comptable dépose chaque jour ses exports dans `F:\Compta` sur le serveur de fichiers. Ce dossier n'est PAS synchronisé avec Azure Files. La bande LTO hebdomadaire est arrêtée : la comptabilité exige une sauvegarde chaque soir de semaine à 21:00, conservée 30 jours, sans port entrant ni VPN vers Lyon.
**Prérequis** : lab 09.1 étape 6 lancé (agent installé et inscrit) ; bloc de variables exécuté.

**Énoncé** :
1. Vérifier la fin de l'installation :
   ```bash
   ./scripts/labs/module-09/mars-lyon.sh "$NN" --status
   ```
   Résultat attendu (versions et dates variables) :
   ```
   Etat       Debut                             Fin
   ---------  --------------------------------  --------------------------------
   Succeeded  2026-10-08T09:13:20.0145213+00:00  2026-10-08T09:24:51.7745130+00:00
   Dossier F:\Compta : 6 fichiers
   Agent MARS : 2.0.xxxxx.0
   Inscription : rsv-st07-arveo
   MARS PRET
   ```
2. **Portail** : coffre `rsv-st<NN>-arveo` › **Infrastructure de sauvegarde** › **Serveurs protégés** › **Agent Azure Backup** : relever le nom du serveur inscrit et son état.
3. Sur le serveur, par la fonction `lyon`, définir la stratégie MARS : dossier `F:\Compta`, du lundi au vendredi à 21:00, rétention de 30 jours. Afficher ensuite la stratégie appliquée.
4. Lancer une sauvegarde immédiate selon cette stratégie, puis vérifier, dans le coffre, l'élément sauvegardé et le travail correspondant (portail : **Éléments de sauvegarde** › **Agent Azure Backup** ; **Travaux de sauvegarde**).
5. Simuler une suppression (fournie) :
   ```bash
   lyon "Remove-Item F:\Compta\export-2026-09-30.csv; (Get-ChildItem F:\Compta).Count"
   ```
   Résultat attendu : `5`.
6. Restaurer `export-2026-09-30.csv` depuis le point de récupération de l'étape 4 dans `F:\Restauration`, puis le recopier dans `F:\Compta` et vérifier que le dossier compte de nouveau 6 fichiers.
7. Répondre par écrit :
   - a. Où la phrase secrète est-elle conservée ? Pourquoi ne doit-elle jamais être stockée uniquement sur le serveur protégé ?
   - b. Quelles opérations exigeront le PIN de sécurité du coffre ?
   - c. Pourquoi le rôle « Contributeur de sauvegarde » sur le coffre seul, plutôt que Contributeur sur `rg-st<NN>-shared` ?

**Indices** :
- Module : `Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'` en tête de chaque appel `lyon` (session PowerShell neuve à chaque appel).
- Stratégie : `New-OBPolicy`, `New-OBFileSpec -FileSpec @('F:\Compta')`, `Add-OBFileSpec`, `New-OBSchedule -DaysOfWeek ... -TimesOfDay 21:00`, `Set-OBSchedule`, `New-OBRetentionPolicy -RetentionDays 30`, `Set-OBRetentionPolicy`, `Set-OBPolicy -Confirm:$false` ; lecture : `Get-OBPolicy | Get-OBSchedule`, `Get-OBPolicy | Get-OBFileSpec`.
- Sauvegarde : `Get-OBPolicy | Start-OBBackup` (synchrone : 1 à 3 min) ; dernier travail : `Get-OBJob -Previous 1`.
- Restauration : `Get-OBRecoverableSource` (volumes sauvegardés), `Get-OBRecoverableItem -Source <SOURCE>` (points, propriété `PointInTime`), `Get-OBRecoverableItem -RecoveryPoint <POINT> -Location 'F:\Compta' -SearchString '<NOM>'`, `New-OBRecoveryOption -DestinationPath 'F:\Restauration' -OverwriteType Overwrite`, `Start-OBRecovery -RecoverableItem <ELEMENT> -RecoveryOption <OPTION>`.
- Plusieurs lignes PowerShell : les écrire dans un fichier de Cloud Shell, puis `lyon "$(cat <FICHIER>)"`.
- Chemin restauré : l'agent recrée l'arborescence d'origine sous le dossier cible `[À VÉRIFIER]` (`Get-ChildItem F:\Restauration -Recurse`).

**Critères de réussite** :
- [ ] `lyon "Import-Module '<CHEMIN_MODULE>'; (Get-OBPolicy | Get-OBFileSpec).FileName"` renvoie `F:\Compta`.
- [ ] Le portail affiche `F:\` (ou `F:\Compta`) parmi les éléments de l'agent Azure Backup, avec un point de récupération.
- [ ] `lyon "(Get-ChildItem F:\Compta).Count"` renvoie `6` après la restauration.
- [ ] Les trois réponses de l'étape 7 sont rédigées.

---

## Lab 09.4 ⭐⭐ — Récupérer les contrats de `web01` par restauration de disque (semi-autonome)
**Durée** : 15 min · **Objectif** : restaurer les données d'une VM depuis un point de récupération sans interrompre la VM (objectif 10)
**Contexte** : à 11:55, un script de purge mal paramétré a supprimé le dossier `/srv/arveo/contrats` de `web01` (contrats-cadres des transporteurs, publiés par le portail). Le portail doit rester en service ; seules les données doivent revenir, telles qu'au point de 09:00.
**Prérequis** : sauvegarde de `web01` terminée ou au moins au niveau instantané ; bloc de variables exécuté.

**Énoncé** :
1. Simuler l'incident (fourni) :
   ```bash
   vmrun web01 "ls /srv/arveo/contrats | wc -l; rm -rf /srv/arveo/contrats; ls /srv/arveo"
   ```
   Résultat attendu : `5`, puis le contenu de `/srv/arveo` sans `contrats` (`lost+found`).
2. Lister les points de récupération de `web01` avec leur date et leur niveau (`InstantRP`, `HardenedRP`). Retenir le plus récent.
3. Restaurer les disques de ce point (disque de données du LUN 0) dans `rg-st<NN>-app`, avec `$DIAG_SA` comme compte intermédiaire. Suivre le travail jusqu'à `Completed`.
4. Identifier les disques restaurés (disques non attachés de `rg-st<NN>-app`) : nom, zone, taille.
5. Attacher le disque de données restauré à `web01` au LUN 1, le monter en LECTURE SEULE sur `/mnt/restauration`, recopier `contrats` dans `/srv/arveo`, vérifier les 5 fichiers.
6. Démonter, détacher, puis supprimer TOUS les disques restaurés (disque OS compris).
7. Répondre par écrit :
   - a. Pourquoi ne pas avoir utilisé « Remplacer l'existant » ou la récupération de fichiers ?
   - b. Dans quelle zone le disque restauré a-t-il été créé ? Aurait-il pu être attaché à `web02` ?
   - c. Quelles données auraient été perdues si un contrat avait été ajouté à 10:30 ?

**Indices** :
- Noms internes : `bkitem VM "vm-${ST}-web01"`.
- Points : `az backup recoverypoint list --backup-management-type AzureIaasVM --workload-type VM` ; niveau : `join(',', properties.recoveryPointTierDetails[].type)` ; plus récent : `sort_by(@, &properties.recoveryPointTime)[-1].name`.
- Restauration : `az backup restore restore-disks --rp-name <POINT> --storage-account <COMPTE> --target-resource-group <GROUPE> --diskslist 0 --query name -o tsv` (renvoie l'ID du travail) ; suivi : `az backup job wait -n <ID_TRAVAIL>` puis `az backup job show -n <ID_TRAVAIL> --query properties.status`.
- Disques non attachés : `az disk list -g <GROUPE> --query "[?managedBy==null].{Nom:name, Zone:zones[0], Go:diskSizeGB}" -o table`.
- Attachement : `az vm disk attach --name <DISQUE> --lun 1` ; périphérique : `lsblk -o NAME,HCTL,SIZE,LABEL,MOUNTPOINT` (LUN = dernier nombre de `HCTL`) ou `/dev/disk/azure/scsi1/lun1-part1`.
- Montage : `mkdir -p /mnt/restauration && mount -o ro <PARTITION> /mnt/restauration` ; copie : `cp -a`.
- Les deux disques portent l'étiquette `arveo-data` : jamais de redémarrage de `web01` avec les deux disques attachés (montage `LABEL=` ambigu).

**Critères de réussite** :
- [ ] Le travail `Restore` de `vm-st<NN>-web01` est `Completed`.
- [ ] `vmrun web01 "ls /srv/arveo/contrats | wc -l; findmnt -no SOURCE /mnt/restauration"` renvoie `5` et aucune source montée.
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web01 --query "length(storageProfile.dataDisks)"` renvoie `1`.
- [ ] `az disk list -g rg-st<NN>-app --query "[?managedBy==null] | length(@)"` renvoie `0`.
- [ ] Les trois réponses de l'étape 7 sont rédigées.

---

## Défi 09.5 ⭐⭐⭐ — Retour arrière de `web01` après une mise à jour ratée (autonome)
**Durée** : 15 min en séance (déroulé commenté pour les autres) · **Objectif** : restaurer le système d'une VM depuis un point de récupération en conservant son identité réseau, et choisir le service de reprise adapté (objectif 10)
**Contexte** : une mise à jour manuelle du portail « v3 » sur `web01` a cassé la configuration nginx : `web01` répond `500`, la sonde du Load Balancer l'a retirée du pool. Personne ne sait annuler la modification. Le chef d'exploitation décide un retour au point de sauvegarde de 09:00, sans nouvelle VM : même nom, même IP, même place dans `bp-web`. Le portail ne doit pas s'interrompre pendant l'opération.

Simulation de la mise à jour ratée (fournie) :
```bash
vmrun web01 "printf 'server { listen 80 default_server; return 500; }\n' \
  > /etc/nginx/sites-enabled/default && systemctl reload nginx && curl -s -o /dev/null -w '%{http_code}\n' localhost"
```
Résultat attendu : `500`.

**Exigences** :

| Élément | Exigence |
|---|---|
| Point de restauration | Point de `web01` le plus récent ANTÉRIEUR à la mise à jour ratée |
| Type de restauration | Remplacement des disques existants, compte intermédiaire `starveost<NN>diag` |
| Identité réseau | `nic-st<NN>-web01`, IP `10.<OCT>.4.11`, appartenance à `bp-web` inchangées |
| Continuité | Portail servi par `lbe-st<NN>-web` pendant toute l'opération, sans erreur HTTP |
| Traçabilité | Procédure (runbook) de 5 à 8 étapes, RTO mesuré du lancement au retour de `web01` dans le pool |

**Énoncé** :
1. Avant toute restauration, lancer depuis Cloud Shell une boucle de contrôle du portail (une requête toutes les 2 s, code HTTP et serveur ayant répondu), conservée dans un fichier.
2. Réaliser la restauration (portail ou CLI), puis prouver le résultat par quatre contrôles :
   - a. `web01` répond de nouveau `200` en local avec la page v2 ;
   - b. la carte, l'IP et l'appartenance au pool sont inchangées ;
   - c. la boucle n'a enregistré aucune erreur et montre le retour de `web01` ;
   - d. les disques de `web01` après restauration sont identifiés (noms, date de création) et l'état de `/srv/arveo/contrats` est expliqué.
3. Rédiger la procédure et le RTO mesuré.
4. Répondre par écrit :
   - a. Quel RPO effectif pour `web01` ce matin ? Que faudrait-il changer pour un RPO de 4 h ?
   - b. France Central devient indisponible : le coffre actuel permet-il de restaurer `web01` ailleurs ? Que faudrait-il avoir configuré, et quand ?
   - c. L'ERP d'Arvéo exige un RPO de 15 min et un RTO d'1 h en cas de perte de la région. Proposer l'architecture de reprise (service, région cible, test annuel) et expliquer pourquoi la sauvegarde reste nécessaire.

**Critères de réussite** :
- [ ] Le dernier travail `Restore` de `vm-st<NN>-web01` est `Completed` (type de restauration : remplacement des disques).
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web01 -d --query "[privateIps, networkProfile.networkInterfaces[0].id]" -o tsv` montre `10.<OCT>.4.11` et `nic-st<NN>-web01`.
- [ ] `curl -s http://<IP_LB>/` répond depuis `web01` ET `web02` ; le fichier de la boucle ne contient aucun code différent de `200`.
- [ ] La procédure, le RTO mesuré et les trois réponses de l'étape 4 sont rédigés.

---

## Bonus 🚀
1. **Suppression réversible** : arrêter la protection de `web02` AVEC suppression des données, observer l'état de l'élément (`az backup item show ... --query properties.isScheduledForDeferredDelete`), puis annuler la suppression (`az backup protection undelete`) et reprendre la protection (`az backup protection resume`, stratégie `pol-vm-arveo`). Expliquer ce qu'un attaquant détenant le rôle Contributeur sur le coffre aurait pu faire sans cette fonction.
2. **Récupération de fichiers (ILR)** : portail, coffre › élément `vm-st<NN>-web02` › **Récupération de fichiers** : télécharger le script Python du dernier point, l'exécuter sur `web02` par Bastion (`scripts/labs/module-07/bastion.sh` si Bastion a été supprimé) ou par `vmrun` `[À VÉRIFIER]` saisie du mot de passe non interactive, parcourir les volumes montés, puis **Démonter les disques**. Comparer durée et risques avec le lab 09.4.
3. **Blobs `pod` (module 6)** : créer un coffre de sauvegarde (Backup vault) `bvault-st<NN>-arveo` dans `rg-st<NN>-shared`, attribuer à son identité le rôle « Storage Account Backup Contributor » sur `starveost<NN>data<SES>`, puis configurer la sauvegarde opérationnelle du compte (portail : coffre de sauvegarde › **Sauvegarde** › **Blobs Azure**). Expliquer ce qu'elle ajoute au versioning et à la suppression réversible du module 6.
4. **Rapports** : créer un paramètre de diagnostic du coffre vers `log-st<NN>-shared` (catégories `AddonAzureBackupJobs`, `CoreAzureBackup`, mode spécifique à la ressource), puis, 15 à 30 min plus tard, interroger la table `AddonAzureBackupJobs` (préparation du module 10).

## Nettoyage
- **Fin de matinée du J4 (12:28)** :
  ```bash
  ./scripts/cleanup/module-09-backup.sh "$NN"
  ```
  Le script désalloue le serveur de Lyon et supprime les disques non attachés de `rg-st<NN>-app` (disques restaurés oubliés), sauf pendant une restauration en cours (défi 09.5 : relancer après la fin du travail). Relançable sans risque.
- Conservés jusqu'à la fin de la formation : coffre, stratégies, éléments protégés et points de récupération (travaux et alertes exploités au module 10).
- **Fin de formation**, AVANT le nettoyage complet du stockage (`module-06-storage.sh --purge`) :
  ```bash
  ./scripts/cleanup/module-09-backup.sh "$NN" --purge
  ```
  Désactive la suppression réversible, arrête toutes les protections avec suppression des données, désinscrit le compte de stockage (le verrou `AzureBackupProtectionLock` disparaît), supprime le serveur MARS inscrit, les stratégies puis le coffre. Sans `--purge` préalable, la suppression du compte de fichiers échoue (verrou) et le coffre reste bloqué 14 jours (suppression réversible).
- Bonus 3 : supprimer `bvault-st<NN>-arveo` (arrêt de la protection d'abord).
- Rattrapage complet du module : `./scripts/catch-up/module-09/deploy.sh <NN> <SES>`.
- Coûts : instance protégée facturée au mois selon la taille protégée (VM, partage, serveur MARS), stockage du coffre au Go (LRS), instantanés de disques et de partage au Go, VM Windows B2s_v2 tant qu'elle tourne `[À VÉRIFIER]` calculatrice de prix Azure.
