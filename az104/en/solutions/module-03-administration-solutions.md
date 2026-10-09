# Module 03 — Solutions

Examples given for trainee 07 (`NN=07`). Replace `07` with the trainee number.

## Lab 03.1 ⭐ — Getting started with Cloud Shell

### Solution
```bash
az account show --query "{Account:user.name, Subscription:name}" -o table
az version --query '"azure-cli"' -o tsv
az bicep version
az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
pwsh
```
```powershell
Get-AzContext | Select-Object Account, Subscription
exit
```

### Why
- Ephemeral session: no storage account to create in the shared subscription, no extra permission required.
- Check the active account before any action: a trainee signed in with a personal account or another tenant gets confusing authorization errors later.
- `az version --query '"azure-cli"'`: inner double quotes required, the key name contains a hyphen.
- `pwsh` from Bash: same container, same authentication; shows that CLI and PowerShell talk to the same ARM.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Cloud Shell asks to create a storage account | "Ephemeral" option not selected | Close, reopen Cloud Shell > Settings > Reset user settings `[TO VERIFY]` label, choose the option without storage |
| Error opening Cloud Shell mentioning `Microsoft.CloudShell` | Provider not registered on the subscription `[TO VERIFY]` | Trainer: `az provider register --namespace Microsoft.CloudShell` |
| `az account show` displays another tenant | Personal account already signed in in the browser | Private browsing window, sign in again with `st07@<DOMAIN>` |
| Session closed during the lab | 20 min of inactivity | Reopen Cloud Shell, redefine variables (step 1 of lab 03.2) |

## Lab 03.2 ⭐ — Azure CLI: context, tags and Log Analytics workspace

### Solution
```bash
NN=07
ST="st${NN}"
RG="rg-${ST}-shared"
LOC="francecentral"

az configure --defaults group="$RG" location="$LOC"
az configure --list-defaults -o table

az group list --query "[?starts_with(name, 'rg-${ST}-')].{Name:name, Region:location}" -o table

RG_ID=$(az group show --name "$RG" --query id -o tsv)
az tag update --resource-id "$RG_ID" --operation Merge \
  --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
  --query "properties.tags"

az monitor log-analytics workspace create \
  --workspace-name "log-${ST}-shared" \
  --retention-time 30 \
  --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
  --query "{Name:name, State:provisioningState, Retention:retentionInDays}" -o table

az resource list \
  --query "[].{Name:name, Type:type, Owner:tags.Proprietaire}" -o table

WS_ID=$(az monitor log-analytics workspace show -n "log-${ST}-shared" \
  --query customerId -o tsv)
echo "$WS_ID"
```

### Why
- `az configure --defaults`: `--resource-group` and `--location` become optional; shorter commands, but risk of acting on the wrong group if defaults are forgotten.
- `[?starts_with(name, 'rg-${ST}-')]`: the Reader role on the subscription makes ALL trainees' groups visible; the filter isolates the trainee's own. `${ST}` is expanded by Bash because the string is in double quotes.
- `az tag update --operation Merge`: adds or updates the supplied tags without removing others. `Replace` would overwrite the whole set and could remove a tag required by a policy (`RequestDisallowedByPolicy`).
- 30-day retention: value included without extra retention cost `[TO VERIFY]` current pricing terms.
- `customerId` (workspace ID, GUID) ≠ `id` (ARM resource ID): the first is used by agents and KQL queries, the second by RBAC assignments and diagnostic settings.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `AuthorizationFailed` | Another trainee's group or typo in `NN` | `echo $RG`, fix the variable |
| `RequestDisallowedByPolicy` | Missing tag or region not allowed (M2 policies) | Check `--tags` and `LOC`, read the error details (assignment name) |
| Group list is empty | `ST` empty (variables lost after session close) | Redefine step 1 variables |
| `MissingSubscriptionRegistration` for `Microsoft.OperationalInsights` | Provider not registered | Trainer: `az provider register --namespace Microsoft.OperationalInsights` |
| `WS_ID` contains quotes | `-o json` instead of `-o tsv` | Rerun with `-o tsv` |

## Exercise 03.3 ⭐⭐ — Az PowerShell: idempotent storage account and inventory

