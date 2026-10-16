# Module 09 — Solutions

All commands assume the variable block of the exercises has been run (`NN`, `SES`, `ST`, `RG_*`, `VAULT`, `SA_FILES`, `DIAG_SA`, functions `vmrun`, `lyon`, `bkitem`). Outputs are given for trainee `07`, session `2610`.

---

## Lab 09.1 ⭐ — Arvéo vault, Enhanced policy, protecting `web02`

### Solution
The lab steps are complete. Final checks:
```bash
az backup vault backup-properties show -g "$RG_SHARED" -n "$VAULT" \
  --query "[0].properties.storageModelType" -o tsv
az backup item list -g "$RG_SHARED" -v "$VAULT" --backup-management-type AzureIaasVM \
  --query "[].{VM:properties.friendlyName, Policy:properties.policyName, State:properties.protectionState}" -o table
./scripts/labs/module-09/mars-lyon.sh "$NN" --status
```
Expected output (protection state `IRPending` until the first backup completes `[TO VERIFY]` label):
```
LocallyRedundant
VM             Policy        State
-------------  ------------  ---------
vm-st07-web01  pol-vm-arveo  Protected
vm-st07-web02  pol-vm-arveo  IRPending
Etat     Debut                             Fin
-------  --------------------------------  -----
Running  2026-10-08T09:13:20.0145213+00:00
```

### Why
- **Script at 09:00**: the first backup of a VM is full (copy of all used disk blocks to the vault). Started at 11:00, it would at best provide a snapshot-tier point during the module. Same logic as the VPN gateways (D2) and Bastion (D3).
- **Vault in `rg-st<NN>-shared`, France Central**: a Recovery Services vault protects VMs and storage accounts of ITS region. A single vault for every Arvéo workload simplifies policies, RBAC and monitoring (module 10).
- **LRS**: cost choice for the course. In production, Arvéo would choose GRS + Cross Region Restore (loss of France Central) or ZRS (loss of a zone), a decision to make BEFORE the first protection (`Locked` state afterwards).
- **Enhanced policy (V2)**: `web01` and `web02` are Trusted Launch VMs (M7 Ubuntu 24.04 images, Gen2, secure boot and vTPM by default). The Standard policy rejects them. The Enhanced policy also brings backups every 4 h if the RPO tightens.
- **Retention**: 30 daily points + 12 weekly points (Sunday) = IT requirement; 7 days of snapshots = restore in minutes for a week (beyond that: from the vault, slower).
- **"Backup Contributor" role on the vault only**: the Lyon server identity must generate vault credentials; it needs no right anywhere else (least privilege, module 2).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `lancer-sauvegarde.sh`: `vm-stNN-web01 absente` | M7 catch-up not run or VM deleted | `./scripts/catch-up/module-07/deploy.sh <NN>` then rerun the script |
| `enable-for-vm`: policy not compatible with Trusted Launch | Standard policy (`DefaultPolicy`) chosen | Use `pol-vm-arveo` (`policyType` = `V2`) |
| `backup-properties set`: redundancy cannot be changed | An item already protected (rerun after protection) | Expected: redundancy stays as first set; recreate the vault to change it |
| `backup-now`: `UserErrorBackupOperationInProgress` | Backup already running for the VM | Wait for the end; the script detects this case |
| `RequestDisallowedByPolicy` when creating the vault | M2 policy (tags or allowed regions) | Check the tags passed; region `francecentral` allowed |
| `mars-lyon.sh`: `aucune identité managée` | Module 6 caught up without `lyon-fs-prep.sh` | `az vm identity assign -g rg-stNN-lyon -n vm-stNN-lyon-fs`, then assign the role and rerun |
| `role assignment create`: `Forbidden` | Trainee not owner of `rg-stNN-shared` | Check `az role assignment list --assignee <UPN> -g rg-stNN-shared`; trainer |

---

## Lab 09.2 ⭐⭐ — Backing up and restoring share `partage-lyon`

