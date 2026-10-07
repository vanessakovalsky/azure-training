# Module 02 — Solutions

All solutions assume the session variables are defined:

```bash
ST="st<NN>"
DOMAINE="<DOMAIN>"
SUB_ID=$(az account show --query id --output tsv)
```

---

## Lab 02.1 ⭐ — Organize and tag the Arvéo landing zone

### Solution
The lab steps are the solution. Full-CLI variant for step 2 (portal):

```bash
RG_ID=$(az group show --name "rg-${ST}-hub" --query id --output tsv)
az tag update --resource-id "$RG_ID" --operation Merge --output none \
  --tags Proprietaire=$ST CentreDeCout=CC-IT-1042 Environnement=Prod Application=Socle
```

Checking the tags of a single group:

```bash
az tag list --resource-id "$(az group show --name rg-${ST}-hub --query id -o tsv)" \
  --query "properties.tags"
```
Expected output:
```
{
  "Application": "Socle",
  "CentreDeCout": "CC-IT-1042",
  "Environnement": "Prod",
  "Proprietaire": "st07"
}
```

Budget: creation in the portal is the reference method (alerts and recipients in the same wizard). Suggested amount: the one announced by the trainer, based on the pricing calculator estimate for the hub firewall and VPN gateway `[TO VERIFY]`.

### Why
- **`Proprietaire` tag**: in the shared subscription, it is the only reliable filter to isolate one trainee's groups in cost analysis (`CentreDeCout` values are the same for everyone).
- **`az tag update --operation Merge`** rather than `az group update --tags`: the latter replaces all tags; a tag set by the trainer or by a policy would be lost.
- **Budget on `rg-stNN-hub`**: this group will hold the two most expensive resources of the course (Azure Firewall in module 4, VPN gateway in module 5).
- **"Forecasted" alert at 100 %**: warns BEFORE the overspend, based on the trend; the "Actual" alert at 80 % confirms the observed consumption.
- **Personal email**: `stNN` accounts have no Exchange Online license, hence no mailbox.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `ResourceGroupNotFound` | `ST` variable not defined (new Cloud Shell session) or typo | Redefine `ST`, check with `echo $ST` |
| `AuthorizationFailed` on `az tag update` | Another trainee's group (wrong number) | Check `<NN>`; only the trainee's `rg-stNN-*` groups can be modified |
| Hub tags gone after a command | `az group update --tags` used | Reapply with `az tag update --operation Merge` |
| **Budgets** menu missing or greyed out | Subscription offer type not supported by Cost Management `[TO VERIFY]` | Trainer demo on their own resource group |
| `az consumption budget list` fails | Command group in preview | Check in the portal |
| `declare -A` loop fails | PowerShell shell open instead of Bash | Switch Cloud Shell to **Bash** |

---

## Exercise 02.2 ⭐⭐ — Region and VM size guardrails

### Solution

1. Retrieve the built-in definitions (once; the full list is slow to load):

```bash
DEF_LOC=$(az policy definition list \
  --query "[?displayName=='Allowed locations'].name" --output tsv)
DEF_SKU=$(az policy definition list \
  --query "[?displayName=='Allowed virtual machine size SKUs'].name" --output tsv)
echo "$DEF_LOC / $DEF_SKU"
```
Expected output:
```
e56962a6-4747-49cd-b67b-bf8b01975c4c / cccc23c7-8427-4f53-ad12-b6a63eb452b3
```
The GUIDs are those of the public built-in definitions `[TO VERIFY]`; only the `displayName` lookup is authoritative.

2. Assign "Allowed locations" on the six groups:

```bash
for R in shared hub spoke data app lyon; do
  REGION=francecentral; [ "$R" = "lyon" ] && REGION=westeurope
  az policy assignment create --name "pa-${ST}-loc-${R}" \
    --display-name "Arveo ${ST} - Allowed regions (${R})" \
    --policy "$DEF_LOC" --resource-group "rg-${ST}-${R}" \
    --params "{\"listOfAllowedLocations\":{\"value\":[\"${REGION}\"]}}" \
    --output none
done
```

3. Assign "Allowed virtual machine size SKUs" on `app` and `lyon`:

```bash
for R in app lyon; do
  az policy assignment create --name "pa-${ST}-vmsku-${R}" \
    --display-name "Arveo ${ST} - Allowed VM sizes (${R})" \
    --policy "$DEF_SKU" --resource-group "rg-${ST}-${R}" \
    --params '{"listOfAllowedSKUs":{"value":["Standard_B1s","Standard_B2s","Standard_B2ms"]}}' \
    --output none
done
```