### Solution
Script `New-SocleStockage.ps1`:
```powershell
# New-SocleStockage.ps1 — diagnostics storage account of the Arvéo foundation
# Usage: ./New-SocleStockage.ps1 -Numero 07 [-Suffixe ab]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d{2}$')]
    [string] $Numero,

    [ValidatePattern('^[a-z0-9]{0,4}$')]
    [string] $Suffixe = ''
)

$ErrorActionPreference = 'Stop'

$st       = "st$Numero"
$rg       = "rg-$st-shared"
$location = 'francecentral'
$name     = "starveo$($st)diag$Suffixe"
$tags     = @{ Projet = 'Arveo'; Environnement = 'Formation'; Proprietaire = $st }

$existing = Get-AzStorageAccount -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue
if ($existing) {
    Write-Output "Account $name already present in $rg: no action."
    return
}

$availability = Get-AzStorageAccountNameAvailability -Name $name
if (-not $availability.NameAvailable) {
    throw "Name $name unavailable ($($availability.Reason)). Rerun with -Suffixe <2 letters>."
}

New-AzStorageAccount -ResourceGroupName $rg -Name $name -Location $location `
    -SkuName Standard_LRS -Kind StorageV2 -AccessTier Hot `
    -MinimumTlsVersion TLS1_2 -EnableHttpsTrafficOnly $true `
    -AllowBlobPublicAccess $false -Tag $tags | Out-Null

Write-Output "Account $name created in $rg."
```

Run and check:
```powershell
./New-SocleStockage.ps1 -Numero 07
./New-SocleStockage.ps1 -Numero 07
Get-AzStorageAccount -ResourceGroupName rg-st07-shared -Name starveost07diag |
  Select-Object MinimumTlsVersion, AllowBlobPublicAccess, EnableHttpsTrafficOnly
```
Expected output:
```
Account starveost07diag created in rg-st07-shared.
Account starveost07diag already present in rg-st07-shared: no action.

MinimumTlsVersion AllowBlobPublicAccess EnableHttpsTrafficOnly
----------------- --------------------- ----------------------
TLS1_2                            False                   True
```

Inventory:
```powershell
$st = 'st07'
Get-AzResource |
  Where-Object ResourceGroupName -like "rg-$st-*" |
  Select-Object Name, ResourceType, ResourceGroupName, Location,
    @{ Name = 'Owner'; Expression = { $_.Tags['Proprietaire'] } } |
  Export-Csv -Path "./inventory-$st.csv" -NoTypeInformation -Encoding utf8