### Solution
```bash
# 1. Policy: 20:00 Paris time, 30 daily points
grep -E '"(scheduleRunTimes|timeZone|count)"' -A1 scripts/labs/module-09/pol-files-arveo.json
# 2. Policy in the vault
az backup policy create -g "$RG_SHARED" -v "$VAULT" -n pol-files-arveo \
  --backup-management-type AzureStorage --workload-type AzureFileShare \
  --policy @scripts/labs/module-09/pol-files-arveo.json --query name -o tsv
# 3. Protection (registers the account with the vault, 1 to 2 min)
az backup protection enable-for-azurefileshare -g "$RG_SHARED" -v "$VAULT" \
  --policy-name pol-files-arveo --storage-account "$SA_FILES" \
  --azure-file-share partage-lyon -o none
# 4. Lock set by Azure Backup
az lock list -g "$RG_DATA" --query "[].{Name:name, Level:level, Notes:notes}" -o table
```
Expected output (step 4, note text `[TO VERIFY]`):
```
Name                       Level         Notes
-------------------------  ------------  ----------------------------------------------------
AzureBackupProtectionLock  CanNotDelete  Auto-created by Azure Backup for storage accounts ...
```
```bash
# 5. On-demand backup, wait, snapshots
bkitem AzureFileShare partage-lyon
JOB=$(az backup protection backup-now -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureStorage \
  --retain-until "$(date -d '+30 days' +%d-%m-%Y)" --query name -o tsv)
az backup job wait -g "$RG_SHARED" -v "$VAULT" -n "$JOB"
az backup job show -g "$RG_SHARED" -v "$VAULT" -n "$JOB" --query properties.status -o tsv
az storage share list --account-name "$SA_FILES" --include-snapshots \
  --query "[?name=='partage-lyon'].snapshot" -o tsv
```
Expected output (internal names and timestamp vary):
```
CONT=StorageContainer;Storage;rg-st07-data;starveost07files2610 ITEM=AzureFileShare;<HASH>
Completed

2026-10-08T09:31:07.0000000Z
```
The empty line is the share itself (no snapshot).
```bash
# 6. Simulated deletion (assignment), then 7. restore of the single file
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
Expected output:
```
12
True
```

Step 8 answers:
- **a.** The recovery point is a snapshot of the share, stored IN account `starveost<NN>files<SES>` (snapshot tier). The vault only holds the metadata and drives scheduling and retention. If the account were deleted, its snapshots would disappear with it: hence the lock and the vaulted tier (copy of the data in the vault, isolated from the account) `[TO VERIFY]` regional availability.
- **b.** The `CanNotDelete` lock prevents the accidental (or malicious) deletion of the account, and therefore of the snapshots. It blocks `./scripts/cleanup/module-06-storage.sh <NN> --purge`: at the end of the course, first run `module-09-backup.sh <NN> --purge`, which unregisters the account and removes the lock.
- **c.** The Lyon server is a cache (cloud tiering): backing up `F:\Partages\Commun` with MARS would force the recall of tiered files, fill the volume and duplicate the data. The cloud endpoint is the reference copy, it will survive the closing of Lyon, and its backup depends on no server.

### Why
- **20:00**: after business hours, before the VM backup (22:00); the share is backed up in a few seconds (incremental snapshot, no transfer).
- **File-level restore, original location**: service desk need (one deleted file), without overwriting the other files changed since the point.
- **File Sync**: the restore writes into the Azure share; Azure Backup triggers change detection so the server receives the file `[TO VERIFY]` observed delay. Without it, the server would only have seen it at the 24-h detection cycle (module 6).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `enable-for-azurefileshare`: account not found | Account in another group than the vault `[TO VERIFY]` behavior of the CLI version | Pass the account ID: `--storage-account $(az storage account show -g rg-stNN-data -n <ACCOUNT> --query id -o tsv)` |
| Protection refused: network access | Account firewall (M6 bonus 2) without the trusted services exception | Add the "Trusted Microsoft services" exception or restore access |
| `policy create`: argument `--workload-type` not recognized | CLI version | Remove the option (type taken from the file) |
| Share listing: 12 files already at step 6 | Deletion run on another path | Check `--path Exploitation/tournee-03.csv` (case-sensitive) |
| `Test-Path`: `False` after 5 min | Server stopped or detection not triggered | `az vm start`; force `Invoke-AzStorageSyncChangeDetection -DirectoryPath 'Exploitation'` (lab 06.5) |
| `az storage share list`: `AuthorizationFailure` | Key access removed by mistake on the files account | `--auth-mode login` with role "Storage File Data Privileged Reader" `[TO VERIFY]` |

### Acceptable variants
- Portal: vault › **Backup** › **Azure** › **Azure File Share**, then **File Recovery** from the item. Same result, useful to show the AZ-104 path.
- Restore to another location (`--restore-mode AlternateLocation --target-storage-account --target-file-share --target-folder`): safer in production (check before copying back), slower for the service desk need.
- Policy with several backups a day (hourly schedule for shares): shorter RPO, more snapshots (per-share limit `[TO VERIFY]`).

---

## Lab 09.3 ⭐⭐ — MARS agent on the Lyon server

### Solution
Step 2 (portal): **Protected servers** › **Azure Backup Agent** shows `vm-st<NN>-lyon-fs` (Windows computer name), registration state `Registered` and the agent version.

Step 3, policy (file prepared in Cloud Shell):
```bash
mkdir -p ~/arveo-m09
cat > ~/arveo-m09/strategie-mars.ps1 <<'EOF'
Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'
$p = New-OBPolicy
Add-OBFileSpec -Policy $p -FileSpec (New-OBFileSpec -FileSpec @('F:\Compta')) | Out-Null
$days = 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'
Set-OBSchedule -Policy $p -Schedule (New-OBSchedule -DaysOfWeek $days -TimesOfDay 21:00) | Out-Null
Set-OBRetentionPolicy -Policy $p -RetentionPolicy (New-OBRetentionPolicy -RetentionDays 30) | Out-Null
Set-OBPolicy -Policy $p -Confirm:$false | Out-Null
(Get-OBPolicy | Get-OBFileSpec).FileName
Get-OBPolicy | Get-OBSchedule | Select-Object ScheduleRunDays, ScheduleRunTimes | Format-List
EOF
lyon "$(cat ~/arveo-m09/strategie-mars.ps1)"
```
Expected output (excerpt; layout `[TO VERIFY]` depending on the agent version):
```
F:\Compta
ScheduleRunDays  : {Monday, Tuesday, Wednesday, Thursday, Friday}
ScheduleRunTimes : {21:00:00}
```
Step 4, on-demand backup (1 to 3 min):
```bash
lyon "Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'; Get-OBPolicy | Start-OBBackup"
```
Expected output (end):
```
Taking snapshot of volumes...
Transferring data...
The backup operation completed successfully.
```
Portal: **Backup items** › **Azure Backup Agent**: volume `F:\` with the last point; **Backup jobs** › filter "Azure Backup Agent": `Backup` job `Completed`.

Steps 5 and 6, restore into `F:\Restauration` then copy back:
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
"$($f.FullName) -> F:\Compta ; $((Get-ChildItem F:\Compta -File).Count) files"
EOF
lyon "$(cat ~/arveo-m09/restauration-mars.ps1)"
```
Expected output (path under `F:\Restauration` `[TO VERIFY]`: original tree recreated):
```
F:\Restauration\Compta\export-2026-09-30.csv -> F:\Compta ; 6 files
```

