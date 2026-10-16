# Module 09 — Corrections

Toutes les commandes supposent le bloc de variables des exercices exécuté (`NN`, `SES`, `ST`, `RG_*`, `VAULT`, `SA_FILES`, `DIAG_SA`, fonctions `vmrun`, `lyon`, `bkitem`). Les sorties sont données pour le stagiaire `07`, session `2610`.

---

## Lab 09.1 ⭐ — Coffre Arvéo, stratégie Améliorée, protection de `web02`

### Solution
Les étapes du lab sont complètes. Contrôles finaux :
```bash
az backup vault backup-properties show -g "$RG_SHARED" -n "$VAULT" \
  --query "[0].properties.storageModelType" -o tsv
az backup item list -g "$RG_SHARED" -v "$VAULT" --backup-management-type AzureIaasVM \
  --query "[].{VM:properties.friendlyName, Strategie:properties.policyName, Etat:properties.protectionState}" -o table
./scripts/labs/module-09/mars-lyon.sh "$NN" --status
```
Sortie attendue (état de protection `IRPending` tant que la première sauvegarde n'est pas terminée `[À VÉRIFIER]` libellé) :
```
LocallyRedundant
VM             Strategie     Etat
-------------  ------------  ---------
vm-st07-web01  pol-vm-arveo  Protected
vm-st07-web02  pol-vm-arveo  IRPending
Etat     Debut                             Fin
-------  --------------------------------  -----
Running  2026-10-08T09:13:20.0145213+00:00
```

### Pourquoi
- **Script à 09:00** : la première sauvegarde d'une VM est complète (copie de tous les disques utilisés vers le coffre). Lancée à 11:00, elle ne fournirait au mieux qu'un point au niveau instantané pendant le module. Même logique que les passerelles VPN (J2) et Bastion (J3).
- **Coffre dans `rg-st<NN>-shared`, France Central** : un coffre Recovery Services protège les VMs et les comptes de stockage de SA région. Un seul coffre pour toutes les charges Arvéo simplifie les stratégies, le RBAC et la supervision (module 10).
- **LRS** : choix de coût pour la formation. En production, Arvéo choisirait GRS + restauration interrégion (perte de France Central) ou ZRS (perte d'une zone), décision à prendre AVANT la première protection (état `Locked` ensuite).
- **Stratégie Améliorée (V2)** : `web01` et `web02` sont des VMs à lancement fiable (images Ubuntu 24.04 du M7, Gen2, démarrage sécurisé et vTPM par défaut). La stratégie Standard les refuse. La stratégie Améliorée apporte aussi les sauvegardes toutes les 4 h si le RPO se durcit.
- **Rétention** : 30 points quotidiens + 12 points hebdomadaires (dimanche) = exigence de la DSI ; 7 jours d'instantanés = restauration en minutes pendant une semaine (au-delà : depuis le coffre, plus long).
- **Rôle « Backup Contributor » sur le coffre seul** : l'identité du serveur de Lyon doit générer des identifiants du coffre ; elle n'a besoin d'aucun droit ailleurs (moindre privilège, module 2).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `lancer-sauvegarde.sh` : `vm-stNN-web01 absente` | Rattrapage du M7 non joué ou VM supprimée | `./scripts/catch-up/module-07/deploy.sh <NN>` puis relancer le script |
| `enable-for-vm` : stratégie non compatible avec le lancement fiable | Stratégie Standard (`DefaultPolicy`) choisie | Utiliser `pol-vm-arveo` (`policyType` = `V2`) |
| `backup-properties set` : redondance non modifiable | Un élément déjà protégé (relance après protection) | Normal : la redondance reste celle du premier réglage ; recréer le coffre pour en changer |
| `backup-now` : `UserErrorBackupOperationInProgress` | Sauvegarde déjà en cours pour la VM | Attendre la fin ; le script détecte ce cas |
| `RequestDisallowedByPolicy` à la création du coffre | Stratégie du M2 (tags ou régions autorisées) | Vérifier les tags passés ; région `francecentral` autorisée |
| `mars-lyon.sh` : `aucune identité managée` | Module 6 rattrapé sans `lyon-fs-prep.sh` | `az vm identity assign -g rg-stNN-lyon -n vm-stNN-lyon-fs`, puis attribuer le rôle et relancer |
| `role assignment create` : `Forbidden` | Stagiaire non propriétaire de `rg-stNN-shared` | Vérifier `az role assignment list --assignee <UPN> -g rg-stNN-shared` ; formatrice |

---

## Lab 09.2 ⭐⭐ — Sauvegarder et restaurer le partage `partage-lyon`

### Solution
```bash
# 1. Stratégie : 20:00 heure de Paris, 30 points quotidiens
grep -E '"(scheduleRunTimes|timeZone|count)"' -A1 scripts/labs/module-09/pol-files-arveo.json
# 2. Stratégie dans le coffre
az backup policy create -g "$RG_SHARED" -v "$VAULT" -n pol-files-arveo \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --policy @scripts/labs/module-09/pol-files-arveo.json --query name -o tsv
# 3. Protection (enregistre le compte dans le coffre, 1 à 2 min)
az backup protection enable-for-azurefileshare -g "$RG_SHARED" -v "$VAULT" \
  --policy-name pol-files-arveo --storage-account "$SA_FILES" \
  --azure-file-share partage-lyon -o none
# 4. Verrou posé par Azure Backup
az lock list -g "$RG_DATA" --query "[].{Nom:name, Niveau:level, Notes:notes}" -o table
```
Sortie attendue (étape 4, texte de la note `[À VÉRIFIER]`) :
```
Nom                        Niveau        Notes
-------------------------  ------------  ----------------------------------------------------
AzureBackupProtectionLock  CanNotDelete  Auto-created by Azure Backup for storage accounts ...
```
```bash
# 5. Sauvegarde immédiate, attente, instantanés
bkitem AzureFileShare partage-lyon
JOB=$(az backup protection backup-now -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureStorage \
  --retain-until "$(date -d '+30 days' +%d-%m-%Y)" --query name -o tsv)
az backup job wait -g "$RG_SHARED" -v "$VAULT" -n "$JOB"
az backup job show -g "$RG_SHARED" -v "$VAULT" -n "$JOB" --query properties.status -o tsv
az storage share list --account-name "$SA_FILES" --include-snapshots \
  --query "[?name=='partage-lyon'].snapshot" -o tsv
```
Sortie attendue (noms internes et horodatage variables) :
```
CONT=StorageContainer;Storage;rg-st07-data;starveost07files2610 ITEM=AzureFileShare;<EMPREINTE>
Completed

2026-10-08T09:31:07.0000000Z
```
La ligne vide correspond au partage lui-même (sans instantané).
```bash
# 6. Suppression simulée (énoncé), puis 7. restauration du seul fichier
RP=$(az backup recoverypoint list -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --query "sort_by(@, &properties.recoveryPointTime)[-1].name" -o tsv)
JOB=$(az backup restore restore-azurefiles -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --rp-name "$RP" \
  --restore-mode OriginalLocation --resolve-conflict Overwrite \
  --source-file-type File --source-file-path Exploitation/tournee-03.csv --query name -o tsv)
az backup job wait -g "$RG_SHARED" -v "$VAULT" -n "$JOB"
az storage file list --share-name partage-lyon --account-name "$SA_FILES" \
  --path Exploitation --query "length(@)" -o tsv
sleep 180
lyon "Test-Path F:\Partages\Commun\Exploitation\tournee-03.csv"
```
Sortie attendue :
```
12
True
```

Réponses de l'étape 8 :
- **a.** Le point de récupération est un instantané du partage, stocké DANS le compte `starveost<NN>files<SES>` (niveau instantané). Le coffre ne contient que les métadonnées et pilote la planification et la rétention. Si le compte était supprimé, ses instantanés disparaîtraient avec lui : c'est la raison du verrou et du niveau coffré (copie des données dans le coffre, isolée du compte) `[À VÉRIFIER]` disponibilité régionale.
- **b.** Le verrou `CanNotDelete` empêche la suppression accidentelle (ou malveillante) du compte, donc des instantanés. Il bloque `./scripts/cleanup/module-06-storage.sh <NN> --purge` : en fin de formation, lancer d'abord `module-09-backup.sh <NN> --purge`, qui désinscrit le compte et retire le verrou.
- **c.** Le serveur de Lyon est un cache (hiérarchisation cloud) : sauvegarder `F:\Partages\Commun` avec MARS forcerait le rappel des fichiers hiérarchisés, saturerait le volume et doublerait les données. Le point de terminaison cloud est la copie de référence, il survivra à la fermeture de Lyon, et sa sauvegarde ne dépend d'aucun serveur.

### Pourquoi
- **20:00** : après la fin d'activité, avant la sauvegarde des VMs (22:00) ; le partage est sauvegardé en quelques secondes (instantané incrémentiel, aucun transfert).
- **Restauration au fichier, emplacement d'origine** : besoin du support (un fichier supprimé), sans écraser les autres fichiers modifiés depuis le point.
- **File Sync** : la restauration écrit dans le partage Azure ; Azure Backup déclenche la détection des changements pour que le serveur reçoive le fichier `[À VÉRIFIER]` délai observé. Sans elle, le serveur ne l'aurait vu qu'au cycle de détection de 24 h (module 6).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `enable-for-azurefileshare` : compte introuvable | Compte dans un autre groupe que le coffre `[À VÉRIFIER]` comportement de la version de la CLI | Passer l'ID du compte : `--storage-account $(az storage account show -g rg-stNN-data -n <COMPTE> --query id -o tsv)` |
| Protection refusée : accès réseau | Pare-feu du compte (bonus 2 du M6) sans exception des services approuvés | Ajouter l'exception « Services Microsoft approuvés » ou rétablir l'accès |
| `policy create` : argument `--workload-type` non reconnu | Version de la CLI | Retirer l'option (type déduit du fichier) |
| Liste du partage : 12 fichiers dès l'étape 6 | Suppression lancée sur un autre chemin | Vérifier `--path Exploitation/tournee-03.csv` (respect de la casse) |
| `Test-Path` : `False` après 5 min | Serveur arrêté ou détection non déclenchée | `az vm start` ; forcer `Invoke-AzStorageSyncChangeDetection -DirectoryPath 'Exploitation'` (lab 06.5) |
| `az storage share list` : `AuthorizationFailure` | Accès par clé retiré par erreur sur le compte de fichiers | `--auth-mode login` avec le rôle « Storage File Data Privileged Reader » `[À VÉRIFIER]` |

### Variantes acceptables
- Portail : coffre › **Sauvegarde** › **Azure** › **Partage de fichiers Azure**, puis **Restauration de fichier** depuis l'élément. Même résultat, utile pour montrer le parcours AZ-104.
- Restauration vers un autre emplacement (`--restore-mode AlternateLocation --target-storage-account --target-file-share --target-folder`) : plus sûre en production (contrôle avant recopie), plus lente pour le besoin du support.
- Stratégie à plusieurs sauvegardes par jour (planification horaire des partages) : RPO plus court, plus d'instantanés (limite par partage `[À VÉRIFIER]`).

---

## Lab 09.3 ⭐⭐ — Agent MARS sur le serveur de Lyon

### Solution
Étape 2 (portail) : **Serveurs protégés** › **Agent Azure Backup** affiche `vm-st<NN>-lyon-fs` (nom d'ordinateur Windows), état de l'inscription `Inscrit` et version de l'agent.

Étape 3, stratégie (fichier préparé dans Cloud Shell) :
```bash
mkdir -p ~/arveo-m09
cat > ~/arveo-m09/strategie-mars.ps1 <<'EOF'
Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'
$p = New-OBPolicy
Add-OBFileSpec -Policy $p -FileSpec (New-OBFileSpec -FileSpec @('F:\Compta')) | Out-Null
$jours = 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'
Set-OBSchedule -Policy $p -Schedule (New-OBSchedule -DaysOfWeek $jours -TimesOfDay 21:00) | Out-Null
Set-OBRetentionPolicy -Policy $p -RetentionPolicy (New-OBRetentionPolicy -RetentionDays 30) | Out-Null
Set-OBPolicy -Policy $p -Confirm:$false | Out-Null
(Get-OBPolicy | Get-OBFileSpec).FileName
Get-OBPolicy | Get-OBSchedule | Select-Object ScheduleRunDays, ScheduleRunTimes | Format-List
EOF
lyon "$(cat ~/arveo-m09/strategie-mars.ps1)"
```
Sortie attendue (extrait ; mise en forme `[À VÉRIFIER]` selon la version de l'agent) :
```
F:\Compta
ScheduleRunDays  : {Monday, Tuesday, Wednesday, Thursday, Friday}
ScheduleRunTimes : {21:00:00}
```
Étape 4, sauvegarde immédiate (1 à 3 min) :
```bash
lyon "Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'; Get-OBPolicy | Start-OBBackup"
```
Sortie attendue (fin) :
```
Taking snapshot of volumes...
Transferring data...
The backup operation completed successfully.
```
Portail : **Éléments de sauvegarde** › **Agent Azure Backup** : volume `F:\` avec le dernier point ; **Travaux de sauvegarde** › filtre « Agent Azure Backup » : travail `Backup` `Terminé`.

Étapes 5 et 6, restauration dans `F:\Restauration` puis recopie :
```bash
cat > ~/arveo-m09/restauration-mars.ps1 <<'EOF'
Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'
$src  = Get-OBRecoverableSource | Select-Object -First 1
$rp   = Get-OBRecoverableItem -Source $src | Sort-Object PointInTime -Descending | Select-Object -First 1
$item = Get-OBRecoverableItem -RecoveryPoint $rp -Location 'F:\Compta' -SearchString 'export-2026-09-30.csv'
$opt  = New-OBRecoveryOption -DestinationPath 'F:\Restauration' -OverwriteType Overwrite
Start-OBRecovery -RecoverableItem $item -RecoveryOption $opt | Out-Null
$f = Get-ChildItem F:\Restauration -Recurse -Filter 'export-2026-09-30.csv' | Select-Object -First 1
Copy-Item $f.FullName F:\Compta\
"$($f.FullName) -> F:\Compta ; $((Get-ChildItem F:\Compta -File).Count) fichiers"
EOF
lyon "$(cat ~/arveo-m09/restauration-mars.ps1)"
```
Sortie attendue (chemin sous `F:\Restauration` `[À VÉRIFIER]` : arborescence d'origine recréée) :
```
F:\Restauration\Compta\export-2026-09-30.csv -> F:\Compta ; 6 fichiers
```

Réponses de l'étape 7 :
- **a.** Dans `~/.arveo/mars-passphrase.txt` (Cloud Shell) ; en entreprise : coffre de secrets (Azure Key Vault) ou coffre-fort physique, géré par une autre équipe. Stockée seulement sur le serveur, elle disparaît avec lui (sinistre, rançongiciel) : sans elle, aucune restauration, même vers un autre serveur. Microsoft ne peut pas la régénérer.
- **b.** Les opérations critiques, avec les fonctions de sécurité du coffre activées : réduction de la rétention, arrêt de la protection avec suppression des données, changement de la phrase secrète. Le PIN se génère dans le portail (coffre › **Propriétés** › **PIN de sécurité**), valable 5 min `[À VÉRIFIER]`.
- **c.** Moindre privilège : l'identité d'un serveur d'un site en fin de vie est moins digne de confiance qu'un compte d'administration. « Backup Contributor » sur le coffre permet l'inscription et la gestion de ses sauvegardes, mais ni la suppression du coffre, ni la gestion des accès, ni la modification des autres ressources de `rg-st<NN>-shared` (espace de travail, compte de diagnostic). Contributeur sur le groupe permettrait de supprimer le coffre entier.

### Pourquoi
- **MARS plutôt que la sauvegarde de VM** : `vm-st<NN>-lyon-fs` simule un serveur SUR SITE (Lyon) ; l'agent MARS est la méthode sans infrastructure supplémentaire pour des fichiers Windows. Une sauvegarde de VM Azure ne s'appliquerait pas à un vrai serveur physique de Lyon.
- **Identité managée pour les identifiants du coffre** : supprime le téléchargement manuel du fichier `.VaultCredentials` et sa copie vers le serveur ; le parcours portail (coffre › **Sauvegarde** › « Local » › « Fichiers et dossiers » › télécharger l'agent et les identifiants) reste celui de l'examen AZ-104 et d'un vrai serveur sur site.
- **`F:\Restauration` plutôt qu'écrasement** : un fichier comptable restauré se vérifie avant de remplacer quoi que ce soit.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `--status` : `Failed`, `Invoke-WebRequest` en échec | Pas de sortie Internet à Lyon | Formatrice : `./scripts/labs/module-06/lyon-nat.sh status` puis `create` ; relancer `mars-lyon.sh` |
| `--status` : `Failed`, `Get-AzRecoveryServicesVault` non autorisé | Rôle non attribué ou non propagé | Vérifier l'attribution (lab 09.1 étape 6), attendre 5 min, relancer `mars-lyon.sh` |
| `--status` : `Failed` sur `Set-OBMachineSetting` | `-SecurityPin` exigé par la version de l'agent `[À VÉRIFIER]` | Générer le PIN (portail), puis `lyon` : `Set-OBMachineSetting -EncryptionPassphrase ... -SecurityPin <PIN>` |
| `Start-OBBackup` : aucune stratégie | Étape 3 non appliquée (erreur de syntaxe) | Relire la sortie de l'étape 3 ; `Get-OBPolicy` |
| `Get-OBRecoverableItem` : aucun élément | Point plus ancien que le fichier ou nom erroné | Lister : `Get-OBRecoverableItem -Source $src` ; vérifier `PointInTime` |
| `lyon` : délai dépassé | Commande longue (sauvegarde initiale volumineuse) | Normal au-delà de 90 min seulement ; ici données réduites : vérifier le service `obengine` |

### Variantes acceptables
- Console graphique MARS par une session RDP (Bastion du hub vers le site de Lyon : non prévu ici, le site n'est pas appairé) : même stratégie, assistant « Planifier la sauvegarde ».
- Stratégie à 3 sauvegardes par jour (`-TimesOfDay 12:00, 17:00, 21:00`) : maximum de MARS, RPO de quelques heures.
- Rétention GFS MARS (`New-OBRetentionPolicy` avec rétentions hebdomadaire et mensuelle `[À VÉRIFIER]` paramètres) : plus proche de la stratégie des VMs.

---

## Lab 09.4 ⭐⭐ — Récupérer les contrats de `web01` par restauration de disque

### Solution
```bash
# 2. Points de récupération de web01
bkitem VM "vm-${ST}-web01"
NIV="join(',', properties.recoveryPointTierDetails[].type)"
az backup recoverypoint list -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
  --workload-type VM --query "[].{Nom:name, Date:properties.recoveryPointTime, Niveau:$NIV}" -o table
RP=$(az backup recoverypoint list -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
  --workload-type VM --query "sort_by(@, &properties.recoveryPointTime)[-1].name" -o tsv)
```
Sortie attendue (identifiant et heure variables ; `HardenedRP` absent si le transfert n'est pas terminé) :
```
Nom              Date                         Niveau
---------------  ---------------------------  --------------------
140738765427211  2026-10-08T07:04:12.556+00:00  InstantRP,HardenedRP
```
```bash
# 3. Restauration des disques (LUN 0) dans rg-stNN-app
JOB=$(az backup restore restore-disks -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --rp-name "$RP" \
  --storage-account "$DIAG_SA" --target-resource-group "$RG_APP" \
  --diskslist 0 --query name -o tsv)
az backup job wait -g "$RG_SHARED" -v "$VAULT" -n "$JOB"
az backup job show -g "$RG_SHARED" -v "$VAULT" -n "$JOB" --query properties.status -o tsv
# 4. Disques restaurés
az disk list -g "$RG_APP" --query "[?managedBy==null].{Nom:name, Zone:zones[0], Go:diskSizeGB}" -o table
REST=$(az disk list -g "$RG_APP" --query "[?managedBy==null && diskSizeGB==\`32\`].name | [0]" -o tsv)
```
Sortie attendue (3 à 10 min depuis le niveau instantané ; noms générés `[À VÉRIFIER]`) :
```
Completed
Nom                                              Zone    Go
-----------------------------------------------  ------  ----
vm-st07-web01-osdisk-20261008-120411             1       30
vm-st07-web01-datadisk-000-20261008-120411       1       32
```
```bash
# 5. Attachement au LUN 1, montage en lecture seule, recopie
az vm disk attach -g "$RG_APP" --vm-name "vm-${ST}-web01" --name "$REST" --lun 1 -o none
vmrun web01 "set -e; udevadm settle; mkdir -p /mnt/restauration
mount -o ro /dev/disk/azure/scsi1/lun1-part1 /mnt/restauration
ls /mnt/restauration/contrats | wc -l
cp -a /mnt/restauration/contrats /srv/arveo/
ls /srv/arveo/contrats | wc -l
umount /mnt/restauration"
```
Sortie attendue :
```
5
5
```
```bash
# 6. Détachement et suppression de TOUS les disques restaurés
az vm disk detach -g "$RG_APP" --vm-name "vm-${ST}-web01" --name "$REST" -o none
for D in $(az disk list -g "$RG_APP" --query "[?managedBy==null].name" -o tsv); do
  az disk delete -g "$RG_APP" -n "$D" --yes -o none && echo "$D supprimé"
done
```

Réponses de l'étape 7 :
- **a.** « Remplacer l'existant » aurait arrêté `web01` et ramené TOUS ses disques au point de 09:00 (système compris) : interruption et perte de tout ce qui a changé depuis, pour récupérer un seul dossier. La récupération de fichiers convient aussi, mais demande un script, un montage iSCSI sortant (port 3260), un mot de passe saisi de manière interactive et un démontage dans les 12 h : plus fragile en automatisation. La restauration de disque est non intrusive et entièrement scriptable.
- **b.** Zone 1, celle de la VM d'origine : un disque managé zonal n'est attachable qu'à une VM de la même zone. Rattacher à `web02` (zone 2) aurait échoué ; il faudrait un instantané du disque puis un nouveau disque en zone 2, ou l'option de restauration interzone `[À VÉRIFIER]` conditions.
- **c.** Un contrat ajouté à 10:30 n'existe dans aucun point (dernier point : 09:00, suivant : 22:00) et a été supprimé à 11:55 : perdu. C'est le RPO de 24 h accepté par la DSI ; un RPO plus court exigerait une stratégie toutes les 4 h, ou une copie applicative (synchronisation vers Azure Files, par exemple).

### Pourquoi
- **`--diskslist 0`** : seul le disque de données est utile ; le disque OS est tout de même restauré par le service `[À VÉRIFIER]` comportement de la restauration sélective : d'où la suppression de tous les disques non attachés.
- **Compte intermédiaire `$DIAG_SA`** : compte Standard de France Central déjà présent (module 3) ; le service y dépose la configuration de la VM et le modèle de déploiement.
- **Lecture seule + copie** : aucune écriture sur la copie restaurée (preuve conservée), aucun écrasement des données vivantes.
- **LUN 1 et chemin `/dev/disk/azure/scsi1/lun1-part1`** : les deux disques portent la même étiquette `arveo-data` ; seul le chemin par LUN est sans ambiguïté.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Aucun point de récupération | Sauvegarde de 09:00 non lancée ou en échec | `az backup job list` ; si échec : rattrapage, ou point de `web02` pour s'exercer |
| `restore-disks` : compte de stockage non valide | Compte Premium, autre région ou accès réseau restreint | Utiliser un compte Standard de France Central sans pare-feu |
| Travail `Failed` : `RequestDisallowedByPolicy` | Stratégie du M2 (tags obligatoires) refusant les disques restaurés sans tags | Exemption temporaire sur `rg-stNN-app` (formatrice) ou effet `Modify` `[À VÉRIFIER]` définition du M2 |
| `vm disk attach` : zone incompatible | Disque restauré sans zone ou dans une autre zone | `az disk show --query zones` ; recréer un disque zonal depuis un instantané |
| `mount` : `wrong fs type` ou `cannot mount read-only` | Journal ext4 à rejouer | `mount -o ro,noload <PARTITION> /mnt/restauration` |
| `/dev/disk/azure/scsi1/lun1-part1` absent | Lien udev non créé (version de l'image) `[À VÉRIFIER]` | `lsblk -o NAME,HCTL,SIZE,LABEL` : partition du disque dont le HCTL finit par `:1` |
| VM bloquée au redémarrage, `/srv/arveo` incohérent | Redémarrage avec les deux disques `arveo-data` attachés | Détacher le disque restauré, redémarrer |

### Variantes acceptables
- Récupération de fichiers (bonus 2) : adaptée à quelques fichiers, sans créer de disque.
- Restauration sur une NOUVELLE VM de vérification (`vm-st<NN>-web01r`), puis copie par le réseau : plus lourde (carte, IP, coût), utile pour contrôler une application complète.
- Portail : élément › **Restaurer la VM** › **Restaurer les disques** ; même résultat.

---

## Défi 09.5 ⭐⭐⭐ — Retour arrière de `web01` après une mise à jour ratée

### Solution
```bash
# 1. Boucle de contrôle du portail (arrière-plan, fichier ~/arveo-m09/boucle.log)
mkdir -p ~/arveo-m09
LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
( while true; do
    R=$(curl -s --max-time 3 -w ' HTTP%{http_code}' "http://${LB_IP}/")
    echo "$(date +%T) $(grep -o 'vm-st[0-9]*-web0[12]' <<< "$R" | head -n 1) ${R##* }"
    sleep 2
  done ) > ~/arveo-m09/boucle.log 2>&1 &
BOUCLE=$!
tail -n 3 ~/arveo-m09/boucle.log
```
Sortie attendue (avant restauration : `web01` retirée du pool par la sonde) :
```
11:58:02 vm-st07-web02 HTTP200
11:58:04 vm-st07-web02 HTTP200
11:58:06 vm-st07-web02 HTTP200
```
Restauration, voie portail (recommandée) : coffre `rsv-st<NN>-arveo` › **Éléments de sauvegarde** › **Machine virtuelle Azure** › `vm-st<NN>-web01` › **Restaurer la VM** › point de 09:00 › configuration **Remplacer l'existant** › emplacement intermédiaire `starveost<NN>diag` › **Restaurer**. Heure de lancement à noter (début du RTO).

Restauration, voie CLI `[À VÉRIFIER]` option `--restore-mode OriginalLocation` selon la version de la CLI :
```bash
bkitem VM "vm-${ST}-web01"
RP=$(az backup recoverypoint list -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
  --workload-type VM --query "sort_by(@, &properties.recoveryPointTime)[-1].name" -o tsv)
T0=$(date +%s)
JOB=$(az backup restore restore-disks -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --rp-name "$RP" \
  --storage-account "$DIAG_SA" --restore-mode OriginalLocation --query name -o tsv)
az backup job wait -g "$RG_SHARED" -v "$VAULT" -n "$JOB"
az vm start -g "$RG_APP" -n "vm-${ST}-web01" -o none   # sans effet si déjà démarrée
```
Contrôles (étape 2) :
```bash
# a. page locale
vmrun web01 "curl -s -o /dev/null -w '%{http_code} ' localhost; curl -s localhost | grep -o 'portail client v[0-9]'"
# b. identité réseau
az vm show -g "$RG_APP" -n "vm-${ST}-web01" -d \
  --query "[privateIps, networkProfile.networkInterfaces[0].id]" -o tsv | sed 's#/subscriptions/.*/##'
az network lb address-pool show -g "$RG_APP" --lb-name "lbe-${ST}-web" -n bp-web \
  --query "length(backendIPConfigurations)" -o tsv
# c. boucle : erreurs et retour de web01, puis arrêt de la boucle et RTO
grep -vc 'HTTP200' ~/arveo-m09/boucle.log; grep -m1 -n 'web01' ~/arveo-m09/boucle.log
kill "$BOUCLE"; echo "RTO : $(( ($(date +%s) - T0) / 60 )) min"
# d. disques après restauration
az vm show -g "$RG_APP" -n "vm-${ST}-web01" \
  --query "{OS:storageProfile.osDisk.name, Donnees:storageProfile.dataDisks[].name}" -o json
vmrun web01 "ls /srv/arveo/contrats | wc -l"
```
Sortie attendue (noms de disques et numéro de ligne variables) :
```
200 portail client v2
10.7.4.11	nic-st07-web01
2
0
412:12:11:46 vm-st07-web01 HTTP200
RTO : 18 min
{
  "Donnees": [ "vm-st07-web01-datadisk-000-<HORODATAGE>" ],
  "OS": "vm-st07-web01-osdisk-<HORODATAGE>"
}
5
```
- d. Les disques de `web01` sont ceux recréés depuis le point de 09:00 : `/srv/arveo/contrats` contient les 5 contrats de 09:00 (la copie du lab 09.4 est écrasée par l'état du point). Les disques d'origine sont conservés, détachés, dans `rg-st<NN>-app` `[À VÉRIFIER]` comportement en vigueur : à supprimer après validation (`module-09-backup.sh` les supprime, sauf `disk-st<NN>-web01-data`, à supprimer à la main s'il est détaché).

Procédure (runbook) attendue, en substance :
1. Constater l'incident (sonde en échec, `web01` hors du pool) et vérifier que `web02` sert seule le portail.
2. Identifier le dernier point ANTÉRIEUR à la modification ; noter le RPO effectif (données perdues).
3. Lancer une boucle de contrôle du portail (preuve de continuité).
4. Restaurer `web01` en « Remplacer l'existant » avec le compte intermédiaire.
5. Suivre le travail jusqu'à `Completed` ; démarrer la VM si nécessaire.
6. Vérifier : page locale, IP et carte, pool (sonde), contenu des données.
7. Supprimer les disques d'origine détachés après validation ; consigner le RTO et l'incident.

Réponses de l'étape 4 :
- **a.** RPO effectif ce matin : le point de 09:00 (environ 3 h de modifications perdues sur `web01` ; ici seulement la mise à jour ratée). En régime normal : 24 h (sauvegarde à 22:00). Pour 4 h : stratégie Améliorée à planification horaire (`scheduleRunFrequency` = `Hourly`, intervalle 4 h, fenêtre de 24 h) ; coût : plus d'instantanés et de points dans le coffre.
- **b.** Non : stockage LRS, aucune restauration interrégion ; les points de récupération sont tous en France Central. Il aurait fallu un coffre GRS avec restauration interrégion, choisi AVANT la première protection (sinon nouveau coffre et nouvelle protection), ou une réplication Site Recovery. Avec GRS + CRR, la restauration se fait dans France South depuis la copie secondaire (RPO de la réplication du coffre, de l'ordre de 12 à 36 h `[À VÉRIFIER]`).
- **c.** Azure Site Recovery : réplication continue des VMs de l'ERP de France Central vers France South, VNet de reprise préparé (plan d'adressage distinct ou identique selon le basculement), plan de récupération (base de données puis serveurs d'applications, scripts de reconfiguration DNS), basculement de test annuel dans un VNet isolé, puis rétablissement. RPO de quelques minutes, RTO inférieur à 1 h si le plan est testé. La sauvegarde reste nécessaire : Site Recovery réplique aussi une corruption ou un chiffrement en quelques minutes, et ne conserve que des points récents ; seule la sauvegarde (immuable, longue rétention) permet de revenir avant l'attaque.

### Pourquoi
- **Remplacer l'existant** : seule option qui conserve nom, carte, IP et appartenance au pool ; « Créer une VM » imposerait une nouvelle carte (pool à reconfigurer, IP différente).
- **Boucle de contrôle** : prouve la valeur de la haute disponibilité du module 7 pendant une restauration (RTO du SERVICE nul, RTO du serveur mesuré).
- **Point antérieur à la modification** : le point le plus récent n'est pas toujours le bon (un point pris APRÈS une corruption la restaure).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| « Remplacer l'existant » indisponible | Limite de l'option pour certaines configurations `[À VÉRIFIER]` liste en vigueur | Restaurer les disques puis échanger le disque OS (`az vm update --os-disk`, VM désallouée) |
| CLI : option `--restore-mode` inconnue | Version de la CLI | Voie portail ; ou mise à jour de la CLI (Cloud Shell récent) |
| Boucle : erreurs `HTTP000` pendant la restauration | `web02` arrêtée ou sonde mal réglée | Vérifier `web02` (`az vm start`) et `DipAvailability` ; la continuité n'est pas prouvée |
| `web01` restaurée mais hors pool | VM non démarrée, ou nginx en échec au démarrage | `az vm start` ; `vmrun web01 "systemctl status nginx --no-pager"` |
| Travail `Failed` : extension de sauvegarde en conflit | Opération d'extension en cours (AMA, Custom Script) | Attendre et relancer |

### Variantes acceptables
- Restaurer les disques, puis échanger le disque OS de la VM désallouée (`az vm update -g <GROUPE> -n <VM> --os-disk <ID_DISQUE>`) : même résultat, plus d'étapes, utile si « Remplacer l'existant » est indisponible.
- Annulation par Custom Script (republier la configuration v2 de `portail-v2.sh`, module 7) : plus rapide si la cause est connue ; ne répond pas au cas « personne ne sait annuler ».

---

## Bonus

1. **Suppression réversible**
   ```bash
   bkitem VM "vm-${ST}-web02"
   az backup protection disable -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" \
     --item-name "$ITEM" --backup-management-type AzureIaasVM --delete-backup-data true --yes -o none
   az backup item show -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" --name "$ITEM" \
     --backup-management-type AzureIaasVM \
     --query "properties.{Etat:protectionState, SuppressionDifferee:isScheduledForDeferredDelete}" -o table
   az backup protection undelete -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" \
     --item-name "$ITEM" --backup-management-type AzureIaasVM -o none
   az backup protection resume -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" \
     --item-name "$ITEM" --policy-name pol-vm-arveo -o none
   ```
   Sortie attendue (commande `show`) : `SuppressionDifferee` à `True`, état `ProtectionStopped`. Sans suppression réversible, un attaquant Contributeur sur le coffre (ou un administrateur pressé) supprime définitivement tous les points en une commande ; avec elle, 14 jours pour réagir. L'immuabilité et la MUA ferment aussi la voie « désactiver la suppression réversible puis supprimer ».
2. **Récupération de fichiers** : le script Python demande le mot de passe affiché dans le portail, crée une cible iSCSI et monte les volumes sous `/home/arveoadmin/<NOM_VM>-<DATE>/Volume1` `[À VÉRIFIER]` chemin. Plus rapide pour un fichier, mais manuel, limité à 12 h et dépendant du port 3260 sortant.
3. **Blobs** : la sauvegarde opérationnelle s'appuie sur les mêmes mécanismes que le module 6 (versioning, flux de modifications, suppression réversible) et ajoute la restauration à un instant donné de tout un compte ou d'un conteneur, gérée depuis un coffre de sauvegarde (rétention centralisée, RBAC séparé). La sauvegarde coffrée des blobs copie en plus les données hors du compte `[À VÉRIFIER]` disponibilité. Rôle requis pour l'identité du coffre : « Storage Account Backup Contributor » sur le compte.
4. **Rapports** :
   ```bash
   WS_ID=$(az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" --query id -o tsv)
   az monitor diagnostic-settings create -n diag-backup --resource "$(az backup vault show \
     -g "$RG_SHARED" -n "$VAULT" --query id -o tsv)" --workspace "$WS_ID" --export-to-resource-specific true \
     --logs '[{"category":"CoreAzureBackup","enabled":true},{"category":"AddonAzureBackupJobs","enabled":true}]' -o none
   ```
   Requête (15 à 30 min plus tard) : `AddonAzureBackupJobs | summarize count() by JobOperation, JobStatus`.

---

## QCM — Réponses
1. **B** — La réplication copie toute écriture, écrasement compris ; seule une sauvegarde (ou le versioning) conserve l'ancienne version.
2. **B** — La redondance du stockage de sauvegarde est verrouillée dès qu'un élément est protégé.
3. **C** — Les VMs à lancement fiable ne sont prises en charge que par la stratégie Améliorée.
4. **B** — La sauvegarde Azure Files crée des instantanés de partage stockés dans le compte de stockage lui-même.
5. **C** — Azure Backup pose le verrou `AzureBackupProtectionLock` (`CanNotDelete`) sur le compte protégé.
6. **C** — La phrase secrète chiffre les données côté serveur ; ni Microsoft ni le PIN ne permettent de la retrouver.
7. **B** — Avec hiérarchisation, le partage Azure est la copie de référence ; MARS provoquerait des rappels massifs.
8. **C** — « Remplacer l'existant » garde la VM, sa carte réseau, son IP et donc son appartenance au pool.
9. **B** — Le niveau instantané restaure depuis des instantanés locaux à la région, sans copie depuis le coffre.
10. **C** — Seule la réplication continue de Site Recovery offre un RPO de quelques minutes vers une autre région.
