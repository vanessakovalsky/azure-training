# Module 03 — Exercises

Common thread: building the **Arvéo shared foundation** in `rg-stNN-shared`, reused in modules 7 (boot diagnostics) and 10 (monitoring).

| Resource | Name (trainee 07) | Creation tool | Lab |
|---|---|---|---|
| Log Analytics workspace | `log-st07-shared` | Azure CLI | 03.2 |
| Diagnostics storage account | `starveost07diag` | Az PowerShell | 03.3 |
| User-assigned managed identity | `id-st07-deploy` | ARM JSON template | 03.4 |
| All three, brought under IaC | `socle.bicep` | Bicep | 03.5 |

Variables used in all labs:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<DOMAIN>` = training tenant domain, provided by the trainer

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`. Tag names and values stay in French: they are shared with the French-speaking groups of the same tenant.

---

## Lab 03.1 ⭐ — Getting started with Cloud Shell (guided)
**Duration** : 5 min · **Objective** : open an authenticated terminal and check the working context (objective 4)
**Context** : Arvéo teams install no tools on their workstations; all administration goes through Cloud Shell.
**Prerequisites** : account `st<NN>@<DOMAIN>` with an MFA method registered (M0); recent browser.

### Steps
1. Sign in to the portal `https://portal.azure.com` with `st<NN>@<DOMAIN>`.
   Expected result: portal home page, training tenant name at the top right.

2. Open Cloud Shell (`>_` icon in the top bar), choose **Bash**.
   On the first-use screen: select **No storage account required** `[TO VERIFY]` exact label, then the training subscription, then **Apply**.
   Expected result: a `st07 [ ~ ]$` prompt (or similar) after a few seconds.

3. Check the active account and subscription.
   ```bash
   az account show --query "{Account:user.name, Subscription:name}" -o table
   ```
   Expected result:
   ```
   Account                              Subscription
   -----------------------------------  ------------------------
   st07@<DOMAIN>                        <SUBSCRIPTION_NAME>
   ```

4. Check tool versions.
   ```bash
   az version --query '"azure-cli"' -o tsv
   az bicep version
   ```
   Expected result: a `2.x` version for Azure CLI, then `Bicep CLI version 0.x.y` `[TO VERIFY]` current versions.

5. Check that a resource provider used in this module is registered.
   ```bash
   az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
   ```
   Expected result:
   ```
   Registered
   ```

6. Switch to PowerShell from the same session, then come back.
   ```bash
   pwsh
   ```
   ```powershell
   Get-AzContext | Select-Object Account, Subscription
   exit
   ```
   Expected result: account `st07@<DOMAIN>` and the training subscription; back to the Bash prompt after `exit`.

7. In the portal, open resource group `rg-st<NN>-shared` > **Activity log**.
   Expected result: module 2 operations (tags, assignments) visible, with caller and status.

### Success criteria
- [ ] `az account show` displays account `st<NN>@<DOMAIN>`.
- [ ] `az provider show` returns `Registered`.
- [ ] `Get-AzContext` displays the same account from PowerShell.

---

## Lab 03.2 ⭐ — Azure CLI: context, tags and Log Analytics workspace (guided)
**Duration** : 10 min · **Objective** : create and query a resource with Azure CLI (objective 4)
**Context** : Arvéo centralizes the future landing zone logs in a single Log Analytics workspace per environment, placed in `rg-stNN-shared`.
**Prerequisites** : Lab 03.1 completed, Cloud Shell in Bash.

### Steps
1. Define session variables. Replace `<NN>` with the trainee number.
   ```bash
   NN=<NN>
   ST="st${NN}"
   RG="rg-${ST}-shared"
   LOC="francecentral"
   echo "$ST $RG $LOC"
   ```
   Expected result (trainee 07):
   ```
   st07 rg-st07-shared francecentral
   ```