Step 7 answers:
- **a.** In `~/.arveo/mars-passphrase.txt` (Cloud Shell); in the enterprise: a secret store (Azure Key Vault) or a physical safe, managed by another team. Stored only on the server, it disappears with it (disaster, ransomware): without it, no restore is possible, even to another server. Microsoft cannot regenerate it.
- **b.** Critical operations, with the vault security features enabled: retention reduction, stop protection with data deletion, passphrase change. The PIN is generated in the portal (vault › **Properties** › **Security PIN**), valid 5 min `[TO VERIFY]`.
- **c.** Least privilege: the identity of a server in an end-of-life site is less trustworthy than an administration account. "Backup Contributor" on the vault allows registration and management of its backups, but neither deleting the vault, nor managing access, nor changing the other resources of `rg-st<NN>-shared` (workspace, diagnostics account). Contributor on the group would allow deleting the whole vault.

### Why
- **MARS rather than VM backup**: `vm-st<NN>-lyon-fs` simulates an ON-PREMISES server (Lyon); the MARS agent is the method with no additional infrastructure for Windows files. An Azure VM backup would not apply to a real physical server in Lyon.
- **Managed identity for the vault credentials**: removes the manual download of the `.VaultCredentials` file and its copy to the server; the portal path (vault › **Backup** › "On-premises" › "Files and folders" › download agent and credentials) remains the AZ-104 exam path and that of a real on-premises server.
- **`F:\Restauration` rather than overwrite**: a restored accounting file is checked before replacing anything.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `--status`: `Failed`, `Invoke-WebRequest` error | No Internet egress in Lyon | Trainer: `./scripts/labs/module-06/lyon-nat.sh status` then `create`; rerun `mars-lyon.sh` |
| `--status`: `Failed`, `Get-AzRecoveryServicesVault` unauthorized | Role not assigned or not propagated | Check the assignment (lab 09.1 step 6), wait 5 min, rerun `mars-lyon.sh` |
| `--status`: `Failed` on `Set-OBMachineSetting` | `-SecurityPin` required by the agent version `[TO VERIFY]` | Generate the PIN (portal), then `lyon`: `Set-OBMachineSetting -EncryptionPassphrase ... -SecurityPin <PIN>` |
| `Start-OBBackup`: no policy | Step 3 not applied (syntax error) | Read the step 3 output again; `Get-OBPolicy` |
| `Get-OBRecoverableItem`: no item | Point older than the file or wrong name | List: `Get-OBRecoverableItem -Source $src`; check `PointInTime` |
| `lyon`: timeout | Long command (large initial backup) | Only beyond 90 min; here small data: check the `obengine` service |

