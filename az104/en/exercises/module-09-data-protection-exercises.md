# Module 09 — Exercises

Common thread: **Arvéo backup and recovery plan**. A single Recovery Services vault protects the two customer portal servers (VM backup, Enhanced policy), the share `partage-lyon` migrated in module 6 (share snapshots managed by the vault) and the accounting exports of the Lyon server, which are not migrated (MARS agent). Every protection is proven by a restore: a file of the share, a folder of the Lyon server, `web01` data then system. The backup jobs feed the monitoring of module 10.

| Resource | Name (trainee 07, session `2610`) | Group | Lab |
|---|---|---|---|
| Recovery Services vault | `rsv-st07-arveo` (France Central, LRS storage) | `rg-st07-shared` | 09.1 (09:00 script) |
| VM policy | `pol-vm-arveo` (Enhanced, 22:00, 7 d of snapshots, 30 d + 12 weeks) | `rg-st07-shared` | 09.1 |
| Protected VMs | `vm-st07-web01` (09:00 script), `vm-st07-web02` | `rg-st07-app` | 09.1 |
| Policy and protected share | `pol-files-arveo`, `partage-lyon` of `starveost07files2610` | `rg-st07-shared` / `rg-st07-data` | 09.2 |
| Server protected by MARS | `vm-st07-lyon-fs`, folder `F:\Compta` | `rg-st07-lyon` | 09.3 |
| Restored disks (temporary) | OS disk and LUN 0 disk of `web01`, generated names | `rg-st07-app` | 09.4 |

Variables used in all labs:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<SES>` = 4-character session code from module 6 (e.g. `2610`)
- `<REPO_URL>` = Git repository of the course, provided by the trainer

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`. Tag names and values stay in French: they are shared with the French-speaking groups of the same tenant. Lab scripts (`scripts/labs/module-09/`) are shared with those groups: their comments and messages are in French. Folder and file names of the Lyon server (`Compta` = accounting, `Restauration` = restore, `Partages\Commun` = common shares) and of `web01` (`contrats` = contracts) are kept in French for the same reason.

