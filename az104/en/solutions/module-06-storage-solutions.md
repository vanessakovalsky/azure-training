# Module 06 — Solutions

Examples given for trainee 07, session `2610` (`NN=07`, `OCT=7`, `SES=2610`). All solutions assume the exercises' variable block has been run in Cloud Shell (Bash), including the `tester` and `lyon` functions. Identifiers (GUIDs, versions, timestamps) vary from one run to another.

## Lab 06.1 ⭐ — Data account and redundancy

### Solution
```bash
# 1. Name availability
az storage account check-name --name "st-${NN}-data" --query "[nameAvailable, reason]" -o tsv
az storage account check-name --name "$SA_DATA" --query nameAvailable -o tsv

# 2. Creation as LRS, secured from the start
az storage account create -g "$RG_DATA" -n "$SA_DATA" -l "$LOC" \
  --kind StorageV2 --sku Standard_LRS --access-tier Hot \
  --min-tls-version TLS1_2 --allow-blob-public-access false \
  --tags $TAGS \
  --query "[provisioningState, primaryLocation, sku.name]" -o tsv
```
Expected output:
```
false	AccountNameInvalid
true
Succeeded	francecentral	Standard_LRS
```

```bash
# 3. Endpoints
az storage account show -g "$RG_DATA" -n "$SA_DATA" \
  --query "primaryEndpoints.{Blob:blob, Files:file, Queues:queue, Tables:table}" -o table

# 4. Switch to RA-GRS
az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Standard_RAGRS \
  --query "{SKU:sku.name, Secondary:secondaryLocation, State:statusOfSecondary}" -o table
az storage account show -g "$RG_DATA" -n "$SA_DATA" --query secondaryEndpoints.blob -o tsv

# 5. Geo-replication status
az storage account show -g "$RG_DATA" -n "$SA_DATA" --expand geoReplicationStats \
  --query "geoReplicationStats.{State:status, LastSync:lastSyncTime}" -o table
```
Expected output (steps 4 and 5):
```
SKU             Secondary    State
--------------  -----------  ---------
Standard_RAGRS  francesouth  available
https://starveost07data2610-secondary.blob.core.windows.net/
State  LastSync
-----  -------------------------
Live   2026-10-08T07:21:44+00:00
```

```bash
# 6. Standard → Premium: refused
az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Premium_LRS -o none
```
Expected output (wording `[TO VERIFY]`): error `400`, SKU change between Standard and Premium not supported.

Expected answers (step 7):
- a. Four requirements: nothing public (account settings, regardless of redundancy), TLS 1.2 (same), readable copy in a second region (G + RA), Archive tier. ZRS does not copy outside France Central; RA-GZRS covers both regions but does not accept the Archive tier. RA-GRS is the only option that satisfies all four.
- b. Writes from the last 10 minutes are not yet on the secondary: in the event of a failover, they are lost (RPO ≈ 10 min at that moment). `Last Sync Time` is used to assess this loss BEFORE deciding on a failover.
- c. Performance is fixed at creation: create a Premium block blob account (`--kind BlockBlobStorage --sku Premium_LRS`), copy the data from account to account with AzCopy, then repoint the applications.

### Why
- `check-name` first: uniqueness is global across Azure; a creation failure in the middle of a script costs more than a test.
- Creation as LRS then switch to RA-GRS: shows that an LRS ↔ GRS ↔ RA-GRS change is a simple update, with no migration or interruption.
- `--allow-blob-public-access false`: forbids any anonymous container on the account, even if a container is later created with a public level.
- `--min-tls-version TLS1_2`: rejects obsolete clients at the service level, without depending on their configuration.
- `--access-tier Hot`: default tier for new blobs; proofs of delivery are consulted for 30 days.
- `geoReplicationStats`: the only indicator of the secondary's lag; state `Bootstrap` as long as the initial copy is not complete.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `check-name` returns `false` for `starveost<NN>data<SES>` | Name taken by another session or another tenant | New session code provided by the trainer |
| `RequestDisallowedByPolicy` | Tags missing (`$TAGS` not defined: variable block not pasted again) | Paste the block again, `echo $TAGS`, rerun |
| `StorageAccountAlreadyTaken` | Account created by another trainee with the same number | Check `NN`; notify the trainer |
| `geoReplicationStats` empty | `--expand geoReplicationStats` forgotten, or account still in LRS | Add the option; check `sku.name` |
| Persistent `Bootstrap` state | Initial copy to France South in progress | Wait; no impact on the rest of the lab |

### Acceptable variants
- Creation via the Portal ("Basics", "Advanced", "Networking" tabs): acceptable, same properties to check with `az storage account show`.
- Direct creation as `Standard_RAGRS`: correct; step 4 then has no effect.
- PowerShell: `New-AzStorageAccount -SkuName Standard_RAGRS -Kind StorageV2 -MinimumTlsVersion TLS1_2 -AllowBlobPublicAccess $false`.

## Lab 06.2 ⭐⭐ — Protection, replication and lifecycle of proofs of delivery

### Solution
```bash
# 1. Blob service data protection
az storage account blob-service-properties update -g "$RG_DATA" -n "$SA_DATA" \
  --enable-versioning true --enable-change-feed true \
  --enable-delete-retention true --delete-retention-days 14 \
  --enable-container-delete-retention true --container-delete-retention-days 14 \
  --query "[isVersioningEnabled, changeFeed.enabled, deleteRetentionPolicy.days, containerDeleteRetentionPolicy.days]" \
  -o tsv
```
Expected output:
```
True	True	14	14
```

```bash
# 2. Sample data (instructions)
mkdir -p "$WORK/pod"
for i in $(seq -w 1 20); do
  echo "Preuve de livraison ${i} - tournée T${i} - signée" > "$WORK/pod/pod-0${i}.txt"
done

# 3. Private container and upload
az storage container create -n pod --public-access off \
  --account-name "$SA_DATA" --auth-mode key -o tsv
az storage blob upload-batch -d pod -s "$WORK/pod" --destination-path 2026/10 \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage blob list -c pod --prefix 2026/10/ \
  --account-name "$SA_DATA" --auth-mode key --query "length(@)" -o tsv
```
Expected output:
```
True
20
```