Import-Csv "./inventory-$st.csv" | Format-Table
```
Expected output:
```
Name            ResourceType                             ResourceGroupName Location      Owner
----            ------------                             ----------------- --------      -----
log-st07-shared Microsoft.OperationalInsights/workspaces rg-st07-shared    francecentral st07
starveost07diag Microsoft.Storage/storageAccounts        rg-st07-shared    francecentral st07
```

### Why
- `$ErrorActionPreference = 'Stop'`: any unhandled error stops the script; without it, PowerShell carries on after a non-terminating error and reports a false success.
- `-ErrorAction SilentlyContinue` on `Get-AzStorageAccount`: the account not existing is an expected case, not an error; this local parameter overrides the global preference.
- `return` in the "already present" branch: clean exit, no error code, script can be rerun (idempotence).
- `Get-AzStorageAccountNameAvailability`: the name is global to Azure; the check gives a clear message instead of a `StorageAccountAlreadyTaken` error at the end of creation.
- `ValidatePattern`: rejects a malformed number BEFORE any call to Azure (same principle as Bicep decorators).
- `-AllowBlobPublicAccess $false`, `-MinimumTlsVersion TLS1_2`: security settings expected by IT, revisited in module 6.
- `Get-AzResource` then filter: the Reader role on the subscription gives a full view, the `-like` filter (case-insensitive) restricts it to the trainee's groups.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `Name starveost07diag unavailable (AlreadyExists)` | Name already taken in Azure (other session, other customer) | Rerun with `-Suffixe` (2 letters, e.g. initials) and note the name for challenge 03.5 |
| `A parameter cannot be found that matches parameter name 'MinimumTlsVersion'` | Old Az.Storage module (local workstation) | Use Cloud Shell or `Update-Module Az.Storage` |
| Second run recreates or fails | `-ErrorAction SilentlyContinue` forgotten: missing account stops the script | Add the parameter on `Get-AzStorageAccount` |
| Empty `Owner` column | Resource without the tag, or wrong case in the key | Check the exact key with `(Get-AzResource -Name <NAME>).Tags` |
| Garbled accents in the CSV opened in Excel | Encoding without BOM | `-Encoding utf8BOM` (PowerShell 7) |
| Script refused: `cannot be loaded because running scripts is disabled` | Local Windows workstation, execution policy | Cloud Shell is not affected; locally: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |

### Acceptable variants
- `try { Get-AzStorageAccount ... } catch { ... }` instead of `-ErrorAction SilentlyContinue`: more explicit, longer.
- Inventory with Azure CLI: `az resource list --query "[?starts_with(resourceGroup, 'rg-st07-')]"` then `-o tsv` redirected to a file; correct, but headers must be added by hand.
- Name with a random suffix (`Get-Random`): uniqueness guaranteed but unpredictable name, to avoid for a foundation referenced by other modules.

## Exercise 03.4 ⭐⭐ — Read an ARM JSON template, deploy it, convert it to Bicep

### Solution
Reading answers:
- Two parameters: `numero` (mandatory, no `defaultValue`) and `location` (optional).
- Type `Microsoft.ManagedIdentity/userAssignedIdentities`, name `id-st07-deploy` for trainee 07 (`prefix` = `st07`).
- Without `location`: region of the target resource group (`resourceGroup().location`), i.e. `francecentral` for `rg-st07-shared`.

Deployment:
```bash
az deployment group create \
  --resource-group rg-st07-shared \
  --name identite-arm \
  --template-file identite.json \
  --parameters numero=07 \
  --query "properties.outputs.principalId.value" -o tsv
```
Expected output: a GUID (ID of the identity's service principal in Entra ID).

Conversion and comparison:
```bash
az bicep decompile --file identite.json
wc -l identite.json identite.bicep
```
Expected output (Bicep CLI 0.48, excerpt):
```
WARNING: Decompilation is a best-effort process, as there is no guaranteed mapping from ARM JSON to Bicep Template or Bicep Parameters.
identite.bicep(21,29) : Warning use-resource-symbol-reference: Use a resource reference instead of invoking function "reference".
  42 identite.json
  21 identite.bicep
  63 total
```
Warning wording may vary with the Bicep version.

Resulting `identite.bicep`:
```bicep
@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string
param location string = resourceGroup().location

var prefix = 'st${numero}'
var identityName = 'id-${prefix}-deploy'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

output principalId string = reference(identity.id, '2023-01-31').principalId
```

Cleanup recommended by the linter (last line):
```bicep
output principalId string = identity.properties.principalId
```

Preview:
```bash
az deployment group what-if \
  --resource-group rg-st07-shared \
  --template-file identite.bicep \
  --parameters numero=07
```
Expected output (end):
```
  = Microsoft.ManagedIdentity/userAssignedIdentities/id-st07-deploy [2023-01-31]