2. Configure CLI default values.
   ```bash
   az configure --defaults group="$RG" location="$LOC"
   az configure --list-defaults -o table
   ```
   Expected result: two lines, `group` = `rg-st07-shared` and `location` = `francecentral`.

3. List only the trainee's own resource groups.
   ```bash
   az group list --query "[?starts_with(name, 'rg-${ST}-')].{Name:name, Region:location}" -o table
   ```
   Expected result:
   ```
   Name            Region
   --------------  -------------
   rg-st07-app     francecentral
   rg-st07-data    francecentral
   rg-st07-hub     francecentral
   rg-st07-lyon    francecentral
   rg-st07-shared  francecentral
   rg-st07-spoke   francecentral
   ```
   The region of `rg-st07-lyon` depends on the provisioning script `[TO VERIFY]`.

4. Merge the Arvéo tags on group `rg-stNN-shared` (without overwriting existing tags).
   ```bash
   RG_ID=$(az group show --name "$RG" --query id -o tsv)
   az tag update --resource-id "$RG_ID" --operation Merge \
     --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
     --query "properties.tags"
   ```
   Expected result:
   ```
   {
     "Environnement": "Formation",
     "Projet": "Arveo",
     "Proprietaire": "st07"
   }
   ```
   (other tags set in module 2 may appear: they are kept)

5. Create the Log Analytics workspace.
   ```bash
   az monitor log-analytics workspace create \
     --workspace-name "log-${ST}-shared" \
     --retention-time 30 \
     --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
     --query "{Name:name, State:provisioningState, Retention:retentionInDays}" -o table
   ```
   Expected result (30 to 60 seconds):
   ```
   Name             State      Retention
   ---------------  ---------  -----------
   log-st07-shared  Succeeded  30
   ```

6. List the group's resources with a JMESPath projection.
   ```bash
   az resource list \
     --query "[].{Name:name, Type:type, Owner:tags.Proprietaire}" -o table
   ```
   Expected result:
   ```
   Name             Type                                      Owner
   ---------------  ----------------------------------------  -----
   log-st07-shared  Microsoft.OperationalInsights/workspaces  st07
   ```

7. Store the workspace ID in a variable (used in module 10).
   ```bash
   WS_ID=$(az monitor log-analytics workspace show -n "log-${ST}-shared" \
     --query customerId -o tsv)
   echo "$WS_ID"
   ```
   Expected result: a bare GUID, without quotes (e.g. `3f2b9c1e-8a4d-4c55-9e0b-2d7f1a6c4b90`, specific to each workspace).

### Success criteria
- [ ] `az configure --list-defaults -o table` displays `rg-st<NN>-shared` and `francecentral`.
- [ ] `az group show -n rg-st<NN>-shared --query tags` contains `Projet`, `Environnement`, `Proprietaire`.
- [ ] `az monitor log-analytics workspace show -n log-st<NN>-shared --query provisioningState -o tsv` returns `Succeeded`.
- [ ] `echo "$WS_ID"` displays a GUID without quotes.

---

## Exercise 03.3 ⭐⭐ — Az PowerShell: idempotent storage account and inventory (semi-autonomous)
**Duration** : 10 min · **Objective** : create a resource with a reusable script and produce a report with Az PowerShell (objective 4)

> 🔸 **Adjusted session**: this exercise is covered as a trainer demonstration. Complete it independently once you finish labs 03.1 and 03.2, during M4 labs.
**Context** : Arvéo VMs (M7) will write their boot diagnostics to a dedicated storage account. IT requires a script that can be rerun without error and a CSV inventory of the resources of each environment.

**Assignment** :
1. In Cloud Shell, PowerShell mode, write a script `New-SocleStockage.ps1` that takes the trainee number as a parameter and creates storage account `starveost<NN>diag` in `rg-st<NN>-shared` with:
   - Standard performance, LRS redundancy, StorageV2 kind, Hot access tier;
   - minimum TLS version 1.2, HTTPS traffic only, anonymous public blob access disabled;
   - the three Arvéo tags.