**Variable block**: paste it into Cloud Shell (Bash) at the start of EVERY lab (session closed after 20 min of inactivity).
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
cd ~/formation 2>/dev/null || git clone <REPO_URL> ~/formation && cd ~/formation
vmrun() {   # vmrun <web01|web02> "<BASH COMMAND>": run on vm-stNN-<name> (rg-stNN-app)
  az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
lyon() {    # lyon "<POWERSHELL COMMAND>": run on vm-stNN-lyon-fs
  az vm run-command invoke -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" \
    --command-id RunPowerShellScript --scripts "$1" \
    --query "value[0].message" -o tsv
}
bkitem() {  # bkitem <VM|AzureFileShare> <NAME>: internal names CONT and ITEM of a protected item
  local BMT=AzureIaasVM; [[ "$1" == "AzureFileShare" ]] && BMT=AzureStorage
  read -r CONT ITEM < <(az backup item list -g "$RG_SHARED" -v "$VAULT" \
    --backup-management-type "$BMT" --workload-type "$1" \
    --query "[?properties.friendlyName=='$2'] | [0].[properties.containerName, name]" -o tsv)
  echo "CONT=${CONT} ITEM=${ITEM}"
}
echo "$ST $VAULT $SA_FILES $DIAG_SA"
```
Expected result (trainee 07, session `2610`; diagnostics account name with the possible module 3 suffix):
```
st07 rsv-st07-arveo starveost07files2610 starveost07diag
```

**Starting state**: end of module 7 for compute, VMs `web01` and `web02` restarted at the beginning of day 4 (portal v2 served by `lbe-st<NN>-web`, `web01` data disk mounted on `/srv/arveo`); end of module 6 for storage (`partage-lyon` synchronized with `F:\Partages\Commun` of the Lyon server, server stopped at the end of the D3 morning); the trainer's `natgw-lyon` NAT gateway active until the end of D4. Module 9 uses no module 8 resource. Late trainee: `./scripts/catch-up/module-09/deploy.sh <NN> <SES>` (15 to 25 min, backups included) produces the END state of module 9.

---

## Lab 09.1 ⭐ — Arvéo vault, Enhanced policy, protecting `web02` (guided)
**Duration** : 5 min in class (+ 2 min at 09:00) · **Objective** : configure a Recovery Services vault and a policy that meet Arvéo's requirement, then protect a VM (objective 10)
**Context** : for the customer portal, Arvéo IT sets a 24 h RPO, a retention of 30 days and 12 weeks, and a restore in a few minutes for one week. The initial backup of a VM takes time, so the vault and the protection of `web01` were started at 09:00 by script; the lab checks the result and protects `web02`.
**Prerequisites** : variable block run; starting state as described.

### Steps
1. **(D4, 09:00, at the start of module 8)** Launch the backup preparation (2 min, `web01` backup in the background):
   ```bash
   ./scripts/labs/module-09/lancer-sauvegarde.sh "$NN"
   ```
   Expected result (script messages in French; retention date and ID vary):
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
      travail lancé : <JOB_ID>
   Suivi : az backup job list -g rg-st07-shared -v rsv-st07-arveo -o table
   ```

2. **(11:10)** Read the storage and security configuration of the vault:
   ```bash
   Q="{Storage:[0].properties.storageModelType, State:[0].properties.storageTypeState,"
   Q="$Q CRR:[0].properties.crossRegionRestoreFlag, SoftDelete:[1].properties.softDeleteFeatureState}"
   az backup vault backup-properties show -g "$RG_SHARED" -n "$VAULT" --query "$Q" -o table
   ```
   Expected result:
   ```
   Storage           State   CRR    SoftDelete
   ----------------  ------  -----  ------------
   LocallyRedundant  Locked  False  Enabled
   ```
   `Locked`: an item is protected, the vault redundancy can no longer change.

3. Read policy `pol-vm-arveo` and its source file:
   ```bash
   az backup policy show -g "$RG_SHARED" -v "$VAULT" -n pol-vm-arveo \
     --query "{Type:properties.policyType, Frequency:properties.schedulePolicy.scheduleRunFrequency, Snapshots:properties.instantRpRetentionRangeInDays, Days:properties.retentionPolicy.dailySchedule.retentionDuration.count, Weeks:properties.retentionPolicy.weeklySchedule.retentionDuration.count}" \
     -o table
   grep -E '"(scheduleRunTimes|timeZone|daysOfTheWeek)"' -A1 scripts/labs/module-09/pol-vm-arveo.json
   ```
   Expected result (first command):
   ```
   Type    Frequency    Snapshots    Days    Weeks
   ------  -----------  -----------  ------  -------
   V2      Daily        7            30      12
   ```

4. Follow the vault jobs:
   ```bash
   az backup job list -g "$RG_SHARED" -v "$VAULT" -o table \
     --query "[].{Item:properties.entityFriendlyName, Operation:properties.operation, Status:properties.status, Start:properties.startTime}"
   ```
   Expected result (the `web01` backup may still be `InProgress`):
   ```
   Item           Operation        Status      Start
   -------------  ---------------  ----------  --------------------------------
   vm-st07-web01  Backup           InProgress  2026-10-08T07:03:41.118230+00:00
   vm-st07-web01  ConfigureBackup  Completed   2026-10-08T07:02:55.402871+00:00
   ```

5. Protect `web02` with the same policy, then start its first backup:
   ```bash
   VM02_ID=$(az vm show -g "$RG_APP" -n "vm-${ST}-web02" --query id -o tsv)
   az backup protection enable-for-vm -g "$RG_SHARED" -v "$VAULT" \
     --vm "$VM02_ID" --policy-name pol-vm-arveo -o none
   bkitem VM "vm-${ST}-web02"
   az backup protection backup-now -g "$RG_SHARED" -v "$VAULT" \
     --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
     --retain-until "$(date -d '+30 days' +%d-%m-%Y)" --query "properties.status" -o tsv
   ```
   Expected result (1 to 2 min; exact format of the internal names `[TO VERIFY]`):
   ```
   CONT=iaasvmcontainerv2;rg-st07-app;vm-st07-web02 ITEM=VM;iaasvmcontainerv2;rg-st07-app;vm-st07-web02
   InProgress
   ```

6. Prepare lab 09.3: assign the Lyon server's managed identity (created in module 6) the "Backup Contributor" role on the vault ONLY, then start the MARS agent installation in the background (10 to 15 min):
   ```bash
   LYON_MI=$(az vm show -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" --query identity.principalId -o tsv)
   VAULT_ID=$(az backup vault show -g "$RG_SHARED" -n "$VAULT" --query id -o tsv)
   az role assignment create --assignee-object-id "$LYON_MI" \
     --assignee-principal-type ServicePrincipal --role "Backup Contributor" \
     --scope "$VAULT_ID" --query roleDefinitionName -o tsv
   ./scripts/labs/module-09/mars-lyon.sh "$NN"
   ```
   Expected result:
   ```
   Backup Contributor
   == Serveur vm-st07-lyon-fs
      en fonctionnement
   == Phrase secrète MARS
      générée : /home/<USER>/.arveo/mars-passphrase.txt (32 caractères)
   == Installation et inscription de l'agent MARS (commande d'exécution managée mars-install)
      mars-install lancée en arrière-plan (10 à 15 min)
   Suivi : ./scripts/labs/module-09/mars-lyon.sh 07 --status
   ```

### Success criteria
- [ ] `az backup vault backup-properties show -g rg-st<NN>-shared -n rsv-st<NN>-arveo --query "[0].properties.storageModelType" -o tsv` returns `LocallyRedundant`.
- [ ] `az backup item list -g rg-st<NN>-shared -v rsv-st<NN>-arveo --backup-management-type AzureIaasVM --query "[].{VM:properties.friendlyName, Policy:properties.policyName}" -o table` shows `web01` and `web02` with `pol-vm-arveo`.
- [ ] A `Backup` job exists for each VM (`InProgress` or `Completed`).
- [ ] `mars-lyon.sh <NN> --status` shows a `Running` or `Succeeded` execution.

---

## Lab 09.2 ⭐⭐ — Backing up and restoring share `partage-lyon` (semi-autonomous)
**Duration** : 10 min · **Objective** : back up an Azure Files share with the vault and restore a deleted file (objective 10)
**Context** : since module 6, `partage-lyon` is the reference copy of the Lyon file server; File Sync ALSO propagates deletions. Requirement: 24 h RPO, 30-day retention, restore of a file by the service desk in less than one hour, without depending on the Lyon server.
**Prerequisites** : lab 09.1 completed; share synchronized (module 6).

**Assignment** :
1. Read `scripts/labs/module-09/pol-files-arveo.json`: backup time, time zone, retention.
2. Create policy `pol-files-arveo` in the vault from this file.
3. Protect share `partage-lyon` of account `starveost<NN>files<SES>` with this policy.
4. List the locks of the storage account: note the name, level and creator of the lock that appeared.
5. Start an on-demand backup of the share (kept 30 days), wait for the job to end, then list the share snapshots.
6. Simulate a Lyon user's mistake (provided):
   ```bash
   az storage file delete --share-name partage-lyon --path Exploitation/tournee-03.csv \
     --account-name "$SA_FILES" -o none
   az storage file list --share-name partage-lyon --account-name "$SA_FILES" \
     --path Exploitation --query "length(@)" -o tsv
   ```
   Expected result: `11` (one file fewer than in module 6).
7. Restore `Exploitation/tournee-03.csv` alone, to the original location, from the recovery point created in step 5. Check that it is back in the share, then, 2 to 5 min later, on the Lyon server.
8. Answer in writing:
   - a. Where are the data of the recovery point physically stored? What would happen to them if the storage account were deleted?
   - b. Why does Azure Backup set a lock on the account? Which cleanup script of a previous module is affected?
   - c. Why back up the share rather than `F:\Partages\Commun` on the Lyon server?

**Hints** :
- Policy: `az backup policy create --backup-management-type AzureStorage --workload-type AzureFileShare --policy @<FILE>`.
- Protection: `az backup protection enable-for-azurefileshare --policy-name --storage-account --azure-file-share` (also registers the account with the vault; 1 to 2 min).
- Locks: `az lock list -g rg-st<NN>-data --query "[].{Name:name, Level:level, Notes:notes}" -o table`.
- Internal names: `bkitem AzureFileShare partage-lyon`.
- Backup: `az backup protection backup-now --backup-management-type AzureStorage --retain-until <DD-MM-YYYY>`; wait: `az backup job wait -n <JOB_ID>`.
- Snapshots: `az storage share list --account-name <ACCOUNT> --include-snapshots --query "[?name=='partage-lyon'].snapshot" -o tsv`.
- Points: `az backup recoverypoint list --backup-management-type AzureStorage --query "sort_by(@, &properties.recoveryPointTime)[-1].name" -o tsv`.
- Restore: `az backup restore restore-azurefiles --restore-mode OriginalLocation --resolve-conflict Overwrite --source-file-type File --source-file-path <PATH>`.
- Server: `lyon "Test-Path F:\Partages\Commun\Exploitation\tournee-03.csv"`.

**Success criteria** :
- [ ] `az backup item list -g rg-st<NN>-shared -v rsv-st<NN>-arveo --backup-management-type AzureStorage --workload-type AzureFileShare --query "[0].properties.[friendlyName, policyName]" -o tsv` returns `partage-lyon` and `pol-files-arveo`.
- [ ] Lock `AzureBackupProtectionLock` (level `CanNotDelete`) is present on the account.
- [ ] At least one snapshot of `partage-lyon` exists.
- [ ] After the restore, folder `Exploitation` of the share has `12` files again and `Test-Path` returns `True` on the server.
- [ ] The three step 8 answers are written.

---

## Lab 09.3 ⭐⭐ — MARS agent on the Lyon server (semi-autonomous)
**Duration** : 15 min · **Objective** : back up and restore a folder of an on-premises server with the MARS agent (objective 10)
**Context** : until Lyon closes (6 months), the old accounting application drops its exports every day into `F:\Compta` on the file server. This folder is NOT synchronized with Azure Files. The weekly LTO tape has been stopped: accounting requires a backup every weekday evening at 21:00, kept 30 days, with no inbound port or VPN to Lyon.
**Prerequisites** : lab 09.1 step 6 launched (agent installed and registered); variable block run.

**Assignment** :
1. Check that the installation is finished:
   ```bash
   ./scripts/labs/module-09/mars-lyon.sh "$NN" --status
   ```
   Expected result (versions and dates vary; messages in French):
   ```
   Etat       Debut                             Fin
   ---------  --------------------------------  --------------------------------
   Succeeded  2026-10-08T09:13:20.0145213+00:00  2026-10-08T09:24:51.7745130+00:00
   Dossier F:\Compta : 6 fichiers
   Agent MARS : 2.0.xxxxx.0
   Inscription : rsv-st07-arveo
   MARS PRET
   ```
2. **Portal**: vault `rsv-st<NN>-arveo` › **Backup infrastructure** › **Protected servers** › **Azure Backup Agent**: note the name of the registered server and its state.
3. On the server, through the `lyon` function, define the MARS policy: folder `F:\Compta`, Monday to Friday at 21:00, 30-day retention. Then display the applied policy.
4. Start an on-demand backup according to this policy, then check, in the vault, the backed-up item and the matching job (portal: **Backup items** › **Azure Backup Agent**; **Backup jobs**).
5. Simulate a deletion (provided):
   ```bash
   lyon "Remove-Item F:\Compta\export-2026-09-30.csv; (Get-ChildItem F:\Compta).Count"
   ```
   Expected result: `5`.
6. Restore `export-2026-09-30.csv` from the step 4 recovery point into `F:\Restauration`, then copy it back to `F:\Compta` and check that the folder has 6 files again.
7. Answer in writing:
   - a. Where is the passphrase kept? Why must it never be stored only on the protected server?
   - b. Which operations will require the vault security PIN?
   - c. Why the "Backup Contributor" role on the vault only, rather than Contributor on `rg-st<NN>-shared`?

**Hints** :
- Module: `Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'` at the beginning of every `lyon` call (new PowerShell session on each call).
- Policy: `New-OBPolicy`, `New-OBFileSpec -FileSpec @('F:\Compta')`, `Add-OBFileSpec`, `New-OBSchedule -DaysOfWeek ... -TimesOfDay 21:00`, `Set-OBSchedule`, `New-OBRetentionPolicy -RetentionDays 30`, `Set-OBRetentionPolicy`, `Set-OBPolicy -Confirm:$false`; reading: `Get-OBPolicy | Get-OBSchedule`, `Get-OBPolicy | Get-OBFileSpec`.
- Backup: `Get-OBPolicy | Start-OBBackup` (synchronous: 1 to 3 min); last job: `Get-OBJob -Previous 1`.
- Restore: `Get-OBRecoverableSource` (backed-up volumes), `Get-OBRecoverableItem -Source <SOURCE>` (points, `PointInTime` property), `Get-OBRecoverableItem -RecoveryPoint <POINT> -Location 'F:\Compta' -SearchString '<NAME>'`, `New-OBRecoveryOption -DestinationPath 'F:\Restauration' -OverwriteType Overwrite`, `Start-OBRecovery -RecoverableItem <ITEM> -RecoveryOption <OPTION>`.
- Several PowerShell lines: write them into a Cloud Shell file, then `lyon "$(cat <FILE>)"`.
- Restored path: the agent recreates the original tree under the target folder `[TO VERIFY]` (`Get-ChildItem F:\Restauration -Recurse`).

**Success criteria** :
- [ ] `lyon "Import-Module '<MODULE_PATH>'; (Get-OBPolicy | Get-OBFileSpec).FileName"` returns `F:\Compta`.
- [ ] The portal shows `F:\` (or `F:\Compta`) among the Azure Backup Agent items, with a recovery point.
- [ ] `lyon "(Get-ChildItem F:\Compta).Count"` returns `6` after the restore.
- [ ] The three step 7 answers are written.

---

## Lab 09.4 ⭐⭐ — Recovering the `web01` contracts through a disk restore (semi-autonomous)
**Duration** : 15 min · **Objective** : restore the data of a VM from a recovery point without interrupting the VM (objective 10)
**Context** : at 11:55, a badly configured purge script deleted folder `/srv/arveo/contrats` on `web01` (framework contracts of the carriers, published by the portal). The portal must stay in service; only the data must come back, as they were at the 09:00 point.
**Prerequisites** : `web01` backup completed or at least at the snapshot tier; variable block run.

**Assignment** :
1. Simulate the incident (provided):
   ```bash
   vmrun web01 "ls /srv/arveo/contrats | wc -l; rm -rf /srv/arveo/contrats; ls /srv/arveo"
   ```
   Expected result: `5`, then the content of `/srv/arveo` without `contrats` (`lost+found`).
2. List the recovery points of `web01` with their date and tier (`InstantRP`, `HardenedRP`). Keep the most recent one.
3. Restore the disks of this point (LUN 0 data disk) into `rg-st<NN>-app`, with `$DIAG_SA` as staging account. Follow the job until `Completed`.
4. Identify the restored disks (unattached disks of `rg-st<NN>-app`): name, zone, size.
5. Attach the restored data disk to `web01` on LUN 1, mount it READ-ONLY on `/mnt/restauration`, copy `contrats` back into `/srv/arveo`, check the 5 files.
6. Unmount, detach, then delete ALL the restored disks (OS disk included).
7. Answer in writing:
   - a. Why not use "Replace existing" or file recovery?
   - b. In which zone was the restored disk created? Could it have been attached to `web02`?
   - c. Which data would have been lost if a contract had been added at 10:30?

**Hints** :
- Internal names: `bkitem VM "vm-${ST}-web01"`.
- Points: `az backup recoverypoint list --backup-management-type AzureIaasVM --workload-type VM`; tier: `join(',', properties.recoveryPointTierDetails[].type)`; most recent: `sort_by(@, &properties.recoveryPointTime)[-1].name`.
- Restore: `az backup restore restore-disks --rp-name <POINT> --storage-account <ACCOUNT> --target-resource-group <GROUP> --diskslist 0 --query name -o tsv` (returns the job ID); follow-up: `az backup job wait -n <JOB_ID>` then `az backup job show -n <JOB_ID> --query properties.status`.
- Unattached disks: `az disk list -g <GROUP> --query "[?managedBy==null].{Name:name, Zone:zones[0], GB:diskSizeGB}" -o table`.
- Attach: `az vm disk attach --name <DISK> --lun 1`; device: `lsblk -o NAME,HCTL,SIZE,LABEL,MOUNTPOINT` (LUN = last number of `HCTL`) or `/dev/disk/azure/scsi1/lun1-part1`.
- Mount: `mkdir -p /mnt/restauration && mount -o ro <PARTITION> /mnt/restauration`; copy: `cp -a`.
- Both disks carry the `arveo-data` label: never restart `web01` with both disks attached (ambiguous `LABEL=` mount).

**Success criteria** :
- [ ] The `Restore` job of `vm-st<NN>-web01` is `Completed`.
- [ ] `vmrun web01 "ls /srv/arveo/contrats | wc -l; findmnt -no SOURCE /mnt/restauration"` returns `5` and no mounted source.
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web01 --query "length(storageProfile.dataDisks)"` returns `1`.
- [ ] `az disk list -g rg-st<NN>-app --query "[?managedBy==null] | length(@)"` returns `0`.
- [ ] The three step 7 answers are written.

---

## Challenge 09.5 ⭐⭐⭐ — Rolling `web01` back after a failed update (autonomous)
**Duration** : 15 min in class (commented walkthrough for the others) · **Objective** : restore the system of a VM from a recovery point while keeping its network identity, and choose the right recovery service (objective 10)
**Context** : a manual update of the "v3" portal on `web01` broke the nginx configuration: `web01` answers `500`, the Load Balancer probe removed it from the pool. Nobody knows how to undo the change. The operations manager decides to go back to the 09:00 backup point, without a new VM: same name, same IP, same place in `bp-web`. The portal must not be interrupted during the operation.

Simulation of the failed update (provided):
```bash
vmrun web01 "printf 'server { listen 80 default_server; return 500; }\n' \
  > /etc/nginx/sites-enabled/default && systemctl reload nginx && curl -s -o /dev/null -w '%{http_code}\n' localhost"
```
Expected result: `500`.

**Requirements** :

| Element | Requirement |
|---|---|
| Restore point | Most recent `web01` point PRIOR to the failed update |
| Restore type | Replace existing disks, staging account `starveost<NN>diag` |
| Network identity | `nic-st<NN>-web01`, IP `10.<OCT>.4.11`, membership of `bp-web` unchanged |
| Continuity | Portal served by `lbe-st<NN>-web` during the whole operation, with no HTTP error |
| Traceability | Procedure (runbook) of 5 to 8 steps, RTO measured from launch until `web01` is back in the pool |

**Assignment** :
1. Before any restore, start from Cloud Shell a portal monitoring loop (one request every 2 s, HTTP code and responding server), recorded in a file.
2. Perform the restore (portal or CLI), then prove the result with four checks:
   - a. `web01` answers `200` again locally with the v2 page;
   - b. the NIC, the IP and the pool membership are unchanged;
   - c. the loop recorded no error and shows `web01` coming back;
   - d. the `web01` disks after the restore are identified (names, creation date) and the state of `/srv/arveo/contrats` is explained.
3. Write the procedure and the measured RTO.
4. Answer in writing:
   - a. What effective RPO for `web01` this morning? What should change for a 4 h RPO?
   - b. France Central becomes unavailable: does the current vault allow restoring `web01` elsewhere? What should have been configured, and when?
   - c. Arvéo's ERP requires a 15-min RPO and a 1-h RTO if the region is lost. Propose the recovery architecture (service, target region, yearly test) and explain why backup is still needed.

**Success criteria** :
- [ ] The last `Restore` job of `vm-st<NN>-web01` is `Completed` (restore type: replace disks).
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web01 -d --query "[privateIps, networkProfile.networkInterfaces[0].id]" -o tsv` shows `10.<OCT>.4.11` and `nic-st<NN>-web01`.
- [ ] `curl -s http://<LB_IP>/` answers from `web01` AND `web02`; the loop file contains no code other than `200`.
- [ ] The procedure, the measured RTO and the three step 4 answers are written.

---

## Bonus 🚀
1. **Soft delete**: stop the protection of `web02` WITH data deletion, observe the item state (`az backup item show ... --query properties.isScheduledForDeferredDelete`), then undo the deletion (`az backup protection undelete`) and resume protection (`az backup protection resume`, policy `pol-vm-arveo`). Explain what an attacker holding the Contributor role on the vault could have done without this feature.
2. **File recovery (ILR)**: portal, vault › item `vm-st<NN>-web02` › **File Recovery**: download the Python script of the last point, run it on `web02` through Bastion (`scripts/labs/module-07/bastion.sh` if Bastion was deleted) or through `vmrun` `[TO VERIFY]` non-interactive password entry, browse the mounted volumes, then **Unmount Disks**. Compare duration and risks with lab 09.4.
3. **Blobs `pod` (module 6)**: create a Backup vault `bvault-st<NN>-arveo` in `rg-st<NN>-shared`, assign its identity the "Storage Account Backup Contributor" role on `starveost<NN>data<SES>`, then configure the operational backup of the account (portal: Backup vault › **Backup** › **Azure Blobs**). Explain what it adds to the versioning and soft delete of module 6.
4. **Reports**: create a diagnostic setting of the vault towards `log-st<NN>-shared` (categories `AddonAzureBackupJobs`, `CoreAzureBackup`, resource-specific mode), then, 15 to 30 min later, query table `AddonAzureBackupJobs` (preparing module 10).

## Cleanup
- **End of the D4 morning (12:28)**:
  ```bash
  ./scripts/cleanup/module-09-backup.sh "$NN"
  ```
  The script deallocates the Lyon server and deletes the unattached disks of `rg-st<NN>-app` (forgotten restored disks), except during a running restore (challenge 09.5: rerun it once the job is over). Safe to rerun.
- Kept until the end of the course: vault, policies, protected items and recovery points (jobs and alerts used in module 10).
- **End of the course**, BEFORE the full storage cleanup (`module-06-storage.sh --purge`):
  ```bash
  ./scripts/cleanup/module-09-backup.sh "$NN" --purge
  ```
  Disables soft delete, stops every protection with data deletion, unregisters the storage account (lock `AzureBackupProtectionLock` disappears), deletes the registered MARS server, the policies then the vault. Without a prior `--purge`, deleting the files account fails (lock) and the vault stays blocked 14 days (soft delete).
- Bonus 3: delete `bvault-st<NN>-arveo` (stop the protection first).
- Full module catch-up: `./scripts/catch-up/module-09/deploy.sh <NN> <SES>`.
- Costs: protected instance billed monthly by protected size (VM, share, MARS server), vault storage per GB (LRS), disk and share snapshots per GB, Windows B2s_v2 VM while running `[TO VERIFY]` Azure pricing calculator.