4. Check the assignments (success criterion):

```bash
for R in shared hub spoke data app lyon; do
  az policy assignment list --resource-group "rg-${ST}-${R}" \
    --query "[?starts_with(name,'pa-${ST}-')].name" --output tsv
done
```
Expected output:
```
pa-st07-loc-shared
pa-st07-loc-hub
pa-st07-loc-spoke
pa-st07-loc-data
pa-st07-loc-app
pa-st07-vmsku-app
pa-st07-loc-lyon
pa-st07-vmsku-lyon
```

5. Proof of denial (after a few minutes):

```bash
az network nsg create --resource-group "rg-${ST}-hub" \
  --name "nsg-${ST}-test" --location westeurope
```
Expected output (excerpt):
```
(RequestDisallowedByPolicy) Resource 'nsg-st07-test' was disallowed by policy.
```

6. Proof of acceptance, then cleanup:

```bash
az network nsg create --resource-group "rg-${ST}-hub" \
  --name "nsg-${ST}-test" --location francecentral \
  --query "NewNSG.provisioningState" --output tsv
az network nsg delete --resource-group "rg-${ST}-hub" --name "nsg-${ST}-test"
```
Expected output:
```
Succeeded
```

7. Compliance:

```bash
az policy state trigger-scan --resource-group "rg-${ST}-hub"
az policy state summarize --resource-group "rg-${ST}-hub" \
  --query "results.{nonCompliant:nonCompliantResources, policies:nonCompliantPolicies}"
```
Expected output:
```
{
  "nonCompliant": 0,
  "policies": 0
}
```
Without `--no-wait`, `trigger-scan` returns when the scan ends (possibly several minutes).

### Why
- **Resource group scope**: in the shared tenant, trainees cannot assign at subscription level; in the enterprise, these two policies would be assigned once on the `mg-arveo` management group, with an exclusion (`notScopes`) for the Lyon site.
- **NSG as test resource**: instant, free creation, subject to the region (`Indexed` mode).
- **Virtual network in West Europe in `rg-stNN-lyon`**: allowed because that group's assignment specifies `westeurope`. Assignments are independent: each group has its own list.
- **`global` resources** (private DNS zones in module 4, action groups and metric alert rules in module 10): excluded by the built-in rule (`notEquals: global`), so not blocked.
- **VM sizes**: the B series covers all labs (modules 5 to 9). Any other size requires updating the parameter, which records the decision.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `DEF_LOC` empty | Typo in `displayName` (case-sensitive) | Copy the exact name: `Allowed locations` |
| `InvalidPolicyParameters` | Badly escaped `--params` JSON (quotes in the loop) | Reuse the `\"…\"` syntax from the solution |
| `InvalidRequestContent` on `--params` | Wrong parameter name (`listOfAllowedLocation`) | `az policy definition show --name $DEF_LOC --query parameters` |
| West Europe NSG accepted | Assignment too recent | Wait a few minutes, then retry |
| `trigger-scan` very long | Whole group evaluated | Add `--no-wait`, check compliance later |
| Empty compliance summary | Initial evaluation not finished | Rerun `summarize` after a few minutes |

### Acceptable variants
- **Portal**: **Policy** → **Assignments** → **Assign policy** → scope = resource group → "Allowed locations" definition → **Parameters** tab. Slower for six groups, but shows the **Exclusions** field.
- **Initiative**: cannot be created by trainees (definition at subscription level), but an "Arvéo - Baseline" initiative grouping both definitions would avoid eight assignments.
- **Az PowerShell** `[TO VERIFY]` on the `DisplayName` property depending on the Az.Resources version:
  ```powershell
  $def = Get-AzPolicyDefinition -Builtin | Where-Object DisplayName -eq 'Allowed locations'
  New-AzPolicyAssignment -Name "pa-$ST-loc-hub" -PolicyDefinition $def `
    -Scope (Get-AzResourceGroup -Name "rg-$ST-hub").ResourceId `
    -PolicyParameterObject @{ listOfAllowedLocations = @('francecentral') }
  ```

---

## Exercise 02.3 ⭐⭐ — Arvéo access matrix and lock

### Solution

1. Group identifiers:

