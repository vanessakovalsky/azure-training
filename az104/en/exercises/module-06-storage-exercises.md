# Module 06 — Exercises

Common thread: **migrating Arvéo's data to Azure**. The proofs of delivery scanned by the drivers ("POD") move to a protected Blob account, with an automated lifecycle and replicated to an archive account; this account can only be reached from the Arvéo network. The Lyon file server, created in module 5, is synchronized with Azure Files by Azure File Sync, then its content is exported with AzCopy. The accounts created here are reused in modules 8 (web application), 9 (backup) and 10 (monitoring).

| Resource | Name (trainee 07, session `2610`) | Group | Lab |
|---|---|---|---|
| Data account (Blob) | `starveost07data2610`, container `pod` | `rg-st07-data` | 06.1, 06.2 |
| Archive account | `starveost07arch2610`, containers `pod-replica`, `partage-lyon`, `pod-sync` | `rg-st07-data` | 06.2, 06.6 |
| Data access | Storage Blob Data Contributor role, policy `sap-transporteurs` | `rg-st07-data` | 06.3 |
| Private endpoint | `pe-st07-blob` (`10.7.9.4`), NIC `nic-st07-pe-blob` | `rg-st07-data` (in `snet-pe`) | 06.4 |
| Private DNS zone | `privatelink.blob.core.windows.net` | `rg-st07-hub` | 06.4 |
| File account | `starveost07files2610`, share `partage-lyon` | `rg-st07-data` | 06.5 |
| Synchronization | `sss-st07`, group `sg-partage-lyon` | `rg-st07-data` | 06.5 |
| Lyon server | `vm-st07-lyon-fs`, disk `disk-st07-lyon-fs-data` (`F:`) | `rg-st07-lyon` | 06.5 |

Variables used in all labs:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<SES>` = 4-character session code (lowercase letters and digits), provided by the trainer (e.g. `2610`)
- `<REPO_URL>` = address of the course Git repository, provided by the trainer
- `<DOMAIN>` = domain of the training tenant (e.g. `arveoformation.onmicrosoft.com`)

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`. Tag names and values stay in French: they are shared with the French-speaking groups of the same tenant.