### Acceptable variants
- MARS graphical console through an RDP session (hub Bastion to the Lyon site: not planned here, the site is not peered): same policy, "Schedule Backup" wizard.
- Policy with 3 backups a day (`-TimesOfDay 12:00, 17:00, 21:00`): MARS maximum, RPO of a few hours.
- MARS GFS retention (`New-OBRetentionPolicy` with weekly and monthly retention `[TO VERIFY]` parameters): closer to the VM policy.

---

## Lab 09.4 ⭐⭐ — Recovering the `web01` contracts through a disk restore

### Solution
```bash
# 2. Recovery points of web01
bkitem VM "vm-${ST}-web01"
TIER="join(',', properties.recoveryPointTierDetails[].type)"
az backup recoverypoint list -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
  --workload-type VM --query "[].{Name:name, Date:properties.recoveryPointTime, Tier:$TIER}" -o table
RP=$(az backup recoverypoint list -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
  --workload-type VM --query "sort_by(@, &properties.recoveryPointTime)[-1].name" -o tsv)
```
Expected output (ID and time vary; `HardenedRP` missing if the transfer is not finished):
```
Name             Date                           Tier
---------------  -----------------------------  --------------------
140738765427211  2026-10-08T07:04:12.556+00:00  InstantRP,HardenedRP
```
```bash
# 3. Disk restore (LUN 0) into rg-stNN-app
JOB=$(az backup restore restore-disks -g "$RG_SHARED" -v "$VAULT" \
  --container-name "$CONT" --item-name "$ITEM" --rp-name "$RP" \
  --storage-account "$DIAG_SA" --target-resource-group "$RG_APP" \
  --diskslist 0 --query name -o tsv)
az backup job wait -g "$RG_SHARED" -v "$VAULT" -n "$JOB"
az backup job show -g "$RG_SHARED" -v "$VAULT" -n "$JOB" --query properties.status -o tsv
# 4. Restored disks
az disk list -g "$RG_APP" --query "[?managedBy==null].{Name:name, Zone:zones[0], GB:diskSizeGB}" -o table
REST=$(az disk list -g "$RG_APP" --query "[?managedBy==null && diskSizeGB==\`32\`].name | [0]" -o tsv)
```
Expected output (3 to 10 min from the snapshot tier; generated names `[TO VERIFY]`):
```
Completed
Name                                             Zone    GB
-----------------------------------------------  ------  ----
vm-st07-web01-osdisk-20261008-120411             1       30
vm-st07-web01-datadisk-000-20261008-120411       1       32
```
```bash
# 5. Attach on LUN 1, read-only mount, copy back
az vm disk attach -g "$RG_APP" --vm-name "vm-${ST}-web01" --name "$REST" --lun 1 -o none
vmrun web01 "set -e; udevadm settle; mkdir -p /mnt/restauration
mount -o ro /dev/disk/azure/scsi1/lun1-part1 /mnt/restauration
ls /mnt/restauration/contrats | wc -l
cp -a /mnt/restauration/contrats /srv/arveo/
ls /srv/arveo/contrats | wc -l
umount /mnt/restauration"
```
Expected output:
```
5
5
```
```bash
# 6. Detach and delete ALL the restored disks
az vm disk detach -g "$RG_APP" --vm-name "vm-${ST}-web01" --name "$REST" -o none
for D in $(az disk list -g "$RG_APP" --query "[?managedBy==null].name" -o tsv); do
  az disk delete -g "$RG_APP" -n "$D" --yes -o none && echo "$D deleted"
done
```