2. The script must:
   - stop at the first error;
   - do nothing (and say so) if the account already exists;
   - check name availability before creation and accept an optional suffix if the name is taken.
3. Run the script twice in a row: the second run must produce no error.
4. Produce `inventory-st<NN>.csv` listing every resource of groups `rg-st<NN>-*` with columns `Name`, `ResourceType`, `ResourceGroupName`, `Location`, `Owner` (value of tag `Proprietaire`).

**Hints** :
- Script editing in Cloud Shell: `code New-SocleStockage.ps1`.
- Useful cmdlets: `Get-AzStorageAccount`, `Get-AzStorageAccountNameAvailability`, `New-AzStorageAccount`, `Get-AzResource`, `Export-Csv`.
- `Get-Help New-AzStorageAccount -Parameter MinimumTlsVersion` for the exact syntax of a parameter.
- Storage account name: 3 to 24 characters, lowercase letters and digits only, unique across Azure.
- Calculated property: `@{ Name = '<COLUMN>'; Expression = { <EXPRESSION> } }`.

**Success criteria** :
- [ ] `Get-AzStorageAccount -ResourceGroupName rg-st<NN>-shared -Name starveost<NN>diag | Select-Object MinimumTlsVersion, AllowBlobPublicAccess, EnableHttpsTrafficOnly` displays `TLS1_2`, `False`, `True`.
- [ ] The second run of the script displays an "already present" message and no error.
- [ ] `Import-Csv ./inventory-st<NN>.csv | Format-Table` displays at least `log-st<NN>-shared` and `starveost<NN>diag`, with `st<NN>` in the `Owner` column.

---

## Exercise 03.4 ⭐⭐ — Read an ARM JSON template, deploy it, convert it to Bicep (semi-autonomous)
**Duration** : 10 min · **Objective** : read and deploy an ARM JSON template, then convert it to Bicep (objective 4)

> 🔸 **Adjusted session**: this exercise is projected as a trainer demonstration. Complete it independently once you finish labs 03.1 and 03.2, during M4 labs.
**Context** : Arvéo's former contractor left an ARM JSON template that creates the managed identity used later by deployment scripts. The decision has been made to migrate all templates to Bicep.