Resource changes: 1 no change.
```

### Why
- `--query "properties.outputs.principalId.value"`: each deployment output is a `{ type, value }` object.
- The `principalId` will be used to assign RBAC roles to the identity (modules 7 and 8); retrieving it as an output avoids a manual lookup.
- `reference()`: decompilation keeps it as is; the linter recommends the symbolic access `identity.properties.principalId`, same ARM call, explicit dependency for Bicep. Illustrates "best effort": decompiled code must be reviewed and cleaned up.
- `what-if` with no change = proof that the Bicep file describes the existing resource EXACTLY; the conversion is validated without risk.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `InvalidTemplate ... Unable to parse` | Badly pasted JSON (missing quote or comma) | `az deployment group validate` or `python3 -m json.tool identite.json` to find the line |
| `The value of parameter numero is not valid` / length | `numero=7` instead of `numero=07` | Always two digits |
| `--query` returns nothing | Wrong path (`outputs.principalId` without `properties`) | `--query properties.outputs` to explore |
| `identite.bicep` already exists, decompile refuses | Second run | `--force` option `[TO VERIFY]` or delete the file |
| `what-if` shows `~` on `tags` | Tag changed by hand in the meantime | Expected: `what-if` reveals the drift; redeploy or fix the file |

### Acceptable variants
- PowerShell deployment: `New-AzResourceGroupDeployment -ResourceGroupName rg-st07-shared -Name identite-arm -TemplateFile identite.json -numero '07'` then `(Get-AzResourceGroupDeployment -ResourceGroupName rg-st07-shared -Name identite-arm).Outputs.principalId.Value`.
- Portal deployment: **Deploy a custom template** > **Build your own template in the editor** > paste the JSON. Correct, but not reproducible by script.
- Symbolic names renamed after decompilation: recommended for readability, no effect on the deployment.

## Challenge 03.5 ⭐⭐⭐ — Bring the foundation under IaC and fix a drift

### Solution
File `socle.bicep` (equivalent to the catch-up script `scripts/catch-up/module-03/main.bicep`, whose descriptions are in French):
```bicep
// socle.bicep — Arvéo shared foundation (rg-stNN-shared)
targetScope = 'resourceGroup'

@description('Two-digit trainee number')
@minLength(2)
@maxLength(2)
param numero string

@description('Deployment region')
@allowed([ 'francecentral', 'westeurope' ])
param location string = 'francecentral'

@description('Diagnostics storage account name (3 to 24 lowercase letters or digits)')
@minLength(3)
@maxLength(24)
param storageName string = 'starveost${numero}diag'

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${prefix}-shared'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource diagStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-deploy'
  location: location
  tags: tags
}

output workspaceId string = workspace.id
output storageAccountId string = diagStorage.id
output identityPrincipalId string = deployIdentity.properties.principalId
```

Check, deploy, drift, fix:
```bash
az bicep build --file socle.bicep --stdout > /dev/null && echo "Syntax OK"

az deployment group what-if -g rg-st07-shared \
  --template-file socle.bicep --parameters numero=07

az deployment group create -g rg-st07-shared --name socle \
  --template-file socle.bicep --parameters numero=07 \
  --query "properties.provisioningState" -o tsv

# Simulated drift
az storage account update -n starveost07diag -g rg-st07-shared --access-tier Cool
az tag update --resource-id "$(az storage account show -n starveost07diag \
  -g rg-st07-shared --query id -o tsv)" --operation Merge --tags Temporaire=oui

# Detection, then fix
az deployment group what-if -g rg-st07-shared \
  --template-file socle.bicep --parameters numero=07
az deployment group create -g rg-st07-shared --name socle \
  --template-file socle.bicep --parameters numero=07 \
  --query "properties.provisioningState" -o tsv

az storage account show -n starveost07diag -g rg-st07-shared \
  --query "{Tier:accessTier, Tags:tags}"
```
Expected post-drift `what-if` output (excerpt):
```
  ~ Microsoft.Storage/storageAccounts/starveost07diag [2023-05-01]
    - tags.Temporaire: "oui"
    ~ properties.accessTier: "Cool" => "Hot"

  = Microsoft.ManagedIdentity/userAssignedIdentities/id-st07-deploy [2023-01-31]
  = Microsoft.OperationalInsights/workspaces/log-st07-shared [2023-09-01]