Step 7 answers:
- **a.** "Replace existing" would have stopped `web01` and brought ALL its disks back to the 09:00 point (system included): downtime and loss of everything changed since, to recover a single folder. File recovery also fits, but requires a script, an outbound iSCSI mount (port 3260), an interactively typed password and an unmount within 12 h: more fragile to automate. The disk restore is non-intrusive and fully scriptable.
- **b.** Zone 1, that of the original VM: a zonal managed disk can only be attached to a VM of the same zone. Attaching it to `web02` (zone 2) would have failed; it would need a disk snapshot then a new disk in zone 2, or the cross-zonal restore option `[TO VERIFY]` conditions.
- **c.** A contract added at 10:30 exists in no point (last point: 09:00, next: 22:00) and was deleted at 11:55: lost. This is the 24-h RPO accepted by IT; a shorter RPO would require a policy every 4 h, or an application-level copy (sync to Azure Files, for example).

### Why
- **`--diskslist 0`**: only the data disk is useful; the OS disk is restored by the service anyway `[TO VERIFY]` selective restore behavior: hence the deletion of every unattached disk.
- **Staging account `$DIAG_SA`**: existing Standard account in France Central (module 3); the service writes the VM configuration and the deployment template there.
- **Read-only + copy**: no write on the restored copy (evidence kept), no overwrite of the live data.
- **LUN 1 and path `/dev/disk/azure/scsi1/lun1-part1`**: both disks carry the same `arveo-data` label; only the LUN-based path is unambiguous.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| No recovery point | 09:00 backup not started or failed | `az backup job list`; if failed: catch-up, or use a `web02` point to practice |
| `restore-disks`: invalid storage account | Premium account, other region or restricted network access | Use a Standard account in France Central without firewall |
| Job `Failed`: `RequestDisallowedByPolicy` | M2 policy (mandatory tags) denying the untagged restored disks | Temporary exemption on `rg-stNN-app` (trainer) or `Modify` effect `[TO VERIFY]` M2 definition |
| `vm disk attach`: zone mismatch | Restored disk without a zone or in another zone | `az disk show --query zones`; create a zonal disk from a snapshot |
| `mount`: `wrong fs type` or `cannot mount read-only` | ext4 journal to replay | `mount -o ro,noload <PARTITION> /mnt/restauration` |
| `/dev/disk/azure/scsi1/lun1-part1` missing | udev link not created (image version) `[TO VERIFY]` | `lsblk -o NAME,HCTL,SIZE,LABEL`: partition of the disk whose HCTL ends with `:1` |
| VM stuck on reboot, inconsistent `/srv/arveo` | Reboot with both `arveo-data` disks attached | Detach the restored disk, reboot |

### Acceptable variants
- File recovery (bonus 2): suited to a few files, without creating a disk.
- Restore to a NEW check VM (`vm-st<NN>-web01r`), then copy over the network: heavier (NIC, IP, cost), useful to check a whole application.
- Portal: item › **Restore VM** › **Restore disks**; same result.

---

## Challenge 09.5 ⭐⭐⭐ — Rolling `web01` back after a failed update

### Solution
```bash
# 1. Portal monitoring loop (background, file ~/arveo-m09/boucle.log)
mkdir -p ~/arveo-m09
LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
( while true; do
    R=$(curl -s --max-time 3 -w ' HTTP%{http_code}' "http://${LB_IP}/")
    echo "$(date +%T) $(grep -o 'vm-st[0-9]*-web0[12]' <<< "$R" | head -n 1) ${R##* }"
    sleep 2
  done ) > ~/arveo-m09/boucle.log 2>&1 &
LOOP=$!
tail -n 3 ~/arveo-m09/boucle.log
```
Expected output (before the restore: `web01` removed from the pool by the probe):
```
11:58:02 vm-st07-web02 HTTP200
11:58:04 vm-st07-web02 HTTP200
11:58:06 vm-st07-web02 HTTP200
```
Restore, portal path (recommended): vault `rsv-st<NN>-arveo` › **Backup items** › **Azure Virtual Machine** › `vm-st<NN>-web01` › **Restore VM** › 09:00 point › configuration **Replace existing** › staging location `starveost<NN>diag` › **Restore**. Note the start time (start of the RTO).