```bash
# 4. Overwrite and versions
echo "Preuve de livraison 01 - CORRIGÉE" > "$WORK/pod-001-v2.txt"
az storage blob upload -c pod -n 2026/10/pod-001.txt -f "$WORK/pod-001-v2.txt" --overwrite \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage blob list -c pod --prefix 2026/10/pod-001.txt --include v \
  --account-name "$SA_DATA" --auth-mode key \
  --query "[].{Version:versionId, Current:isCurrentVersion}" -o table
```
Expected output:
```
Version                       Current
----------------------------  -------
2026-10-08T07:41:12.3856172Z
2026-10-08T07:44:03.1029840Z  True
```

```bash
# 5. Container soft delete
az storage container create -n tmp --account-name "$SA_DATA" --auth-mode key -o none
az storage container delete -n tmp --account-name "$SA_DATA" --auth-mode key -o none
DELV=$(az storage container list --include-deleted --account-name "$SA_DATA" --auth-mode key \
  --query "[?name=='tmp' && deleted].version | [0]" -o tsv)
echo "$DELV"
sleep 30
az storage container restore -n tmp --deleted-version "$DELV" \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage container list --account-name "$SA_DATA" --auth-mode key --query "[].name" -o tsv
```
Expected output:
```
01DB3F7A2C9E4D10
pod
tmp
```

```bash
# 6. Archive account, replication destination
az storage account create -g "$RG_DATA" -n "$SA_ARCH" -l "$LOC" \
  --kind StorageV2 --sku Standard_LRS --access-tier Cool \
  --min-tls-version TLS1_2 --allow-blob-public-access false --tags $TAGS -o none
az storage account blob-service-properties update -g "$RG_DATA" -n "$SA_ARCH" \
  --enable-versioning true -o none
az storage container create -n pod-replica --account-name "$SA_ARCH" --auth-mode key -o none

# 7. Object replication: destination first, then source
POLICY_ID=$(az storage account or-policy create -g "$RG_DATA" --account-name "$SA_ARCH" \
  --source-account "$SA_DATA" --destination-account "$SA_ARCH" \
  --source-container pod --destination-container pod-replica \
  --min-creation-time '2026-01-01T00:00:00Z' --query policyId -o tsv)
az storage account or-policy show -g "$RG_DATA" --account-name "$SA_ARCH" --policy-id "$POLICY_ID" \
  | az storage account or-policy create -g "$RG_DATA" --account-name "$SA_DATA" --policy "@-" \
    --query "[policyId, rules[0].ruleId]" -o tsv
sleep 180
az storage blob list -c pod-replica --account-name "$SA_ARCH" --auth-mode key \
  --query "length(@)" -o tsv
```
Expected output:
```
1f3c6a2e-0b7d-4c55-9e1a-6d2f8b0c4e91	7a90e3c4-52d1-4c6b-8f0e-3b2a1d9c5e77
20
```
Optional check, replication status of a source blob (property name `[TO VERIFY]` depending on the Azure CLI version):
```bash
az storage blob show -c pod -n 2026/10/pod-010.txt --account-name "$SA_DATA" --auth-mode key \
  --query "objectReplicationSourceProperties[0].rules[0].status" -o tsv
```
Expected output: `complete`.

File `lifecycle-pod.json` (identical to `scripts/catch-up/module-06/lifecycle-pod.json`):
```json
{
  "rules": [
    {
      "enabled": true,
      "name": "pod-cycle-de-vie",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": [ "blockBlob" ],
          "prefixMatch": [ "pod/" ]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": { "daysAfterModificationGreaterThan": 30 },
            "tierToCold": { "daysAfterModificationGreaterThan": 90 },
            "tierToArchive": { "daysAfterModificationGreaterThan": 180 },
            "delete": { "daysAfterModificationGreaterThan": 3650 }
          },
          "version": {
            "delete": { "daysAfterCreationGreaterThan": 90 }
          }
        }
      }
    }
  ]
}
```

```bash
# 8. Applying the lifecycle management rule
cp scripts/catch-up/module-06/lifecycle-pod.json "$WORK/"   # or file written by the trainee
az storage account management-policy create -g "$RG_DATA" --account-name "$SA_DATA" \
  --policy @"$WORK/lifecycle-pod.json" -o none
az storage account management-policy show -g "$RG_DATA" --account-name "$SA_DATA" \
  --query "policy.rules[0].definition.actions.baseBlob" -o json
```
Expected output (null properties omitted):
```
{
  "delete": { "daysAfterModificationGreaterThan": 3650.0 },
  "tierToArchive": { "daysAfterModificationGreaterThan": 180.0 },
  "tierToCold": { "daysAfterModificationGreaterThan": 90.0 },
  "tierToCool": { "daysAfterModificationGreaterThan": 30.0 }
}
```

```bash
# 9. Archive, read refused, rehydration
az storage blob set-tier -c pod -n 2026/10/pod-003.txt --tier Archive \
  --account-name "$SA_DATA" --auth-mode key
az storage blob download -c pod -n 2026/10/pod-003.txt -f "$WORK/pod-003.txt" \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage blob set-tier -c pod -n 2026/10/pod-003.txt --tier Hot --rehydrate-priority Standard \
  --account-name "$SA_DATA" --auth-mode key
az storage blob show -c pod -n 2026/10/pod-003.txt --account-name "$SA_DATA" --auth-mode key \
  --query "properties.{Tier:blobTier, Archive:rehydrationStatus}" -o table
```
Expected output:
```
ERROR: This operation is not permitted on an archived blob.
ErrorCode:BlobArchived
Tier     Archive
-------  ------------------------
Archive  rehydrate-pending-to-hot
```

Expected answers (step 10):
- a. All blobs were modified today (30-day threshold not reached); moreover, the platform runs the rules once a day, with a first pass within 24 to 48 h after the rule is created.
- b. A copy under Arvéo's control: separate account (deleting the source account has no effect on the copy, separate access rights), choice of container, Cool tier at lower cost, copy always readable and movable to another region or another subscription. The RA-GRS secondary, on the other hand, is managed by Microsoft, read-only, and disappears with the account.
- c. With versioning, each overwrite creates a billed previous version; `baseBlob` actions apply only to the current version. Without a `version` action, versions would accumulate indefinitely.