Resource changes: 1 to modify, 2 no change.
```
Expected output of the final check:
```
{
  "Tags": {
    "Environnement": "Formation",
    "Projet": "Arveo",
    "Proprietaire": "st07"
  },
  "Tier": "Hot"
}
```
If the account was created with a suffix in exercise 03.3: add `storageName=starveost07diag<SUFFIX>` to `--parameters`.

### Why
- One file, three resources created by three tools: ARM only knows the state of resources, not the original tool. Describing the existing resources identically = bringing them under IaC without recreation.
- `tags` declared once as a variable: guaranteed consistency, a single line to change.
- `storageName` as a parameter with a default value: general case without parameter, suffix case covered.
- Declared `tags` property = complete set: redeploying removes the `Temporaire` tag added by hand. The file is the source of truth.
- Incremental mode: any other resources of the group (bonus, template spec) are kept.
- Outputs: `workspaceId` (ARM ID) will feed diagnostic settings in module 10; `identityPrincipalId` the RBAC assignments.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `what-if` announces `+ Create` for the storage account | Name differs from the existing one (suffix forgotten) | Pass `storageName=<REAL_NAME>` |
| `what-if` shows `~` on undeclared workspace properties (`features`, `workspaceCapping`) | Default values set by the CLI at creation, compared with the file | Acceptable noise: check that no business value changes; `--result-format ResourceIdOnly` for a summary `[TO VERIFY]` |
| Linter warning `use-recent-api-versions` | More recent API versions available | No effect on deployment; update after testing |
| `BCP035` / `BCP037` | Misspelled or misplaced property (`accessTier` outside `properties`) | Read the error position, use VS Code completion |
| `RequestDisallowedByPolicy` on the storage account | M2 policy (tag, region or security setting) | Read `policyAssignmentName` in the error, align the file |
| `InvalidTemplateDeployment` on the region | `location` outside the `@allowed` list | Expected: validation does its job |

### Acceptable variants
- Existing resources referenced with `existing` instead of being redeclared: valid to READ them, but no drift fix possible (the file no longer describes the desired state).
- Tags passed as an object parameter (`param tags object`): more flexible, but risk of diverging values between trainees.
- One Bicep module per resource (`modules/workspace.bicep`): recommended structure for a larger foundation, oversized for three resources.
- Fixing the drift with `az storage account update --access-tier Hot`: same result here, but untracked manual fix, contrary to the objective.

## Bonus

### 1. `.bicepparam` parameter file
```bicep
// socle.bicepparam
using './socle.bicep'

param numero = '07'
```
```bash
az deployment group create -g rg-st07-shared --name socle \
  --parameters socle.bicepparam \
  --query "properties.provisioningState" -o tsv
```
Expected output:
```
Succeeded
```
`using` links the parameter file to the template: `--template-file` becomes unnecessary (Azure CLI 2.53 or later `[TO VERIFY]`).

### 2. Template spec
```bash
az ts create --name ts-st07-socle --version 1.0 \
  --resource-group rg-st07-shared --location francecentral \
  --template-file socle.bicep --query id -o tsv

TS_ID=$(az ts show --name ts-st07-socle --version 1.0 \
  --resource-group rg-st07-shared --query id -o tsv)

az deployment group create -g rg-st07-shared --name socle-ts \
  --template-spec "$TS_ID" --parameters numero=07 \
  --query "properties.provisioningState" -o tsv
```
Expected output: a resource ID ending in `templateSpecs/ts-st07-socle/versions/1.0`, then `Succeeded`.
Benefit: versioned template stored in Azure, shareable through RBAC (Reader role on the template spec) without a Git repository.

### 3. PowerShell deployment with `-WhatIf`
```powershell
New-AzResourceGroupDeployment -ResourceGroupName rg-st07-shared `
  -TemplateFile ./socle.bicep -numero '07' -WhatIf
```
Same result as `az deployment group what-if`, same engine on the ARM side. `-numero` is a dynamic parameter generated from the template parameters. Bicep CLI must be in the `PATH` (true in Cloud Shell).

## QCM — Answers
1. **C** — ARM is the single control-plane entry point; Graph manages Entra ID objects, Policy is a control enforced by ARM.
2. **A** — Owner acts on the control plane; reading blobs through Entra ID requires a data role (e.g. Storage Blob Data Reader).
3. **D** — `--query id` extracts the property, `-o tsv` returns it raw, without JSON quotes.
4. **C** — The CLI outputs text (JSON by default); Az PowerShell handles typed .NET objects in the pipeline.
5. **B** — Incremental mode does not touch undeclared resources; only Complete mode deletes them.
6. **C** — `what-if` computes and displays the difference without applying anything.
7. **A** — Bicep is a language transpiled to ARM JSON; no state file, no agent.
8. **D** — `@secure()` masks the value in deployment history and logs.
9. **B** — `MissingSubscriptionRegistration` = resource provider not registered; registration happens at subscription level.