**Variable block**: paste it into Cloud Shell (Bash) at the start of EVERY lab (session closed after 20 min of inactivity).
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
cd ~/formation 2>/dev/null || git clone <REPO_URL> ~/formation && cd ~/formation
tester() {   # tester <web|data> "<BASH COMMAND>": run on vm-stNN-test-<web|data>
  az vm run-command invoke -g "$RG_SPOKE" -n "vm-${ST}-test-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
lyon() {     # lyon "<POWERSHELL COMMAND>": run on vm-stNN-lyon-fs
  az vm run-command invoke -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" \
    --command-id RunPowerShellScript --scripts "$1" \
    --query "value[0].message" -o tsv
}
echo "$ST $SA_DATA $SA_ARCH $SA_FILES"
```
Expected result (trainee 07, session `2610`):
```
st07 starveost07data2610 starveost07arch2610 starveost07files2610
```

**Starting state**: end of module 5 after the day 2 cleanup (hub and spoke VNets, `snet-pe` in the data spoke, `arveo.internal` zone, `vm-st<NN>-lyon-fs` server and test VMs stopped, firewall and VPN gateways deleted). The `rg-st<NN>-data` group is empty. Trainee whose Lyon server is missing: `./scripts/labs/module-05/lyon-vm.sh <NN>` before the startup below.

**Day 3 startup (09:00, before the lecture)**: preparation of the Lyon server, in the background during labs 06.1 to 06.4.
```bash
./scripts/labs/module-06/lyon-fs-prep.sh "$NN"
```
Expected result (script messages in French):
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
The script also starts `vm-st<NN>-test-data` (challenge 06.4), attaches a data disk to the Lyon server, assigns it a managed identity and launches, on the server, the initialization of the `F:` volume, the creation of the share content, and the installation of the Azure File Sync agent and the PowerShell modules.

---

## Lab 06.1 ⭐ — Data account and redundancy (guided)
**Duration** : 13 min · **Objective** : create a storage account and justify its redundancy for a given need (objective 7)
**Context** : Arvéo's IT department stores the proofs of delivery in Azure. Requirements: no public data, modern encryption in transit, a copy in a second region readable even if France Central is unavailable, and long-term retention in the Archive tier.
**Prerequisites** : variable block run, Lyon server preparation launched.

### Steps
1. Test the availability of two names: an invalid name, then the name of the data account.
   ```bash
   az storage account check-name --name "st-${NN}-data" \
     --query "[nameAvailable, reason]" -o tsv
   az storage account check-name --name "$SA_DATA" --query nameAvailable -o tsv
   ```
   Expected result:
   ```
   false	AccountNameInvalid
   true
   ```
   If the second test returns `false`: name already taken (another session); notify the trainer, who provides another session code.

2. Create the account in LRS, anonymous access disabled, TLS 1.2 minimum.
   ```bash
   az storage account create -g "$RG_DATA" -n "$SA_DATA" -l "$LOC" \
     --kind StorageV2 --sku Standard_LRS --access-tier Hot \
     --min-tls-version TLS1_2 --allow-blob-public-access false \
     --tags $TAGS \
     --query "[provisioningState, primaryLocation, sku.name]" -o tsv
   ```
   Expected result (30 s to 1 min):
   ```
   Succeeded	francecentral	Standard_LRS
   ```

3. Display the endpoints of the four services.
   ```bash
   az storage account show -g "$RG_DATA" -n "$SA_DATA" \
     --query "primaryEndpoints.{Blob:blob, Files:file, Queues:queue, Tables:table}" -o table
   ```
   Expected result:
   ```
   Blob                                             Files                                            Queues                                            Tables
   -----------------------------------------------  -----------------------------------------------  ------------------------------------------------  ------------------------------------------------
   https://starveost07data2610.blob.core.windows.net/  https://starveost07data2610.file.core.windows.net/  https://starveost07data2610.queue.core.windows.net/  https://starveost07data2610.table.core.windows.net/
   ```

4. Switch the account to RA-GRS, then read the secondary region and its endpoint.
   ```bash
   az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Standard_RAGRS \
     --query "{SKU:sku.name, Secondary:secondaryLocation, State:statusOfSecondary}" -o table
   az storage account show -g "$RG_DATA" -n "$SA_DATA" \
     --query secondaryEndpoints.blob -o tsv
   ```
   Expected result:
   ```
   SKU             Secondary     State
   --------------  ------------  ---------
   Standard_RAGRS  francesouth   available
   https://starveost07data2610-secondary.blob.core.windows.net/
   ```

5. Read the geo-replication status (timestamp of the last synchronization).
   ```bash
   az storage account show -g "$RG_DATA" -n "$SA_DATA" --expand geoReplicationStats \
     --query "geoReplicationStats.{State:status, LastSync:lastSyncTime}" -o table
   ```
   Expected result (state `Bootstrap` during the first minutes, then `Live`; timestamp varies):
   ```
   State   LastSync
   ------  -------------------------
   Live    2026-10-08T07:21:44+00:00
   ```

6. Try to switch the account to Premium, then read the error message.
   ```bash
   az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Premium_LRS -o none
   ```
   Expected result: error stating that conversion between performance tiers is not supported (`[TO VERIFY]` exact wording).

7. Answer in writing:
   - a. Why RA-GRS rather than ZRS or RA-GZRS, with regard to the four requirements of the context?
   - b. What does a `LastSync` timestamp 10 min earlier than the current time mean, in case of failover?
   - c. How do you get a Premium account with the same data?

### Success criteria
- [ ] `az storage account show -g rg-st<NN>-data -n starveost<NN>data<SES> --query "[sku.name, minimumTlsVersion, allowBlobPublicAccess]" -o tsv` displays `Standard_RAGRS`, `TLS1_2`, `False`.
- [ ] The secondary endpoint ends with `-secondary.blob.core.windows.net/`.
- [ ] The three answers of step 7 are written.

---

## Lab 06.2 ⭐⭐ — Protection, replication and lifecycle of proofs of delivery (semi-autonomous)
**Duration** : 30 min · **Objective** : automate blob protection and lifecycle (objective 7)
**Context** : every day, Arvéo's drivers upload their signed proofs of delivery. The legal department requires: no loss through accidental overwrite or deletion (14 days to react), a compliance copy in a separate account, and the following internal retention policy, with no manual intervention.

| Age (since last modification) | Tier or action |
|---|---|
| 0 to 30 days | Hot (customer disputes) |
| 30 to 90 days | Cool |
| 90 to 180 days | Cold |
| 180 days to 10 years | Archive |
| More than 10 years (3,650 days) | Deletion |
| Previous versions older than 90 days | Deletion |

**Prerequisites** : lab 06.1 completed, variable block run. In this lab, data operations use the account key (`--auth-mode key`); Entra ID access is covered in 06.3.

**Assignment** :
1. Enable on `starveost<NN>data<SES>`: versioning, change feed, soft delete for blobs (14 days) and for containers (14 days).
2. Generate the sample data (provided, outside the objective):
   ```bash
   mkdir -p "$WORK/pod"
   for i in $(seq -w 1 20); do
     echo "Preuve de livraison ${i} - tournée T${i} - signée" > "$WORK/pod/pod-0${i}.txt"
   done
   ls "$WORK/pod" | wc -l
   ```
   Expected result: `20`.
3. Create the private container `pod`, then upload the 20 files into it under the prefix `2026/10/`.
4. Overwrite `2026/10/pod-001.txt` with new content (`Preuve de livraison 01 - CORRIGÉE`), then list the versions of this blob: identifier, current version or not.
5. Create a container `tmp`, delete it, display it among the deleted containers, then restore it.
6. Create the archive account `starveost<NN>arch<SES>` (Standard LRS, default tier Cool, TLS 1.2, anonymous access disabled, tags), enable its versioning and create its container `pod-replica`.
7. Create the object replication rule `pod` → `pod-replica` (blobs created since January 1, 2026) on the destination account, then apply it to the source account. After 2 to 5 min, count the blobs in `pod-replica`.
8. Write `lifecycle-pod.json` translating the retention policy of the context, apply it to the data account, then display the applied rule.
9. Archive `2026/10/pod-003.txt`, try to download it, note the error, then start its standard rehydration to Hot and display its archive status.
10. Answer in writing:
    - a. Why has no blob changed tier yet under the effect of the lifecycle rule?
    - b. The data account is in RA-GRS: what does object replication to `starveost<NN>arch<SES>` add?
    - c. Why do previous versions have their own delete action in the rule?

**Hints** :
- Blob service properties: `az storage account blob-service-properties update --enable-versioning --enable-change-feed --enable-delete-retention --delete-retention-days --enable-container-delete-retention --container-delete-retention-days`.
- Bulk upload: `az storage blob upload-batch -d <CONTAINER> -s <FOLDER> --destination-path <PREFIX> --account-name <ACCOUNT> --auth-mode key`.
- Versions: `az storage blob list ... --prefix <NAME> --include v --query "[].{Version:versionId, Current:isCurrentVersion}"`.
- Deleted containers: `az storage container list --include-deleted --query "[?deleted]"`; restore: `az storage container restore -n <NAME> --deleted-version <VERSION>`.
- Replication: `az storage account or-policy create` on the destination (options `--source-account`, `--destination-account`, `--source-container`, `--destination-container`, `--min-creation-time`), then `or-policy show` (destination) piped into `or-policy create --policy "@-"` (source).
- Lifecycle: structure `{"rules": [{"enabled", "name", "type": "Lifecycle", "definition": {"filters", "actions"}}]}`; actions `tierToCool`, `tierToCold`, `tierToArchive`, `delete` of `baseBlob` and `version`; applied with `az storage account management-policy create --policy @lifecycle-pod.json`.
- Archive and rehydration: `az storage blob set-tier --tier Archive`, then `--tier Hot --rehydrate-priority Standard`; status: `az storage blob show --query "properties.{Tier:blobTier, Archive:rehydrationStatus}"`.

**Success criteria** :
- [ ] `az storage account blob-service-properties show -g rg-st<NN>-data -n starveost<NN>data<SES> --query "[isVersioningEnabled, changeFeed.enabled, deleteRetentionPolicy.days, containerDeleteRetentionPolicy.days]" -o tsv` displays `True`, `True`, `14`, `14`.
- [ ] At least two versions of `2026/10/pod-001.txt`, only one of which is current.
- [ ] Container `tmp` present and active.
- [ ] `pod-replica` contains 20 blobs.
- [ ] `az storage account management-policy show -g rg-st<NN>-data --account-name starveost<NN>data<SES> --query "policy.rules[0].definition.actions.baseBlob"` displays the four actions and their thresholds.
- [ ] `2026/10/pod-003.txt` in state `rehydrate-pending-to-hot`.
- [ ] The three answers of step 10 are written.

---

## Exercise 06.3 ⭐⭐ — Delegated access: SAS, Entra ID and the end of keys (semi-autonomous)
**Duration** : 15 min (5 min of which before the break) · **Objective** : restrict data access with SAS and Entra ID, then prove it (objective 7)
**Context** : subcontracted carriers view the proofs of delivery of their rounds for 48 h; the billing application reads one specific blob. The CISO requires the ability to revoke one access without cutting off the others, and then an end to the use of the account keys.
**Prerequisites** : lab 06.2 completed.

**Assignment** :
1. **(10:25, before the break)** Assign yourself the "Storage Blob Data Contributor" role on the data account (propagation up to 10 min).
2. Read the `key1` key into a variable (without displaying it), generate an account SAS (Blob service, types `sco`, permissions `rl`, 2 h, HTTPS) signed with it, then list the account's containers with `curl`: expected HTTP code `200`.
3. Create on the `pod` container the stored access policy `sap-transporteurs` (`rl`, 2 h), generate a service SAS that refers to it, then list the blobs of `pod` with `curl`: `200`.
4. Delete the `sap-transporteurs` policy, wait 30 s, then replay the test of step 3.
5. Regenerate `key1`, then replay the test of step 2.
6. Generate a read-only user delegation SAS on `2026/10/pod-001.txt` (2 h), keep it in the `UD_URL` variable, then download the blob with `curl`: content `CORRIGÉE` expected.
7. Disable shared key access on the data account. List the blobs of `pod` with `--auth-mode key`, then with `--auth-mode login`, then replay the download of step 6.
8. Answer in writing:
   - a. Why does step 4 revoke access without changing the key? What other access did step 5 cut off?
   - b. Which SAS still works after step 7, and why?
   - c. As Owner of the `rg-st<NN>-data` group, why do you still need a data role in step 1?

**Hints** :
- Role: `az role assignment create --assignee <UPN> --role "Storage Blob Data Contributor" --scope <ACCOUNT_ID>`; current UPN: `az account show --query user.name -o tsv`.
- Key: `KEY1=$(az storage account keys list ... --query "[?keyName=='key1'].value" -o tsv)`.
- Expiry date: `END=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')`.
- SAS: `az storage account generate-sas`, `az storage container policy create`, `az storage container generate-sas --policy-name`, `az storage blob generate-sas --as-user --auth-mode login --full-uri`.
- HTTP test: `curl -s -o /dev/null -w "%{http_code}\n" "<URL>"`; list of containers: `https://<ACCOUNT>.blob.core.windows.net/?comp=list&<SAS>`; list of blobs: `https://<ACCOUNT>.blob.core.windows.net/pod?restype=container&comp=list&<SAS>`.
- Key: `az storage account keys renew --key key1`; disabling: `az storage account update --allow-shared-key-access false`.

**Success criteria** :
- [ ] HTTP codes recorded: `200` (step 2), `200` (step 3), `403` (step 4), `403` (step 5), `200` (steps 6 and 7).
- [ ] `az storage account show -g rg-st<NN>-data -n starveost<NN>data<SES> --query allowSharedKeyAccess -o tsv` returns `false`.
- [ ] `echo "$UD_URL"` displays a URL containing `skoid=` (variable kept for challenge 06.4).
- [ ] The three answers of step 8 are written.

---

## Challenge 06.4 ⭐⭐⭐ — Data account invisible from the Internet (autonomous)
**Duration** : 15 min in session (commented walkthrough of the solution for the others) · **Objective** : restrict network access to the account with a private endpoint, then prove it (objective 7)
**Context** : the security audit rejects any public endpoint for personal data (customer signatures). Arvéo applications in the spokes must keep reading the proofs of delivery; nothing must respond from the Internet any more, even with a valid SAS. The configuration must be versioned and replayable, like those of modules 4 and 5.

**Assignment** :
1. Write `storage-private.bicep`, deployed into `rg-st<NN>-data`, which:
   - redeclares the data account in its current state (RA-GRS, TLS 1.2, anonymous access and shared key disabled) and disables its public network access;
   - creates the private endpoint `pe-st<NN>-blob` (sub-resource `blob`) in `snet-pe` of the data spoke, with a NIC named `nic-st<NN>-pe-blob`;
   - creates, in `rg-st<NN>-hub` and through a module, the `privatelink.blob.core.windows.net` zone linked to the hub and both spokes;
   - associates the zone with the private endpoint through a DNS zone group.
2. Constraints:
   - only two mandatory parameters: trainee number and session code;
   - names and identifiers computed from these parameters;
   - `what-if` before deployment: on the account, only the network access properties change;
   - private endpoint IP provided as a deployment output.
3. BEFORE deployment: check that `UD_URL` (exercise 06.3) is still valid from Cloud Shell (`200`).
4. Deploy, then prove with five tests:
   - a. `vm-st<NN>-test-data` resolves `starveost<NN>data<SES>.blob.core.windows.net` to `10.<OCT>.9.4`;
   - b. `vm-st<NN>-test-data` downloads `UD_URL`: code `200`;
   - c. Cloud Shell downloads `UD_URL`: code `403`;
   - d. Cloud Shell lists the blobs of `pod` with `--auth-mode login`: denied;
   - e. Cloud Shell resolves the same name: CNAME chain and public address.
5. Answer in writing:
   - a. Why is a valid SAS no longer enough from the Internet (test c)?
   - b. Do object replication and the lifecycle still work? Why?
   - c. What would be needed for the Lyon server to use this private endpoint?

**Success criteria** :
- [ ] `az bicep build --file storage-private.bicep` produces no error.
- [ ] `az storage account show -g rg-st<NN>-data -n starveost<NN>data<SES> --query publicNetworkAccess -o tsv` returns `Disabled`.
- [ ] `az network private-endpoint show -g rg-st<NN>-data -n pe-st<NN>-blob --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv` returns `Approved`.
- [ ] The five tests give the expected result.
- [ ] Redeployment of the file: `what-if` with no change on the account, the private endpoint or the zone.
- [ ] The three answers of step 5 are written.

---

## Lab 06.5 ⭐⭐ — Synchronize the Lyon file server (semi-autonomous)
**Duration** : 35 min · **Objective** : synchronize an Azure Files share with the Lyon server (objective 7)
**Context** : the Lyon file server (`\\vm-st<NN>-lyon-fs\Commun`, folder `F:\Partages\Commun`) is reaching end of life. Arvéo wants an Azure Files share as the reference, with the server kept as a local cache until the site closes, without opening any inbound port in Lyon or re-establishing the VPN.
**Prerequisites** : Lyon server preparation completed; variable block run.

**Assignment** :
1. Check that the server preparation has finished:
   ```bash
   ./scripts/labs/module-06/lyon-fs-prep.sh "$NN" --status
   ```
   Expected result (script messages in French; agent and module versions vary):
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
2. Create the account `starveost<NN>files<SES>` (Standard v2, LRS, TLS 1.2, anonymous access disabled, large file shares enabled, tags), then the share `partage-lyon` (quota 100 GiB, transaction optimized tier).
3. Create the Storage Sync Service `sss-st<NN>` (France Central, tags).
4. **Portal**: in `sss-st<NN>`, create the sync group `sg-partage-lyon` with its cloud endpoint (training subscription, account `starveost<NN>files<SES>`, share `partage-lyon`).
5. Register the Lyon server in `sss-st<NN>` through its managed identity: first assign this identity the Contributor role on the Storage Sync Service only, then launch the registration on the server. Check that the server appears in "Registered servers".
6. **Portal**: add to the group the server endpoint `F:\Partages\Commun` of `vm-st<NN>-lyon-fs`, with cloud tiering enabled and 20% free space on the volume.
7. After 3 to 5 min, list the root of the share, then the `Exploitation` folder.
8. **Server → Azure**: create `F:\Partages\Commun\RH\note-migration.txt` on the server, then check that it arrives in the share.
9. **Azure → server**: upload `Qualite/consigne-qualite.txt` directly into the share; check that it is absent from the server, force change detection on the `Qualite` folder, then check again.
10. Answer in writing:
    - a. Why is no inbound port or VPN needed in Lyon?
    - b. Why an `F:` disk rather than the `C:\Partages` folder?
    - c. Without forced detection, when would `consigne-qualite.txt` have appeared on the server?

**Hints** :
- Account: `az storage account create ... --enable-large-file-share`; share: `az storage share-rm create --storage-account <ACCOUNT> -n <SHARE> --quota 100 --access-tier TransactionOptimized`.
- Storage Sync Service: `az storagesync create -g <GROUP> -n <NAME> -l <REGION> --tags ...` (`storagesync` extension installed on demand).
- Group: portal, `sss-st<NN>` › Sync groups › + Sync group.
- Server identity: `az vm show ... --query identity.principalId -o tsv`; service ID: `az storagesync show ... --query id -o tsv`; role: `az role assignment create --assignee-object-id <ID> --assignee-principal-type ServicePrincipal --role Contributor --scope <SERVICE_ID>`.
- Registration (role propagation: 1 to 5 min): `lyon "Connect-AzAccount -Identity -Subscription '<SUBSCRIPTION_ID>' | Out-Null; Register-AzStorageSyncServer -ResourceGroupName '<GROUP>' -StorageSyncServiceName '<SERVICE>' | Select-Object FriendlyName, ServerId, AgentVersion | Format-List"`.
- Server endpoint: group `sg-partage-lyon` › + Add server endpoint.
- Share content: `az storage file list --share-name partage-lyon --account-name <ACCOUNT> [--path <FOLDER>] --query "[].name" -o tsv`.
- File on the server: `lyon "Set-Content F:\Partages\Commun\RH\note-migration.txt 'Migration Azure J3'"`; test: `lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"`.
- Upload into the share: `az storage file upload --share-name partage-lyon --source <FILE> --path Qualite/consigne-qualite.txt --account-name <ACCOUNT>`.
- Forced detection (on the server, managed identity): `Get-AzStorageSyncCloudEndpoint -ResourceGroupName ... -StorageSyncServiceName ... -SyncGroupName ...` then `Invoke-AzStorageSyncChangeDetection -InputObject <CLOUD_ENDPOINT> -DirectoryPath 'Qualite' -Recursive`.

**Success criteria** :
- [ ] Portal, `sg-partage-lyon`: server endpoint in healthy state (green check mark), recent last synchronization.
- [ ] `az storage file list --share-name partage-lyon --account-name starveost<NN>files<SES> --path Exploitation --query "length(@)" -o tsv` returns `12`.
- [ ] `note-migration.txt` present in the `RH` folder of the share.
- [ ] `lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"` returns `True` after the forced detection.
- [ ] The three answers of step 10 are written.

---

## Lab 06.6 ⭐ — Export and synchronize with AzCopy (guided)
**Duration** : 15 min · **Objective** : transfer data with AzCopy and choose a transfer method (objective 7)
**Context** : before Lyon closes, the IT department requires a frozen copy of the share in the archive account, and a daily differential upload of the proofs of delivery scanned locally. It is also preparing the transfer of the datacenter's 40 TB of history.
**Prerequisites** : lab 06.5 completed (share synchronized), archive account from lab 06.2.

### Steps
1. Check the AzCopy version in Cloud Shell.
   ```bash
   azcopy --version
   ```
   Expected result (version varies):
   ```
   azcopy version 10.30.1
   ```

2. Generate two 2 h SAS: read and list on the share, then an archive account SAS (Blob, types `sco`, permissions `racwl`).
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
   Expected result: two non-zero lengths (e.g. `121 135`).

3. Copy the entire share to the archive account (account-to-account copy, server side).
   ```bash
   azcopy copy "https://${SA_FILES}.file.core.windows.net/partage-lyon?${SAS_F}" \
     "https://${SA_ARCH}.blob.core.windows.net/?${SAS_B}" --recursive
   ```
   Expected result (end of the summary; number of files depends on lab 06.5):
   ```
   Number of File Transfers: 21
   Number of File Transfers Completed: 21
   Number of File Transfers Failed: 0
   Final Job Status: Completed
   ```

4. List the created container (same name as the share).
   ```bash
   azcopy list "https://${SA_ARCH}.blob.core.windows.net/partage-lyon?${SAS_B}" | head -5
   ```
   Expected result (order varies):
   ```
   INFO: Exploitation/tournee-01.csv;  Content Length: 52.00 B
   INFO: Exploitation/tournee-02.csv;  Content Length: 52.00 B
   INFO: Qualite/audit-2024.bin;  Content Length: 100.00 MiB
   ```

5. Synchronize the local proofs of delivery folder with a `pod-sync` container, modify a file, then synchronize again.
   ```bash
   azcopy make "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}"
   azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
     | grep -E "Number of Copy Transfers Completed|Final Job Status"
   echo "Preuve de livraison 07 - RÉSERVE CLIENT" > "$WORK/pod/pod-007.txt"
   azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
     | grep -E "Number of Copy Transfers Completed|Final Job Status"
   ```
   Expected result:
   ```
   Successfully created the resource.
   Number of Copy Transfers Completed: 20
   Final Job Status: Completed
   Number of Copy Transfers Completed: 1
   Final Job Status: Completed
   ```

6. **Portal**: open the "Storage browser" of `starveost<NN>arch<SES>`, browse `partage-lyon` then `pod-replica`, and switch `Qualite/audit-2024.bin` to the Cold tier. Then open the Storage browser of `starveost<NN>data<SES>` and note the message displayed.

7. Calculate the transfer time of Lyon's 40 TB of history over the site's Internet link (100 Mbit/s), assuming the link is saturated, then at 70% efficiency. Conclude: network or Data Box, knowing that the datacenter closes its server rooms in 3 weeks?

### Success criteria
- [ ] `azcopy list ".../partage-lyon?$SAS_B" | wc -l` returns the number of files in the share.
- [ ] The second synchronization transfers exactly `1` file.
- [ ] `az storage blob show --account-name starveost<NN>arch<SES> -c partage-lyon -n Qualite/audit-2024.bin --auth-mode key --query properties.blobTier -o tsv` returns `Cold`.
- [ ] The message from the data account's Storage browser is noted and explained.
- [ ] The calculation of step 7 and the conclusion are written.

---

## Bonus 🚀
1. **Forced tiering**: on the Lyon server, force the tiering of `F:\Partages\Commun\Qualite\audit-2024.bin` (cmdlet `Invoke-StorageSyncCloudTiering` from the agent module, `C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll`). Compare its attributes and the space used on the volume before and after, then recall the file (`Invoke-StorageSyncFileRecall`).
2. **Restricted file account**: limit `starveost<NN>files<SES>` to selected networks (outbound public IP of the Lyon site, provided by the trainer, and the exception for trusted Microsoft services). Check that synchronization continues (file created on the server), then that Cloud Shell can no longer list the share. Then restore access for lab 06.6 or what follows. `[TO VERIFY]` Azure File Sync network prerequisites with a storage firewall.
3. **Full Bicep**: read `scripts/catch-up/module-06/main.bicep`, identify the resources of lab 06.5 (service, group, endpoints, roles) and explain why the object replication rule is created with Azure CLI in `deploy.sh` rather than in Bicep.

## Cleanup
- **End of morning (12:28)**:
  ```bash
  ./scripts/cleanup/module-06-storage.sh "$NN"
  ```
  Stops (deallocates) `vm-st<NN>-lyon-fs`, `vm-st<NN>-test-data` and `vm-st<NN>-test-web`. Safe to rerun.
- Kept: storage accounts, private endpoint, DNS zone, Storage Sync Service, registered server, data disk (reused in modules 8, 9 and 10).
- Full deletion of storage at the end of the course: `./scripts/cleanup/module-06-storage.sh <NN> --purge` (endpoints, registered server, Storage Sync Service, private endpoint, accounts).
- Lyon side (trainer): NAT gateway `natgw-lyon` kept until module 9 (MARS agent), deleted at the end of D4 (`lyon-nat.sh cleanup`).
- Full catch-up of the module: `./scripts/catch-up/module-06/deploy.sh <NN> <SES>` (15 to 25 min).
- Costs: storage per GB and per operation (negligible in a lab), geo-replication and object replication (GB transferred), private endpoint per hour and per GB processed, StandardSSD 32 GB disk, Windows B2s_v2 VM while it runs, shared NAT gateway per hour `[TO VERIFY]` Azure pricing calculator.