```bash
ID_RESEAU=$(az ad group show --group "${ST}-GRP-AdminsReseau" --query id --output tsv)
ID_EXPLOIT=$(az ad group show --group "${ST}-GRP-Exploitation" --query id --output tsv)
ID_LOGIST=$(az ad group show --group "${ST}-GRP-Logistique" --query id --output tsv)
echo "$ID_RESEAU / $ID_EXPLOIT / $ID_LOGIST"
```
Expected output: three non-empty GUIDs.

2. Assignments:

```bash
for R in hub spoke; do
  az role assignment create --assignee-object-id "$ID_RESEAU" \
    --assignee-principal-type Group --role "Network Contributor" \
    --resource-group "rg-${ST}-${R}" --output none
done
az role assignment create --assignee-object-id "$ID_EXPLOIT" \
  --assignee-principal-type Group --role "Virtual Machine Contributor" \
  --resource-group "rg-${ST}-app" --output none
az role assignment create --assignee-object-id "$ID_LOGIST" \
  --assignee-principal-type Group --role "Reader" \
  --resource-group "rg-${ST}-app" --output none
```

3. Check (success criterion):

```bash
for R in hub spoke app; do
  az role assignment list --resource-group "rg-${ST}-${R}" \
    --query "[?principalType=='Group'].{group:principalName, role:roleDefinitionName}" \
    --output table
done
```
Expected output:
```
Group                  Role
---------------------  -------------------
st07-GRP-AdminsReseau  Network Contributor
Group                  Role
---------------------  -------------------
st07-GRP-AdminsReseau  Network Contributor
Group                  Role
---------------------  ---------------------------
st07-GRP-Exploitation  Virtual Machine Contributor
st07-GRP-Logistique    Reader
```

4. Léa Martin's effective access:

```bash
az role assignment list --assignee "${ST}-lea.martin@${DOMAINE}" \
  --all --include-groups \
  --query "[].{role:roleDefinitionName, scope:scope}" --output table
```
Expected output:
```
Role    Scope
------  ----------------------------------------------------------
Reader  /subscriptions/1a2b3c4d-…/resourceGroups/rg-st07-app
```
Portal: `rg-stNN-app` → **Access control (IAM)** → **Check access** → `stNN-lea.martin` → Reader role, assignment shown as inherited from a group `[TO VERIFY]` on the exact label.

5. Lock and proof:

```bash
az lock create --name "lock-${ST}-shared" --lock-type CanNotDelete \
  --resource-group "rg-${ST}-shared" --notes "Arveo shared resources"
az network nsg create --resource-group "rg-${ST}-shared" \
  --name "nsg-${ST}-verrou" --location francecentral --output none
az network nsg delete --resource-group "rg-${ST}-shared" --name "nsg-${ST}-verrou"
```
Expected output (last command, excerpt):
```
(ScopeLocked) The scope '/subscriptions/…/resourceGroups/rg-st07-shared/providers/
Microsoft.Network/networkSecurityGroups/nsg-st07-verrou' cannot perform delete
operation because following scope(s) are locked: '…/resourceGroups/rg-st07-shared'.
```

### Why
- **Groups rather than users**: joiners and leavers are handled in Entra ID (module 1), without touching Azure assignments.
- **`--assignee-object-id` + `--assignee-principal-type`**: avoids a name lookup in Microsoft Graph and replication failures right after a group is created.
- **Network Contributor on hub AND spoke**: peering (module 5) is configured on both sides; rights on the hub alone are not enough.
- **Reader for logistics**: visibility on the customer portal without any possible change.
- **Lock at group level**: also protects resources created later in `rg-stNN-shared` (inheritance).
- **Owner blocked**: the lock applies to everyone; it must be REMOVED to delete a resource, which forces a deliberate action recorded in the activity log.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `az ad group show`: `Resource … does not exist` | Group named differently in module 1 | `az ad group list --filter "startswith(displayName,'${ST}')" --query "[].displayName"` |
| `PrincipalNotFound` | Group created a few seconds ago (replication) | Retry after 1 to 2 minutes |
| `AuthorizationFailed` on `Microsoft.Authorization/roleAssignments/write` | Scope outside `rg-stNN-*` (e.g. subscription) | The trainee is Owner of their groups only |
| Léa Martin with no assignment | `--include-groups` forgotten, or Léa not in the group | Add the option; check `az ad group member list --group "${ST}-GRP-Logistique"` |
| NSG deletion succeeds | Lock created on the wrong group | `az lock list --resource-group "rg-${ST}-shared" --output table` |
| `RoleAssignmentExists` | Command rerun | Harmless: the assignment already exists |