### Why
- Versioning + blob soft delete + container soft delete: three different risks (overwrite, deletion of a blob, deletion of a container); 14 days = reaction time requested by the legal department.
- Change feed: prerequisite for object replication on the source; it is also used for auditing (log of creations, modifications, deletions).
- Object replication created before archiving `pod-003`: the initial copy covers the 20 blobs; a tier change in the source is not replicated.
- `--min-creation-time` set to 1 January 2026: blobs uploaded before the rule are copied too; without this option, only new blobs would be.
- Rule created on the destination then copied to the source: the destination generates `policyId` and `ruleId`; the source must carry exactly the same identifiers.
- Archive account in Cool by default: compliance copy rarely read.
- Lifecycle based on the modification date: last access tracking is not enabled (additional operations cost, no business need).
- Rehydration with standard priority: no urgency; high priority is billed more.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `There are no credentials provided in your command and environment` (warning) | `--auth-mode` omitted: the CLI reads the key itself | No effect; specify `--auth-mode key` in this lab |
| `container restore`: `ContainerBeingDeleted` | Restore launched during deletion | Wait 30 s, rerun |
| `container restore`: `--deleted-version` empty | JMESPath query without `deleted`, or container never deleted | `az storage container list --include-deleted -o table` |
| `or-policy create`: versioning or change feed required | Step 1 incomplete, or versioning not enabled on the destination | Enable `--enable-versioning` (2 accounts) and `--enable-change-feed` (source) |
| `or-policy create` (source): `InvalidRequestPropertyValue` | Source rule created without copying `policyId` and `ruleId` from the destination | Use `or-policy show ... | or-policy create --policy "@-"` |
| `pod-replica` empty after 5 min | Rule missing from the source, or `--min-creation-time` later than the blobs | `az storage account or-policy list --account-name $SA_DATA`; recreate the rule |
| `management-policy create`: invalid JSON | Trailing comma, typographic quotes, prefix without the container name | `python3 -m json.tool lifecycle-pod.json`; `prefixMatch` starts with `pod/` |
| `set-tier --tier Archive` refused | Account in ZRS, GZRS or RA-GZRS | Lab 06.1: account in RA-GRS |
| `rehydrationStatus` empty | Property name differs depending on the CLI version | Display `-o json` and look for `archiveStatus` |

### Acceptable variants
- Portal: the account's "Data protection", "Lifecycle management" (graphical wizard, "Code view" tab for the JSON), "Object replication" (rule created in one go on both accounts).
- Bicep: `blobServices` (versioning, change feed, retentions) and `managementPolicies` fed by `loadJsonContent('lifecycle-pod.json')`; this is the approach of `scripts/catch-up/module-06/main.bicep`.
- Time-based immutability policy (WORM, 10 years) on `pod` instead of soft delete alone: stronger protection (compliance, ransomware), but irreversible once locked; to be validated by the legal department.
- `daysAfterLastAccessTimeGreaterThan` condition with last access tracking: relevant if late consultations are frequent (add `enableAutoTierToHotFromCool`).

## Exercise 06.3 ⭐⭐ — Delegated access: SAS, Entra ID and the end of keys

### Solution
```bash
# 1. Data role for yourself (10:25)
SA_ID=$(az storage account show -g "$RG_DATA" -n "$SA_DATA" --query id -o tsv)
ME=$(az account show --query user.name -o tsv)
az role assignment create --assignee "$ME" --role "Storage Blob Data Contributor" \
  --scope "$SA_ID" --query roleDefinitionName -o tsv
```
Expected output:
```
Storage Blob Data Contributor
```

```bash
# 2. Account SAS signed with key1
END=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')
BLOB="https://${SA_DATA}.blob.core.windows.net"
KEY1=$(az storage account keys list -g "$RG_DATA" -n "$SA_DATA" \
  --query "[?keyName=='key1'].value" -o tsv)
SAS_ACC=$(az storage account generate-sas --account-name "$SA_DATA" --account-key "$KEY1" \
  --services b --resource-types sco --permissions rl --expiry "$END" --https-only -o tsv)
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/?comp=list&${SAS_ACC}"

# 3. Stored access policy and service SAS
az storage container policy create --account-name "$SA_DATA" --account-key "$KEY1" \
  -c pod -n sap-transporteurs --permissions rl --expiry "$END" -o none
SAS_SVC=$(az storage container generate-sas --account-name "$SA_DATA" --account-key "$KEY1" \
  -n pod --policy-name sap-transporteurs -o tsv)
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/pod?restype=container&comp=list&${SAS_SVC}"

# 4. Revocation by deleting the policy
az storage container policy delete --account-name "$SA_DATA" --account-key "$KEY1" \
  -c pod -n sap-transporteurs -o none
sleep 30
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/pod?restype=container&comp=list&${SAS_SVC}"

# 5. Regenerating key1
az storage account keys renew -g "$RG_DATA" -n "$SA_DATA" --key key1 -o none
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/?comp=list&${SAS_ACC}"
```
Expected output:
```
200
200
403
403
```

```bash
# 6. User delegation SAS (variable kept for challenge 06.4)
UD_URL=$(az storage blob generate-sas --account-name "$SA_DATA" -c pod -n 2026/10/pod-001.txt \
  --permissions r --expiry "$END" --https-only --auth-mode login --as-user --full-uri -o tsv)
curl -s "$UD_URL"

# 7. End of keys
az storage account update -g "$RG_DATA" -n "$SA_DATA" --allow-shared-key-access false \
  --query allowSharedKeyAccess -o tsv
az storage blob list -c pod --account-name "$SA_DATA" --auth-mode key --query "length(@)" -o tsv
az storage blob list -c pod --account-name "$SA_DATA" --auth-mode login --query "length(@)" -o tsv
curl -s -o /dev/null -w "%{http_code}\n" "$UD_URL"
```
Expected output:
```
Preuve de livraison 01 - CORRIGÉE
false
ERROR: Key based authentication is not permitted on this storage account.
ErrorCode:KeyBasedAuthenticationNotPermitted
20
200
```

Expected answers (step 8):
- a. The service SAS carries only the name of the stored access policy; permissions and expiry are read from the container on each request. Policy deleted = SAS invalid (within 30 s), key intact, other access intact. Regenerating `key1` (step 5) invalidated ALL SAS signed with it: the account SAS, but also the service SAS from step 3, and any application using `key1`.
- b. The user delegation SAS: it is signed by a delegation key obtained with the trainee's Entra ID identity, not by an account key; it is affected neither by `allowSharedKeyAccess` nor by key rotation. It remains limited by its issuer's RBAC rights at the time of use, and by its expiry.
- c. `Owner` is a control plane role: it includes no `dataAction`. Access to blobs through Entra ID (`--auth-mode login`, delegation key) requires a data role such as "Storage Blob Data Contributor". Without it, only indirect access by reading the keys was possible, and it has just been closed.