**Provided file** : create `identite.json` in Cloud Shell (`code identite.json`) with this exact content (also available as `scripts/labs/module-03/identite.json`).
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "numero": {
      "type": "string",
      "minLength": 2,
      "maxLength": 2,
      "metadata": {
        "description": "Numéro du stagiaire sur deux chiffres"
      }
    },
    "location": {
      "type": "string",
      "defaultValue": "[resourceGroup().location]"
    }
  },
  "variables": {
    "prefix": "[format('st{0}', parameters('numero'))]",
    "identityName": "[format('id-{0}-deploy', variables('prefix'))]",
    "tags": {
      "Projet": "Arveo",
      "Environnement": "Formation",
      "Proprietaire": "[variables('prefix')]"
    }
  },
  "resources": [
    {
      "type": "Microsoft.ManagedIdentity/userAssignedIdentities",
      "apiVersion": "2023-01-31",
      "name": "[variables('identityName')]",
      "location": "[parameters('location')]",
      "tags": "[variables('tags')]"
    }
  ],
  "outputs": {
    "principalId": {
      "type": "string",
      "value": "[reference(resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', variables('identityName')), '2023-01-31').principalId]"
    }
  }
}
```

**Assignment** :
1. Without deploying anything, answer in writing:
   - how many parameters does the template expect, and which one is mandatory?
   - which resource type is created, and with what name for trainee 07?
   - in which region is the resource created if `location` is not supplied?
2. Deploy the template into `rg-st<NN>-shared` with deployment name `identite-arm`, and display only the `principalId` output.
3. Find this deployment in the portal (resource group > Deployments) and open the **Template** tab.
4. Convert `identite.json` into `identite.bicep`, compare both files (line count, readability).
5. Preview the deployment of the Bicep file: the expected result contains no creation and no modification.

**Hints** :
- `az deployment group create --help`: parameters `--name`, `--template-file`, `--parameters`, `--query`.
- Deployment outputs: `properties.outputs`.
- Conversion: `az bicep decompile`.
- Line count: `wc -l identite.json identite.bicep`.

**Success criteria** :
- [ ] `az identity show -n id-st<NN>-deploy -g rg-st<NN>-shared --query tags` displays the three Arvéo tags.
- [ ] `az deployment group show -n identite-arm -g rg-st<NN>-shared --query properties.provisioningState -o tsv` returns `Succeeded`.
- [ ] The Bicep file `what-if` ends with `Resource changes: 1 no change.`

---

## Challenge 03.5 ⭐⭐⭐ — Bring the foundation under IaC and fix a drift (autonomous)
**Duration** : 10 min · **Objective** : deploy a parameterized Bicep file reproducibly after a `what-if` check (objective 4)

> 🔸 **Adjusted session**: replaced by `./scripts/m3/deploy.sh <NN>` (deploys all three foundation resources in 1–2 min). Complete it independently if you finish early.
**Context** : the `rg-stNN-shared` foundation was built with three different tools. Arvéo IT wants a single file, the source of truth, able to recreate the foundation identically and to fix any manual change.

**Assignment** :
1. Write `socle.bicep` describing the three existing resources: `log-st<NN>-shared`, `starveost<NN>diag`, `id-st<NN>-deploy`, with the same properties and the three tags.
2. Constraints:
   - a single mandatory parameter: the trainee number, validated on two characters;
   - storage account name overridable by parameter (suffix case of exercise 03.3);
   - region limited to `francecentral` and `westeurope`;
   - tags defined only once in the file;
   - three outputs: workspace ID, storage account ID, identity `principalId`.
3. `what-if`: no creation, no deletion (minor changes to undeclared properties are accepted, to be explained).
4. Deploy, then simulate a drift:
   ```bash
   az storage account update -n starveost<NN>diag -g rg-st<NN>-shared --access-tier Cool
   az tag update --resource-id "$(az storage account show -n starveost<NN>diag \
     -g rg-st<NN>-shared --query id -o tsv)" --operation Merge --tags Temporaire=oui
   ```
5. Detect the drift with `what-if`, fix it by redeploying, then prove that the account is back to the described state.

**Success criteria** :
- [ ] `az bicep build --file socle.bicep` produces no error.
- [ ] The post-drift `what-if` shows `~` on the storage account, with `accessTier` modified and `tags.Temporaire` removed.
- [ ] After redeployment, `az storage account show -n starveost<NN>diag --query "{Tier:accessTier, Tags:tags}"` displays `Hot` and exactly the three Arvéo tags.
- [ ] A new `what-if` reports no change on the storage account.

---

## Bonus 🚀
1. **Parameter file**: create `socle.bicepparam` (parameter `numero`), then deploy with `--parameters socle.bicepparam` alone, without `--template-file`.
2. **Template spec**: publish `socle.bicep` as template spec `ts-st<NN>-socle`, version `1.0`, in `rg-st<NN>-shared`, then deploy from this template spec.
3. **Comparison**: deploy `socle.bicep` from PowerShell (`New-AzResourceGroupDeployment`) with `-WhatIf`, and compare the display with the CLI one.

## Cleanup
- No deletion: the `rg-st<NN>-shared` foundation is reused in modules 7 and 10.
- Cost: workspace without ingestion and empty storage account = near-zero cost `[TO VERIFY]` Azure pricing calculator.
- Bonus 2: the template spec can stay (no cost) or be deleted with `az ts delete --name ts-st<NN>-socle -g rg-st<NN>-shared --yes`.