Restore, CLI path `[TO VERIFY]` option `--restore-mode OriginalLocation` depending on the CLI version:
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
az vm start -g "$RG_APP" -n "vm-${ST}-web01" -o none   # no effect if already started
```
Checks (step 2):
```bash
# a. local page
vmrun web01 "curl -s -o /dev/null -w '%{http_code} ' localhost; curl -s localhost | grep -o 'portail client v[0-9]'"
# b. network identity
az vm show -g "$RG_APP" -n "vm-${ST}-web01" -d \
  --query "[privateIps, networkProfile.networkInterfaces[0].id]" -o tsv | sed 's#/subscriptions/.*/##'
az network lb address-pool show -g "$RG_APP" --lb-name "lbe-${ST}-web" -n bp-web \
  --query "length(backendIPConfigurations)" -o tsv
# c. loop: errors and return of web01, then stop the loop and RTO
grep -vc 'HTTP200' ~/arveo-m09/boucle.log; grep -m1 -n 'web01' ~/arveo-m09/boucle.log
kill "$LOOP"; echo "RTO: $(( ($(date +%s) - T0) / 60 )) min"
# d. disks after the restore
az vm show -g "$RG_APP" -n "vm-${ST}-web01" \
  --query "{OS:storageProfile.osDisk.name, Data:storageProfile.dataDisks[].name}" -o json