### Why
- Role assigned first: propagation up to 10 min, absorbed by the break.
- Key read into a variable, never displayed: it must appear neither on the projected screen nor in a file.
- Tests with `curl` and HTTP code: proof independent of the CLI, as a carrier would see it.
- Short SAS (2 h) and `--https-only`: minimal exposure surface if a URL leaks (proxy log, email).
- Stored access policy for carriers: targeted revocation of a group of SAS without key rotation (5 policies maximum per container).
- User delegation for the application: no key to store, issuer identified in the logs, maximum duration of 7 days.
- Shared key disabled last: verified without risk, Entra ID access already being in place (step 1).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Step 2 or 3: `403` instead of `200` | `&` missing between the URL and the SAS, or no quotes around the URL | Copy the command again; the URL must be in double quotes |
| Step 3: `403`, `AuthenticationFailed` | Stored access policy not yet active (up to 30 s) | Wait 30 s, rerun |
| Step 4: still `200` | Test run less than 30 s after deletion | Wait, rerun |
| Step 6: `AuthorizationPermissionMismatch` | Data role not yet propagated | Wait up to 10 min; check `az role assignment list --scope $SA_ID -o table` |
| Step 6: `--as-user` refused | `--auth-mode login` missing | The two options go together |
| `date: invalid date` | Command run outside Cloud Shell (macOS, BSD `date`) | Cloud Shell, or `date -u -v+2H '+%Y-%m-%dT%H:%MZ'` on macOS |
| Portal: containers unreadable after step 7 | Portal configured for the access key | Account › Configuration › "Default to Microsoft Entra authorization in the Azure portal"; or toggle "Authentication method" in the container |

### Acceptable variants
- Role assigned at the `pod` container level (`--scope "$SA_ID/blobServices/default/containers/pod"`): more restrictive, correct.
- "Storage Blob Data Reader" + "Storage Blob Delegator" roles for an application that only reads and issues SAS: least privilege, recommended for the billing application.
- Revocation by a stored access policy with a modified expiry (past date) rather than deleted: equivalent, keeps the history.

## Challenge 06.4 ⭐⭐⭐ — Data account invisible from the Internet

### Solution
File `storage-private.bicep` (identical to `scripts/catch-up/module-06/storage-private.bicep`):
```bicep
// storage-private.bicep — compte de données Arvéo joignable uniquement depuis le réseau Arvéo
// Solution du défi 06.4. Déployé dans rg-stNN-data.
//   - compte starveostNNdata<SES> redéclaré À L'IDENTIQUE de l'état des labs 06.1 à 06.3
//     (une déclaration de compte est un remplacement complet de ses propriétés), avec
//     publicNetworkAccess à Disabled
//   - private endpoint pe-stNN-blob (sous-ressource blob) dans snet-pe du spoke données
//   - zone privatelink.blob.core.windows.net dans rg-stNN-hub (module private-dns.bicep)
//     et groupe de zones DNS : enregistrement A créé et maintenu par la plateforme
// Déploiement :
//   az deployment group create -g rg-stNN-data -f storage-private.bicep -p numero=NN session=<SES>
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Code de session (4 caractères, minuscules et chiffres), fourni par la formatrice')
@minLength(4)
@maxLength(4)
param session string

@description('Région du compte et du private endpoint')
param location string = 'francecentral'

@description('Accès public au compte : Disabled (cible du défi) ; Enabled réservé au rattrapage')
@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = 'Disabled'

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var peSubnetId = resourceId('rg-${prefix}-spoke', 'Microsoft.Network/virtualNetworks/subnets',
  'vnet-${prefix}-spoke-data', 'snet-pe')

// ---------- Compte de données (état des labs 06.1 à 06.3) ----------
resource dataAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'starveost${numero}data${session}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_RAGRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Disabled' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ---------- DNS privé (hub) ----------
module dns 'private-dns.bicep' = {
  name: 'private-dns-blob'
  scope: resourceGroup('rg-${prefix}-hub')
  params: {
    numero: numero
  }
}

// ---------- Private endpoint ----------
resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${prefix}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    customNetworkInterfaceName: 'nic-${prefix}-pe-blob'
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-blob'
        properties: {
          privateLinkServiceId: dataAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: dns.outputs.zoneId
        }
      }
    ]
  }
}

// IP lue sur la carte réseau créée par la plateforme, nommée par customNetworkInterfaceName
// (customDnsConfigs peut être vide quand un groupe de zones DNS est associé)
resource peNic 'Microsoft.Network/networkInterfaces@2023-11-01' existing = {
  name: 'nic-${prefix}-pe-blob'
}

output privateEndpointIp string = peNic.properties.ipConfigurations[0].properties.privateIPAddress
output blobEndpoint string = dataAccount.properties.primaryEndpoints.blob
output accountName string = dataAccount.name
```

Module `private-dns.bicep` (same folder):
```bicep
// private-dns.bicep — zone DNS privée des private endpoints Blob, déployée dans rg-stNN-hub
// Module de storage-private.bicep (défi 06.4) et de main.bicep (rattrapage M6).
// Zone privatelink.blob.core.windows.net liée au hub et aux deux spokes (sans enregistrement
// automatique : une seule zone d'enregistrement par VNet, déjà arveo.internal au M4).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

var prefix = 'st${numero}'
var spokeRg = 'rg-${prefix}-spoke'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var vnets = [
  {
    link: 'link-hub'
    id: resourceId('Microsoft.Network/virtualNetworks', 'vnet-${prefix}-hub')
  }
  {
    link: 'link-spoke-app'
    id: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-app')
  }
  {
    link: 'link-spoke-data'
    id: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-data')
  }
]

resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for v in vnets: {
  parent: blobZone
  name: v.link
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: v.id
    }
    registrationEnabled: false
  }
}]

output zoneId string = blobZone.id
```

Check, SAS before deployment, preview, deployment:
```bash
cd ~/formation/scripts/catch-up/module-06      # or folder of the file written by the trainee
az bicep build --file storage-private.bicep --stdout > /dev/null && echo "Syntaxe OK"
curl -s -o /dev/null -w "%{http_code}\n" "$UD_URL"
az deployment group what-if -g "$RG_DATA" -f storage-private.bicep -p numero="$NN" session="$SES"
az deployment group create -g "$RG_DATA" -n storage-private -f storage-private.bicep \
  -p numero="$NN" session="$SES" --query "properties.outputs.privateEndpointIp.value" -o tsv
cd ~/formation
```
Expected `what-if` output (end, property details partially omitted; `+` or `~` on `publicNetworkAccess` depending on whether the property was set):
```
Scope: /subscriptions/<ID>/resourceGroups/rg-st07-data
  ~ Microsoft.Storage/storageAccounts/starveost07data2610 [2023-05-01]
    + properties.publicNetworkAccess:      "Disabled"
    ~ properties.networkAcls.defaultAction: "Allow" => "Deny"
  + Microsoft.Network/privateEndpoints/pe-st07-blob [2023-11-01]
  + Microsoft.Network/privateEndpoints/pe-st07-blob/privateDnsZoneGroups/default [2023-11-01]
Scope: /subscriptions/<ID>/resourceGroups/rg-st07-hub
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net [2020-06-01]
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-hub
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-spoke-app
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-spoke-data

Resource changes: 6 to create, 1 to modify.
```
Then, after 2 to 4 min: `Syntaxe OK`, `200` (before), then `10.7.9.4`.