### Acceptable variants
- **Portal**: resource group → **Access control (IAM)** → **Add role assignment** → role → members → group. Recommended for the first assignment (shows the Role / Members / Conditions tabs).
- **Az PowerShell**:
  ```powershell
  $id = (Get-AzADGroup -DisplayName "$ST-GRP-AdminsReseau").Id
  New-AzRoleAssignment -ObjectId $id -RoleDefinitionName "Network Contributor" `
    -ResourceGroupName "rg-$ST-hub"
  New-AzResourceLock -LockName "lock-$ST-shared" -LockLevel CanNotDelete `
    -ResourceGroupName "rg-$ST-shared" -Force
  ```
- **Contributor instead of Network Contributor**: rejected, because it also allows creating VMs, storage accounts, etc. in the hub.

---

## Challenge 02.4 ⭐⭐⭐ — "VM Operator" custom role

### Solution

1. Role definition:

```bash
RG_APP_ID=$(az group show --name "rg-${ST}-app" --query id --output tsv)
cat > "role-${ST}-operateur-vm.json" <<EOF
{
  "Name": "${ST}-Operateur-VM-Arveo",
  "IsCustom": true,
  "Description": "Arveo - view, start, stop, deallocate and restart VMs",
  "Actions": [
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/instanceView/read",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/powerOff/action",
    "Microsoft.Compute/virtualMachines/deallocate/action",
    "Microsoft.Compute/virtualMachines/restart/action",
    "Microsoft.Compute/disks/read",
    "Microsoft.Network/networkInterfaces/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": [ "${RG_APP_ID}" ]
}
EOF
az role definition create --role-definition "@role-${ST}-operateur-vm.json" \
  --query "{name:roleName, type:roleType}" --output table
```
Expected output:
```
Name                     Type
-----------------------  ----------
st07-Operateur-VM-Arveo  CustomRole
```

2. Replacing the assignment (wait 1 to 2 minutes if the role is not found yet):

```bash
ID_EXPLOIT=$(az ad group show --group "${ST}-GRP-Exploitation" --query id --output tsv)
az role assignment create --assignee-object-id "$ID_EXPLOIT" \
  --assignee-principal-type Group --role "${ST}-Operateur-VM-Arveo" \
  --scope "$RG_APP_ID" --output none
az role assignment delete --assignee "$ID_EXPLOIT" \
  --role "Virtual Machine Contributor" --resource-group "rg-${ST}-app"
```

3. Checks:

```bash
az role definition list --custom-role-only true --scope "$RG_APP_ID" \
  --query "[?roleName=='${ST}-Operateur-VM-Arveo'].assignableScopes[]" --output tsv
az role assignment list --resource-group "rg-${ST}-app" \
  --query "[?principalName=='${ST}-GRP-Exploitation'].roleDefinitionName" --output tsv
```
Expected output:
```
/subscriptions/1a2b3c4d-…/resourceGroups/rg-st07-app
st07-Operateur-VM-Arveo
```

Expected answer to the lock question: **not compatible**. A `ReadOnly` lock blocks write operations AND actions sent as POST requests; `start`, `restart`, `powerOff` and `deallocate` are POSTs. The team could no longer start or stop VMs. A `CanNotDelete` lock is compatible: it blocks deletion, not operations.

### Why
- **No `virtualMachines/*`**: the wildcard would include `write` (resize) and `delete`.
- **`instanceView/read`**: needed to show the power state (running, deallocated); without it, the portal does not show the actual state.
- **`deallocate` on top of `powerOff`**: only `deallocate` stops compute billing (reminder from S2.1).
- **`disks/read` and `networkInterfaces/read`**: complete VM view in the portal (Disks and Networking tabs).
- **`resourceGroups/read`**: navigation to the group in the portal.
- **`AssignableScopes` limited to `rg-stNN-app`**: the role cannot be reused elsewhere by mistake, and the trainee only has `roleDefinitions/write` on their own groups anyway.
- **Create BEFORE delete**: the team never loses access during the switch.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `RoleDefinitionWithSameNameExists` | Name already used in the tenant (another trainee, wrong number) | Check the `stNN` prefix |
| `AuthorizationFailed` when creating the role | `AssignableScopes` at subscription level | Limit to `rg-stNN-app` |
| `Role '…' doesn't exist` at assignment | New role replicating, or subscription lookup scope | Wait; use `--scope "$RG_APP_ID"` |
| Role missing from `az role definition list` | Lookup at subscription scope by default | Add `--scope "$RG_APP_ID"` |
| `InvalidActionOrNotAction` | Typo in an operation name | `az provider operation show --namespace Microsoft.Compute --query "resourceTypes[?name=='virtualMachines'].operations[].name"` |
| JSON file with literal `${ST}` | Heredoc written as `<<'EOF'` (quoted) | Use `<<EOF` without quotes |