vmrun web01 "ls /srv/arveo/contrats | wc -l"
```
Expected output (disk names and line number vary):
```
200 portail client v2
10.7.4.11	nic-st07-web01
2
0
412:12:11:46 vm-st07-web01 HTTP200
RTO: 18 min
{
  "Data": [ "vm-st07-web01-datadisk-000-<TIMESTAMP>" ],
  "OS": "vm-st07-web01-osdisk-<TIMESTAMP>"
}
5
```
- d. The `web01` disks are those recreated from the 09:00 point: `/srv/arveo/contrats` contains the 5 contracts of 09:00 (the lab 09.4 copy is overwritten by the point's state). The original disks are kept, detached, in `rg-st<NN>-app` `[TO VERIFY]` current behavior: delete them after validation (`module-09-backup.sh` deletes them, except `disk-st<NN>-web01-data`, to delete by hand if detached).

Expected procedure (runbook), in substance:
1. Confirm the incident (probe failing, `web01` out of the pool) and check that `web02` alone serves the portal.
2. Identify the last point PRIOR to the change; note the effective RPO (data lost).
3. Start a portal monitoring loop (evidence of continuity).
4. Restore `web01` with "Replace existing" and the staging account.
5. Follow the job until `Completed`; start the VM if needed.
6. Check: local page, IP and NIC, pool (probe), data content.
7. Delete the detached original disks after validation; record the RTO and the incident.

Step 4 answers:
- **a.** Effective RPO this morning: the 09:00 point (about 3 h of changes lost on `web01`; here only the failed update). Normally: 24 h (backup at 22:00). For 4 h: Enhanced policy with an hourly schedule (`scheduleRunFrequency` = `Hourly`, 4-h interval, 24-h window); cost: more snapshots and points in the vault.
- **b.** No: LRS storage, no Cross Region Restore; all the recovery points are in France Central. A GRS vault with Cross Region Restore was needed, chosen BEFORE the first protection (otherwise new vault and new protection), or a Site Recovery replication. With GRS + CRR, the restore happens in France South from the secondary copy (RPO of the vault replication, around 12 to 36 h `[TO VERIFY]`).
- **c.** Azure Site Recovery: continuous replication of the ERP VMs from France Central to France South, recovery VNet prepared (distinct or identical address plan depending on the failover), recovery plan (database then application servers, DNS reconfiguration scripts), yearly test failover in an isolated VNet, then failback. RPO of a few minutes, RTO below 1 h if the plan is tested. Backup is still needed: Site Recovery also replicates a corruption or an encryption within minutes, and keeps only recent points; only backup (immutable, long retention) can go back to before the attack.

### Why
- **Replace existing**: the only option that keeps name, NIC, IP and pool membership; "Create a VM" would require a new NIC (pool to reconfigure, different IP).
- **Monitoring loop**: proves the value of module 7 high availability during a restore (SERVICE RTO of zero, server RTO measured).
- **Point prior to the change**: the most recent point is not always the right one (a point taken AFTER a corruption restores it).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| "Replace existing" unavailable | Option limitation for some configurations `[TO VERIFY]` current list | Restore disks then swap the OS disk (`az vm update --os-disk`, VM deallocated) |
| CLI: unknown option `--restore-mode` | CLI version | Portal path; or update the CLI (recent Cloud Shell) |
| Loop: `HTTP000` errors during the restore | `web02` stopped or probe misconfigured | Check `web02` (`az vm start`) and `DipAvailability`; continuity is not proven |
| `web01` restored but out of the pool | VM not started, or nginx failing at boot | `az vm start`; `vmrun web01 "systemctl status nginx --no-pager"` |
| Job `Failed`: backup extension conflict | Extension operation in progress (AMA, Custom Script) | Wait and retry |

### Acceptable variants
- Restore the disks, then swap the OS disk of the deallocated VM (`az vm update -g <GROUP> -n <VM> --os-disk <DISK_ID>`): same result, more steps, useful if "Replace existing" is unavailable.
- Rollback through Custom Script (republish the v2 configuration of `portail-v2.sh`, module 7): faster if the cause is known; does not answer the "nobody knows how to undo" case.

---

## Bonus

1. **Soft delete**
   ```bash
   bkitem VM "vm-${ST}-web02"
   az backup protection disable -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" \
     --item-name "$ITEM" --backup-management-type AzureIaasVM --delete-backup-data true --yes -o none
   az backup item show -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" --name "$ITEM" \
     --backup-management-type AzureIaasVM \
     --query "properties.{State:protectionState, DeferredDelete:isScheduledForDeferredDelete}" -o table
   az backup protection undelete -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" \
     --item-name "$ITEM" --backup-management-type AzureIaasVM -o none
   az backup protection resume -g "$RG_SHARED" -v "$VAULT" --container-name "$CONT" \
     --item-name "$ITEM" --policy-name pol-vm-arveo -o none
   ```
   Expected output (`show` command): `DeferredDelete` = `True`, state `ProtectionStopped`. Without soft delete, an attacker with Contributor on the vault (or a hurried administrator) permanently deletes every point with one command; with it, 14 days to react. Immutability and MUA also close the "disable soft delete then delete" path.
2. **File recovery**: the Python script asks for the password shown in the portal, creates an iSCSI target and mounts the volumes under `/home/arveoadmin/<VM_NAME>-<DATE>/Volume1` `[TO VERIFY]` path. Faster for one file, but manual, limited to 12 h and dependent on outbound port 3260.
3. **Blobs**: operational backup relies on the same mechanisms as module 6 (versioning, change feed, soft delete) and adds point-in-time restore of a whole account or container, managed from a Backup vault (centralized retention, separate RBAC). Vaulted blob backup also copies the data out of the account `[TO VERIFY]` availability. Role required for the vault identity: "Storage Account Backup Contributor" on the account.
4. **Reports**:
   ```bash
   WS_ID=$(az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" --query id -o tsv)
   az monitor diagnostic-settings create -n diag-backup --resource "$(az backup vault show \
     -g "$RG_SHARED" -n "$VAULT" --query id -o tsv)" --workspace "$WS_ID" --export-to-resource-specific true \
     --logs '[{"category":"CoreAzureBackup","enabled":true},{"category":"AddonAzureBackupJobs","enabled":true}]' -o none
   ```
   Query (15 to 30 min later): `AddonAzureBackupJobs | summarize count() by JobOperation, JobStatus`.

---

## QCM — Answers
1. **B** — Replication copies every write, overwrites included; only a backup (or versioning) keeps the old version.
2. **B** — Backup storage redundancy is locked as soon as an item is protected.
3. **C** — Trusted Launch VMs are supported only by the Enhanced policy.
4. **B** — Azure Files backup creates share snapshots stored in the storage account itself.
5. **C** — Azure Backup sets lock `AzureBackupProtectionLock` (`CanNotDelete`) on the protected account.
6. **C** — The passphrase encrypts the data on the server side; neither Microsoft nor the PIN can recover it.
7. **B** — With tiering, the Azure share is the reference copy; MARS would trigger massive recalls.
8. **C** — "Replace existing" keeps the VM, its NIC, its IP and therefore its pool membership.
9. **B** — The snapshot tier restores from snapshots local to the region, with no copy from the vault.
10. **C** — Only Site Recovery continuous replication gives an RPO of a few minutes to another region.