Tests:
```bash
tester data "getent hosts ${SA_DATA}.blob.core.windows.net"                      # a
tester data "curl -s -o /dev/null -w '%{http_code}\n' '${UD_URL}'"                # b
curl -s -o /dev/null -w "%{http_code}\n" "$UD_URL"                                 # c
az storage blob list -c pod --account-name "$SA_DATA" --auth-mode login -o none   # d
nslookup "${SA_DATA}.blob.core.windows.net" | tail -n +3                           # e
```
Expected output (30 to 60 s per test run on the VM; names and public address vary):
```
10.7.9.4        starveost07data2610.privatelink.blob.core.windows.net starveost07data2610.blob.core.windows.net
200
403
ERROR: This request is not authorized to perform this operation.
ErrorCode:AuthorizationFailure
Non-authoritative answer:
starveost07data2610.blob.core.windows.net	canonical name = starveost07data2610.privatelink.blob.core.windows.net.
starveost07data2610.privatelink.blob.core.windows.net	canonical name = blob.par21prdstr02a.store.core.windows.net.
Name:	blob.par21prdstr02a.store.core.windows.net
Address: <PUBLIC_IP>
```

Expected answers (step 5):
- a. Network and authorization are two independent layers, evaluated in this order: with `publicNetworkAccess = Disabled`, the service rejects any request arriving through the public endpoint BEFORE examining the SAS. A valid SAS proves a right, not an origin.
- b. Yes: lifecycle management and object replication are executed by the storage platform itself, not by a client going through the public endpoint `[TO VERIFY]` documented behavior of object replication with a source account without public access. Simple check: a new blob uploaded from the Arvéo network (module 8) must appear in `pod-replica`.
- c. Three conditions: a network path (the VPN tunnel from module 5, deleted that evening, or ExpressRoute) with the Lyon → `snet-pe` firewall rules (TCP 443); DNS resolution to `10.<OCT>.9.4` from Lyon: a conditional forwarder for the `blob.core.windows.net` zone on the Lyon DNS to an Azure DNS Private Resolver inbound endpoint in the hub (the private zone cannot be queried directly from Lyon); and, if traffic must go through the firewall, network policies enabled on the `snet-pe` subnet so that UDRs apply to the private endpoint.

### Why
- Account redeclared in full: a `storageAccounts` resource declared in Bicep replaces all of its properties; an omitted property (`allowSharedKeyAccess`) would revert to its default value and reopen key access. The `what-if` is precisely there to detect this.
- `publicNetworkAccess: 'Disabled'` rather than `networkAcls` alone: explicit disabling, readable by Azure Policy; `defaultAction: 'Deny'` for consistency, in case public access is reopened by mistake.
- `bypass: 'AzureServices'`: no effect when public access is disabled; useful if the account goes back to "selected networks" (trusted Microsoft services such as Azure Backup in M9).
- Private endpoint in `snet-pe` (data spoke): dedicated subnet planned in M4, no NSG or UDR at this stage; IP `10.<OCT>.9.4` = first usable address (the first 4 are reserved by Azure).
- `customNetworkInterfaceName`: NIC name compliant with the convention instead of the generated name `pe-stNN-blob.nic.<GUID>`.
- Zone in the hub, linked to the three VNets: M4 hub-spoke model (centralized DNS); the zone belongs to the hub, not to the account, and will serve all future Blob private endpoints.
- DNS zone group: the A record follows the private endpoint's lifecycle (created, updated, deleted with it); no manual record to maintain.
- `environment().suffixes.storage`: correct zone name regardless of the Azure cloud (public, sovereign).
- `UD_URL` generated before deployment: the delegation key is requested from the Blob service, unreachable from Cloud Shell once public access is disabled.
- Test e: from the Internet, the `privatelink` CNAME also exists, but the public zone resolves it to the public IP; only the private zone linked to the Arvéo VNets returns the private IP.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `what-if`: `allowSharedKeyAccess: false => true` (or property removed) | Account partially redeclared | Copy all properties from the current state (`az storage account show`) |
| `PrivateEndpointCannotBeCreatedInSubnetThatHasNetworkPoliciesEnabled` `[TO VERIFY]` wording | Network policies enabled on `snet-pe` (older APIs) | `az network vnet subnet update ... -n snet-pe --private-endpoint-network-policies Disabled` |
| `AuthorizationFailed` on the DNS zone | Module deployed in the wrong group (`scope` missing) | `scope: resourceGroup('rg-${prefix}-hub')` |
| Test a: public address on the VM | Zone not linked to `vnet-stNN-spoke-data`, or zone group missing | `az network private-dns link vnet list -g rg-stNN-hub -z privatelink.blob.core.windows.net -o table` |
| Test b: `403` from the VM | `UD_URL` expired (more than 2 h) or generated after deployment | Reopen public access (`publicNetworkAccess=Enabled` parameter), generate a new SAS, redeploy as `Disabled` |
| Test b: timeout (`000`) | `vm-stNN-test-data` stopped | `az vm start -g rg-stNN-spoke -n vm-stNN-test-data` |
| Test a or b: `Conflict` on `run-command` | Another command running on the VM | One command at a time; wait 1 min |
| `RequestDisallowedByPolicy` on the network interface | NIC created by the platform without tags (M2 policy) `[TO VERIFY]` | Notify the trainer (exclusion of the `networkInterfaces` type planned in the guide) |

### Acceptable variants
- Private endpoint and zone with Azure CLI (`az network private-endpoint create`, `az network private-dns zone create`, `az network private-dns link vnet create`, `az network private-endpoint dns-zone-group create`) then `az storage account update --public-network-access Disabled`: technically correct, outside the "versioned and replayable" constraint.
- DNS zone in `rg-stNN-data`: works, but scatters DNS resolution per application; to be avoided in hub-spoke.
- `Microsoft.Storage` service endpoint on `snet-data` + "selected networks" access: free, but the account keeps a public IP and Lyon could never use it; does not meet the audit requirement.
- Azure Policy "Configure private endpoints / disable public network access for storage accounts" (`DeployIfNotExists` or `Modify` effect): enterprise approach, beyond trainee rights (definitions at subscription level, M2).