### Acceptable variants
- **Portal**: `rg-stNN-app` → **Access control (IAM)** → **Add** → **Add custom role** → **Clone a role** (Virtual Machine Contributor) → remove unneeded actions. More visual, but cloning starts from a role that is too broad: risk of leaving a `write` action.
- **`Microsoft.Insights/metrics/read`** added: acceptable (viewing CPU metrics during on-call).
- **Adding `virtualMachineScaleSets/start/action` and `virtualMachineScaleSets/deallocate/action`**: relevant if the team also operates the module 7 VMSS; to be justified.
- **Az PowerShell**: `New-AzRoleDefinition -InputFile "role-$ST-operateur-vm.json"`.

---

## Bonus — Automatic cost center inheritance

### Solution

```bash
DEF_TAG=$(az policy definition list \
  --query "[?displayName=='Inherit a tag from the resource group if missing'].name" \
  --output tsv)
ROLE_ID=$(az policy definition show --name "$DEF_TAG" \
  --query "policyRule.then.details.roleDefinitionIds[0]" --output tsv)
for R in app spoke; do
  RG_ID=$(az group show --name "rg-${ST}-${R}" --query id --output tsv)
  for T in CentreDeCout Environnement; do
    az policy assignment create --name "pa-${ST}-tag-${T}-${R}" \
      --policy "$DEF_TAG" --scope "$RG_ID" \
      --params "{\"tagName\":{\"value\":\"${T}\"}}" \
      --mi-system-assigned --location francecentral \
      --role "$ROLE_ID" --identity-scope "$RG_ID" --output none
  done
done
```

Test (wait a few minutes after the assignment):

```bash
az network nsg create --resource-group "rg-${ST}-app" \
  --name "nsg-${ST}-tagtest" --location francecentral \
  --query "NewNSG.tags" --output json
az network nsg delete --resource-group "rg-${ST}-app" --name "nsg-${ST}-tagtest"
```
Expected output:
```
{
  "CentreDeCout": "CC-IT-1042",
  "Environnement": "Prod"
}
```

Remediation task (resources created before the assignment):

```bash
az policy remediation create --name "rem-${ST}-tag-cc-app" \
  --policy-assignment "pa-${ST}-tag-CentreDeCout-app" --resource-group "rg-${ST}-app"
```

### Why
- **`Modify` effect**: the policy completes the create request before it runs; no tag is forgotten, even by a script.
- **Managed identity**: needed for the remediation task, which changes EXISTING resources on behalf of the assignment.
- **Role read from the definition** (`roleDefinitionIds`): avoids guessing the role and honors the least privilege intended by the definition's author.
- **One assignment per tag**: the built-in definition takes a single tag name as parameter.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `The policy assignment … requires a managed identity` | `--mi-system-assigned` option missing | Recreate the assignment with the identity |
| `--location` required | Managed identity without region | Add `--location francecentral` |
| NSG created without tags | Assignment too recent | Wait, delete and recreate the NSG |
| Remediation task fails | Identity role assignment not propagated yet | Rerun the task after a few minutes |

---

## QCM — Réponses
1. **A** — A resource belongs to a single resource group; a move changes its group.
2. **C** — Tags are not inherited; only a policy (`Modify`, "Inherit a tag…") copies them.
3. **C** — A budget sends notifications and can trigger an action group, without stopping anything itself.
4. **B** — `Deny` rejects the request; `Audit` and `AuditIfNotExists` log, `Append` adds fields.
5. **B** — A custom definition is saved on a management group or a subscription.
6. **B** — Effective rights are the union of inherited and direct roles: Contributor prevails.
7. **C** — Contributor manages everything except access; Owner manages access too.
8. **B** — `ReadOnly` blocks POSTs such as `start`, even for an owner.