## Lab 06.5 ⭐⭐ — Synchronize the Lyon file server

### Solution
```bash
# 1. End of server preparation
./scripts/labs/module-06/lyon-fs-prep.sh "$NN" --status

# 2. Files account and share
az storage account create -g "$RG_DATA" -n "$SA_FILES" -l "$LOC" \
  --kind StorageV2 --sku Standard_LRS --min-tls-version TLS1_2 \
  --allow-blob-public-access false --enable-large-file-share --tags $TAGS -o none
az storage share-rm create -g "$RG_DATA" --storage-account "$SA_FILES" -n partage-lyon \
  --quota 100 --access-tier TransactionOptimized \
  --query "{Share:name, Quota:shareQuota, Tier:accessTier}" -o table

# 3. Storage Sync Service
az storagesync create -g "$RG_DATA" -n "$SSS" -l "$LOC" --tags $TAGS \
  --query provisioningState -o tsv
```
Expected output (steps 2 and 3):
```
Share         Quota  Tier
------------  -----  --------------------
partage-lyon  100    TransactionOptimized
Succeeded
```

**4. Portal**: `sss-st07` › Sync groups › + Sync group:
- Name: `sg-partage-lyon`;
- Cloud endpoint: training subscription, account `starveost07files2610`, share `partage-lyon`;
- Create. The Portal grants the "Microsoft.StorageSync" service principal the necessary rights on the account (`[TO VERIFY]` role assigned: "Reader and Data Access", or roles of the service's managed identity).

```bash
# 5. Registering the server with its managed identity
LYON_PID=$(az vm show -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" --query identity.principalId -o tsv)
SSS_ID=$(az storagesync show -g "$RG_DATA" -n "$SSS" --query id -o tsv)
az role assignment create --assignee-object-id "$LYON_PID" \
  --assignee-principal-type ServicePrincipal --role Contributor --scope "$SSS_ID" \
  --query roleDefinitionName -o tsv
SUB=$(az account show --query id -o tsv)
sleep 60
lyon "Connect-AzAccount -Identity -Subscription '$SUB' | Out-Null; Register-AzStorageSyncServer -ResourceGroupName '$RG_DATA' -StorageSyncServiceName '$SSS' | Select-Object FriendlyName, ServerId, AgentVersion | Format-List"
az rest --method get \
  --url "https://management.azure.com${SSS_ID}/registeredServers?api-version=2022-06-01" \
  --query "value[].{Server:properties.friendlyName, Agent:properties.agentVersion}" -o table
```
Expected output:
```
Contributor

FriendlyName : vm-st07-lyon-fs
ServerId     : 6b0c9d2e-4f1a-4e7b-9a3c-2d5e8f1b7c40
AgentVersion : 20.0.0.0

Server           Agent
---------------  --------
vm-st07-lyon-fs  20.0.0.0
```

**6. Portal**: `sg-partage-lyon` › + Add server endpoint:
- Registered server: `vm-st07-lyon-fs`;
- Path: `F:\Partages\Commun`;
- Cloud tiering: enabled, volume free space `20` %, date policy disabled;
- Initial download mode and initial upload mode: default values;
- Create. State "Provisioning", then initial sync (server files uploaded to the share).

```bash
# 7. Share contents after the initial sync (3 to 5 min)
az storage file list --share-name partage-lyon --account-name "$SA_FILES" \
  --query "[].name" -o tsv
az storage file list --share-name partage-lyon --account-name "$SA_FILES" --path Exploitation \
  --query "length(@)" -o tsv

# 8. Server → Azure
lyon "Set-Content F:\Partages\Commun\RH\note-migration.txt 'Migration Azure J3'; 'Fichier cree'"
sleep 90
az storage file exists --share-name partage-lyon --account-name "$SA_FILES" \
  -p RH/note-migration.txt --query exists -o tsv
```
Expected output (key-read warning possible):
```
Exploitation
Qualite
RH
12
Fichier cree
true
```

```bash
# 9. Azure → server: forced detection
echo "Consigne qualité : contrôle des signatures" > "$WORK/consigne-qualite.txt"
az storage file upload --share-name partage-lyon --account-name "$SA_FILES" \
  --source "$WORK/consigne-qualite.txt" --path Qualite/consigne-qualite.txt -o none
lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"
lyon "Connect-AzAccount -Identity -Subscription '$SUB' | Out-Null; \$ce = Get-AzStorageSyncCloudEndpoint -ResourceGroupName '$RG_DATA' -StorageSyncServiceName '$SSS' -SyncGroupName sg-partage-lyon; Invoke-AzStorageSyncChangeDetection -InputObject \$ce -DirectoryPath 'Qualite' -Recursive; 'Detection lancee'"
sleep 120
lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"
```
Expected output:
```
False
Detection lancee
True
```
Parameters of `Invoke-AzStorageSyncChangeDetection` `[TO VERIFY]` on the installed module version (`Get-Help Invoke-AzStorageSyncChangeDetection`).

Expected answers (step 10):
- a. The agent itself opens outbound HTTPS (443) connections to the Storage Sync Service and the storage account, through the site's NAT gateway; Azure never contacts the server. No SMB (445) traffic crosses the Internet: the share is never mounted remotely.
- b. Cloud tiering is not supported on the system volume; a dedicated data volume also makes it possible to size the cache (20 % free) without risk to the system.
- c. At the next run of the share's change detection job, up to 24 h later: changes made directly in Azure Files (Portal, SMB, REST, AzCopy) do not generate notifications to the Storage Sync Service, unlike the server's USN journal.

### Why
- Files account separate from the data account: opposite needs (shared key and public access required by File Sync in its default configuration, versus a keyless, private Blob account).
- `--enable-large-file-share`: shares up to 100 TiB; irreversible activation, at no extra cost.
- `share-rm` (control plane) rather than `share` (data plane): quota and tier managed by ARM, no key needed.
- Transaction optimized tier: the initial sync generates many operations; switching to Cool can be considered once the share has stabilized.
- Sync group created through the Portal: the Portal creates the cloud endpoint and grants the Storage Sync Service rights on the account in a single operation.
- Registration by managed identity: no password or token handled on the server; the Contributor role is limited to the Storage Sync Service only (not the resource group).
- Server endpoint on `F:` with 20 % free space: the 32 GB volume keeps at least 6.4 GB free; with 120 MB of data, no file is tiered as long as the volume does not fill up (bonus 1 to force it).
- Forced detection limited to the `Qualite` folder: cost and duration proportional to the number of items scanned.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `--status`: `Failed`, output `Unable to connect to the remote server` | No outbound Internet access from the Lyon site | Trainer: `lyon-nat.sh create`; then rerun `lyon-fs-prep.sh <NN>` |
| `--status`: `Running` after 20 min | Slow download or installation of modules | Wait; beyond 30 min, notify the trainer |
| `--status`: `Aucun disque RAW` | Disk not attached (policy, quota) | `az vm show ... --query storageProfile.dataDisks`; rerun the script |
| `az storagesync`: extension to install | First use | Answer `Y`; or `az extension add -n storagesync` |
| `MissingSubscriptionRegistration` for `Microsoft.StorageSync` | Provider not registered (subscription right) | Trainer: `az provider register -n Microsoft.StorageSync` |
| Portal: cloud endpoint creation refused (rights) | Role assignment impossible for the Portal | Check the Owner role on `rg-stNN-data`; otherwise, the trainer |
| `Connect-AzAccount -Identity`: `ManagedIdentityCredential authentication unavailable` | Managed identity missing | `az vm identity assign -g rg-stNN-lyon -n vm-stNN-lyon-fs` |
| Registration: `AuthorizationFailed` | Identity role not yet propagated | Wait 2 to 5 min, rerun |
| Registration: `Register-AzStorageSyncServer` not recognized | Az modules not installed (incomplete preparation) | `lyon-fs-prep.sh <NN> --status`; rerun the script |
| Registration: server already registered | Server attached to another service (previous attempt) | Portal: unregister the server, or `Reset-StorageSyncServer` on the server `[TO VERIFY]` |
| Server endpoint: path refused | System volume (`C:`) or nonexistent path | `F:\Partages\Commun` exactly |
| Share empty after 10 min | Server stopped or endpoint in error | Server endpoint health state in the Portal; `az vm start` |

### Acceptable variants
- Sync group and endpoints with the CLI: `az storagesync sync-group create`, `az storagesync sync-group cloud-endpoint create --storage-account <ACCOUNT> --azure-file-share-name partage-lyon`, `az storagesync sync-group server-endpoint create --registered-server-id <ID> --server-local-path F:\\Partages\\Commun --cloud-tiering on --volume-free-space-percent 20` `[TO VERIFY]` option names; the service's rights on the account must then be granted explicitly.
- Registration with the user's token, if registration by managed identity fails on the installed module version (the token remains valid for about 1 h; it appears in the VM's run command history):
  ```bash
  TOKEN=$(az account get-access-token --query accessToken -o tsv)
  lyon "\$p = (Get-Command Connect-AzAccount).Parameters['AccessToken'].ParameterType; \$t = if (\$p -eq [securestring]) { ConvertTo-SecureString '$TOKEN' -AsPlainText -Force } else { '$TOKEN' }; Connect-AzAccount -AccessToken \$t -AccountId '$(az account show --query user.name -o tsv)' -Subscription '$SUB' | Out-Null; Register-AzStorageSyncServer -ResourceGroupName '$RG_DATA' -StorageSyncServiceName '$SSS' | Select-Object FriendlyName, ServerId"
  ```
- Bicep: `Microsoft.StorageSync/storageSyncServices` and its child resources (`syncGroups`, `cloudEndpoints`, `serverEndpoints`), the server endpoint requiring the registered server's ID; this is the approach of `scripts/catch-up/module-06/main.bicep`, deployed in two passes.
- A more restricted role than Contributor for the server's identity: "Azure File Sync Administrator" `[TO VERIFY]` availability and scope of the built-in role.

## Lab 06.6 ⭐ — Export and synchronize with AzCopy

### Solution
```bash
# 1. Version
azcopy --version

# 2. SAS for the share and the archive account
END=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')
KEY_F=$(az storage account keys list -g "$RG_DATA" -n "$SA_FILES" --query "[0].value" -o tsv)
KEY_A=$(az storage account keys list -g "$RG_DATA" -n "$SA_ARCH" --query "[0].value" -o tsv)
SAS_F=$(az storage share generate-sas -n partage-lyon --account-name "$SA_FILES" \
  --account-key "$KEY_F" --permissions rl --expiry "$END" --https-only -o tsv)
SAS_B=$(az storage account generate-sas --account-name "$SA_ARCH" --account-key "$KEY_A" \
  --services b --resource-types sco --permissions racwl --expiry "$END" --https-only -o tsv)

# 3. and 4. Copy of the share, account to account, then check
azcopy copy "https://${SA_FILES}.file.core.windows.net/partage-lyon?${SAS_F}" \
  "https://${SA_ARCH}.blob.core.windows.net/?${SAS_B}" --recursive
azcopy list "https://${SA_ARCH}.blob.core.windows.net/partage-lyon?${SAS_B}" | wc -l

# 5. Differential synchronization
azcopy make "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}"
azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
  | grep -E "Number of Copy Transfers Completed|Final Job Status"
echo "Preuve de livraison 07 - RÉSERVE CLIENT" > "$WORK/pod/pod-007.txt"
azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
  | grep -E "Number of Copy Transfers Completed|Final Job Status"
```
Expected output (end of each command, version and counters vary):
```
azcopy version 10.30.1
Number of File Transfers: 21
Number of File Transfers Completed: 21
Final Job Status: Completed
21
Successfully created the resource.
Number of Copy Transfers Completed: 20
Final Job Status: Completed
Number of Copy Transfers Completed: 1
Final Job Status: Completed
```

```bash
# 6. Check of the tier change made in Storage browser
az storage blob show --account-name "$SA_ARCH" -c partage-lyon -n Qualite/audit-2024.bin \
  --auth-mode key --query properties.blobTier -o tsv
```
Expected output:
```
Cold
```

Expected observation (step 6, data account): Storage browser displays an access denied message indicating that the account's network settings block access from the workstation. The Portal is a client like any other: from the Internet, it goes through the public endpoint, disabled in challenge 06.4. The account's configuration (control plane, ARM) remains accessible; its data (data plane) no longer is.

Expected calculation (step 7):
- Saturated link: `40 × 10¹² × 8 / 10⁸ = 3.2 × 10⁶ s ≈ 889 h ≈ 37 days`.
- At 70 % efficiency: `37 / 0.7 ≈ 53 days`.
- Conclusion: impossible in 3 weeks over the network, and the link would be saturated for all the site's activity. Data Box: order, local copy over the datacenter network, return and upload in a few days to two weeks `[TO VERIFY]` lead times and usable capacity (a single device if its usable capacity exceeds 40 TB). File Sync or AzCopy `sync` afterwards for the differential.

### Why
- SAS rather than Entra ID for AzCopy in Cloud Shell: account-to-account copy with a source Azure Files share, whose Entra ID data plane access requires specific configuration `[TO VERIFY]` AzCopy support for Azure Files with Entra ID.
- Destination at the account root: AzCopy creates a container named after the share, `partage-lyon`; a copy to an existing container would create a virtual folder `partage-lyon/` in it.
- Server-side copy: the bytes travel between accounts within Azure, not through Cloud Shell; a 100 MiB file is copied in a few seconds.
- `azcopy sync`: compares modification dates and sizes, transfers only the differences; `make` creates the container, `sync` does not.
- Archive account with shared key enabled: transit and compliance account, accessed through short-lived SAS; the sensitive data account, on the other hand, no longer accepts keys.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `azcopy: command not found` | Outside Cloud Shell | Install AzCopy v10 (single binary) or use Cloud Shell |
| `403 This request is not authorized to perform this operation using this permission` | Permission missing from the SAS (`c` to create the container, `l` to list) | Regenerate `SAS_B` with `racwl` and `--resource-types sco` |
| `AuthenticationFailed`, `Signature not valid in the specified time frame` | SAS expired (more than 2 h) | Regenerate `END` and the SAS |
| Copy into a `partage-lyon/partage-lyon/` folder | Destination = existing container instead of the account root | Delete the container, rerun to the root |
| `azcopy sync`: container not found | `azcopy make` forgotten | Create the container, rerun |
| Second sync: `0` transfers | File modified outside `$WORK/pod`, or same content | Check the path, modify the content |
| Storage browser: no message for the data account | Challenge 06.4 not deployed (public access still active) | Normal; message expected after the challenge or the catch-up |

### Acceptable variants
- `azcopy login` (Entra ID) for the archive account, with the "Storage Blob Data Contributor" role: recommended in production; requires the role on `starveost<NN>arch<SES>`.
- `AZCOPY_AUTO_LOGIN_TYPE=AZCLI` variable to reuse the Cloud Shell Azure CLI session `[TO VERIFY]` minimum AzCopy version.
- Azure Storage Explorer on the workstation: same copy by drag and drop between accounts (AzCopy in the background).

## Bonus

### 1. Forced tiering
```bash
lyon "Import-Module 'C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll'; \$f = 'F:\Partages\Commun\Qualite\audit-2024.bin'; 'AVANT : ' + (Get-Item \$f).Attributes; Invoke-StorageSyncCloudTiering -Path \$f; Start-Sleep 20; 'APRES : ' + (Get-Item \$f).Attributes; 'Volume F: libre (Mo) : ' + [math]::Round((Get-Volume F).SizeRemaining / 1MB)"
lyon "Import-Module 'C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll'; Invoke-StorageSyncFileRecall -Path 'F:\Partages\Commun\Qualite\audit-2024.bin'; 'RAPPEL : ' + (Get-Item 'F:\Partages\Commun\Qualite\audit-2024.bin').Attributes"
```
Expected output (free space values vary, about 100 MB more after tiering):
```
AVANT : Archive
APRES : Archive, SparseFile, ReparsePoint, Offline
Volume F: libre (Mo) : 32540
RAPPEL : Archive
```
The tiered file keeps its logical size (100 MB in Explorer) but takes up almost no space on the volume: its content is in Azure Files, and a reparse point replaces it locally. The `Offline` attribute signals to applications (and antivirus software) that a read will trigger a download. After recall, the file becomes local again; it may be tiered again according to the policy.

### 2. Restricted files account
```bash
NAT_IP=<LYON_EGRESS_IP>     # provided by the trainer (lyon-nat.sh status)
az storage account update -g "$RG_DATA" -n "$SA_FILES" --default-action Deny --bypass AzureServices -o none
az storage account network-rule add -g "$RG_DATA" --account-name "$SA_FILES" --ip-address "$NAT_IP" -o none
lyon "Set-Content F:\Partages\Commun\RH\test-pare-feu.txt 'Test'; 'OK'"
sleep 120
az storage file list --share-name partage-lyon --account-name "$SA_FILES" --path RH -o none
# Restore
az storage account update -g "$RG_DATA" -n "$SA_FILES" --default-action Allow -o none
```
Expected result: `OK`; the file appears in the share (checked through the Portal, from a workstation whose IP would be allowed, or after restoring); the `az storage file list` command fails from Cloud Shell (`AuthorizationFailure`), since its IP is not allowed. File Sync remains functional: the agent goes out through the NAT's allowed IP and the Storage Sync Service benefits from the trusted Microsoft services exception `[TO VERIFY]` documented network requirements of Azure File Sync.

### 3. Complete Bicep
In `scripts/catch-up/module-06/main.bicep`: `sss` (`storageSyncServices`), `syncGroup`, `cloudEndpoint` (depends on the `syncRole` assignment to the Microsoft.StorageSync principal on the files account), `lyonSyncRole` (the server's managed identity, Contributor on the service) and `serverEndpoint`, conditional on `registeredServerId`. Object replication rule with the CLI: its `policyId` and `ruleId` are generated by the destination account when it is created, then must be copied to the source. A Bicep resource name must be computable at the start of the deployment (error `BCP120` otherwise); this would require a module receiving the identifier as a parameter, more complex than an idempotent CLI call.

## QCM — Answers
1. **C** — Standard v2 supports Blob, Files, Queue and Table; Premium accounts are specialized.
2. **C** — RA-GRS adds read access to the secondary in the paired region, without failover.
3. **B** — An archived blob is offline: it must be rehydrated (tier change or copy).
4. **B** — Versioning on both accounts and change feed on the source are required.
5. **D** — The user delegation SAS is signed by a key obtained through Entra ID, not by the account key.
6. **B** — `Owner` includes no data actions: a Storage Blob Data… role is required.
7. **A** — Without a link from the private zone to the VNet (or without a zone group), the name resolves to the public IP.
8. **C** — Changes made directly in Azure Files are detected by a job every 24 h.
9. **B** — Cloud tiering is not supported on the system volume.
10. **C** — 40 TB at 100 Mbit/s takes more than a month: offline transfer with Data Box.
