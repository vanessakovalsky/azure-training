# Module 02 — Exercises

**Common environment for all labs**
- Azure Cloud Shell in **Bash** mode (Azure CLI preinstalled), signed in as `stNN@<DOMAIN>`
- Permissions: Owner on the six `rg-stNN-*` groups, Reader on the subscription, Global Reader on the tenant
- Objects from module 01 (or from the `scripts/catch-up/module-01` script):

| Object | Type | Expected members |
|---|---|---|
| `stNN-GRP-AdminsReseau` | Security group | Arvéo network administrators |
| `stNN-GRP-Exploitation` | Security group | Operations team |
| `stNN-GRP-Logistique` | Security group | Including `stNN-lea.martin` |

Object names (groups, tags, assignments) are identical in the French and English courses: the tenant is shared.

Variables to define at the start of EVERY Cloud Shell session:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<DOMAIN>` = training tenant domain (e.g. `arveoformation.onmicrosoft.com`)

```bash
ST="st<NN>"
DOMAINE="<DOMAIN>"
SUB_ID=$(az account show --query id --output tsv)
echo "Trainee: $ST · Subscription: $SUB_ID"
```
Expected result: `Trainee: st07 · Subscription: 1a2b3c4d-…` (identifier specific to the training tenant).

---

## Lab 02.1 ⭐ — Organize and tag the Arvéo landing zone (guided)
**Duration**: 25 min · **Objective**: 2 (structure the environment, tags, budget)
**Context**: Arvéo's finance department wants Azure costs charged back to IT cost center `CC-IT-1042` and to be alerted before any overspend on the hub network (firewall and VPN gateway, deployed in modules 4 and 5).
**Prerequisites**: six empty `rg-stNN-*` resource groups, Cloud Shell open, variables defined.

### Steps
1. Locate the subscription in the hierarchy.
   - Portal: **Subscriptions** → training subscription → **Overview** → **Parent management group** field.
   - Then list the trainee's resource groups:
   ```bash
   az group list --query "[?starts_with(name,'rg-${ST}-')].{name:name, region:location}" \
     --output table
   ```
   Expected result (6 rows, order may vary):
   ```
   Name            Region
   --------------  -------------
   rg-st07-shared  francecentral
   rg-st07-hub     francecentral
   rg-st07-spoke   francecentral
   rg-st07-data    francecentral
   rg-st07-app     francecentral
   rg-st07-lyon    westeurope
   ```

2. Tag `rg-stNN-hub` from the portal.
   - **Resource groups** → `rg-stNN-hub` → **Tags**.
   - Add: `Proprietaire` = `stNN`, `CentreDeCout` = `CC-IT-1042`, `Environnement` = `Prod`, `Application` = `Socle`.
   - **Apply**.
   Expected result: the group's **Overview** shows the four tags.

3. Tag the other five groups with the CLI (merge, no overwrite).
   ```bash
   declare -A APP=( [shared]=Socle [spoke]=Socle [data]=Donnees \
                    [app]=PortailClient [lyon]=SiteLyon )
   for R in "${!APP[@]}"; do
     ENV=Prod; [ "$R" = "lyon" ] && ENV=HorsProd
     RG_ID=$(az group show --name "rg-${ST}-${R}" --query id --output tsv)
     az tag update --resource-id "$RG_ID" --operation Merge --output none \
       --tags Proprietaire=$ST CentreDeCout=CC-IT-1042 Environnement=$ENV \
              Application=${APP[$R]}
   done
   ```
   Expected result: no output, no error message.

4. Check the full taxonomy.
   ```bash
   az group list --tag Proprietaire=$ST \
     --query "[].{RG:name, App:tags.Application, Env:tags.Environnement, CC:tags.CentreDeCout}" \
     --output table
   ```
   Expected result (order may vary):
   ```
   RG              App            Env       CC
   --------------  -------------  --------  ----------
   rg-st07-shared  Socle          Prod      CC-IT-1042
   rg-st07-hub     Socle          Prod      CC-IT-1042
   rg-st07-spoke   Socle          Prod      CC-IT-1042
   rg-st07-data    Donnees        Prod      CC-IT-1042
   rg-st07-app     PortailClient  Prod      CC-IT-1042
   rg-st07-lyon    SiteLyon       HorsProd  CC-IT-1042
   ```

5. Create a budget on `rg-stNN-hub` (portal).
   - `rg-stNN-hub` → **Budgets** (Cost Management section) → **+ Add**.
   - Name: `bud-stNN-hub` · Reset period: **Monthly** · Expiration date: end of the current year.
   - Amount: `<BUDGET_AMOUNT>` (value announced by the trainer).
   - **Next** → alert conditions:
     - Type **Actual**, threshold **80 %**
     - Type **Forecasted**, threshold **100 %**
   - Recipients: `<TRAINEE_EMAIL>` (personal address, the `stNN` account has no mailbox) · Language: **English**.
   - **Create**.
   Expected result: budget `bud-stNN-hub` appears in the list with a spent amount of 0 or close to 0.

6. Check the budget with the CLI (`az consumption` command group in preview).
   ```bash
   az consumption budget list --resource-group "rg-${ST}-hub" \
     --query "[].{name:name, amount:amount, period:timeGrain}" --output table
   ```
   Expected result:
   ```
   Name          Amount    Period
   ------------  --------  --------
   bud-st07-hub  100.0     Monthly
   ```
   If the command fails, check in the portal (step 5): the portal check is authoritative.

7. Review Azure Advisor cost recommendations.
   ```bash
   az advisor recommendation list --category Cost --output table
   ```
   Expected result: empty list or recommendations on other resources in the subscription (no resource deployed by the trainee yet).

8. Explore cost analysis by tag.
   - `rg-stNN-hub` → **Cost analysis** → **Group by** → **Tag** → `CentreDeCout`.
   Expected result: empty or nearly empty chart (no billable resource), grouping ready for the next modules.

### Success criteria
- [ ] Six `rg-stNN-*` groups carry the four taxonomy tags (step 4 command)
- [ ] `rg-stNN-lyon` carries `Environnement=HorsProd`, the other five `Prod`
- [ ] Monthly budget `bud-stNN-hub` with two alerts (80 % actual, 100 % forecasted)
- [ ] Oral explanation: why the budget will NOT stop the VPN gateway on overspend

---

## Exercise 02.2 ⭐⭐ — Region and VM size guardrails (semi-autonomous)
**Duration**: 25 min · **Objective**: 2 (apply an Azure Policy denying a non-compliant resource)
**Context**: Arvéo's CISO requires data residency in France. Only the simulated Lyon site (`rg-stNN-lyon`) stays in West Europe. To control the budget, only the B-series VM sizes approved by IT are allowed.

**Task**: obtain the following guardrails, using built-in policies only.

| Requirement | Scope | Parameter |
|---|---|---|
| Allowed regions | `rg-stNN-shared`, `-hub`, `-spoke`, `-data`, `-app` | `francecentral` |
| Allowed regions | `rg-stNN-lyon` | `westeurope` |
| Allowed VM sizes | `rg-stNN-app`, `rg-stNN-lyon` | `Standard_B1s`, `Standard_B2s`, `Standard_B2ms` |

Assignment naming conventions:
- `pa-stNN-loc-<suffix>` (e.g. `pa-st07-loc-hub`)
- `pa-stNN-vmsku-<suffix>` (e.g. `pa-st07-vmsku-app`)

Expected evidence:
1. Creating network security group `nsg-stNN-test` in **West Europe** in `rg-stNN-hub`: **denied**.
2. Creating the same NSG in **France Central**: **accepted**, then the NSG is deleted.
3. Compliance summary of `rg-stNN-hub` after an on-demand scan.

**Hints**
- Built-in policies: "Allowed locations" and "Allowed virtual machine size SKUs".
- Parameters: `listOfAllowedLocations` and `listOfAllowedSKUs`.
- `az policy definition list --query "[?displayName=='…'].name"` returns a definition's name (GUID).
- `az policy assignment create` accepts `--resource-group` as scope and `--params` as JSON.
- A `for` loop over the suffixes `shared hub spoke data app lyon` avoids six commands.
- An assignment takes a few minutes to take effect: wait before the denial test.
- `az policy state trigger-scan` then `az policy state summarize`.

**Success criteria**
- [ ] Eight assignments visible:
  ```bash
  for R in shared hub spoke data app lyon; do
    az policy assignment list --resource-group "rg-${ST}-${R}" \
      --query "[?starts_with(name,'pa-${ST}-')].name" --output tsv
  done
  ```
- [ ] `RequestDisallowedByPolicy` message when creating in West Europe
- [ ] Test NSG in France Central created then deleted (no `nsg-stNN-test` left)
- [ ] Explanation: why a virtual network in `rg-stNN-lyon` in West Europe is still allowed

---

## Exercise 02.3 ⭐⭐ — Arvéo access matrix and lock (semi-autonomous)
**Duration**: 15 min · **Objective**: 3 (assign RBAC roles at the right scope)
**Context**: Arvéo IT formalizes delegated permissions before deploying the network (module 4) and VMs (module 7). Shared resources (logging, upcoming key vault) must never be deleted by mistake.

**Task**

1. Apply the following access matrix, assigning roles to **groups**:

| Group | Built-in role | Scope |
|---|---|---|
| `stNN-GRP-AdminsReseau` | Network Contributor | `rg-stNN-hub`, `rg-stNN-spoke` |
| `stNN-GRP-Exploitation` | Virtual Machine Contributor | `rg-stNN-app` |
| `stNN-GRP-Logistique` | Reader | `rg-stNN-app` |

2. Check the effective access of `stNN-lea.martin` (member of `stNN-GRP-Logistique`):
   - with the CLI;
   - in the portal, with **Access control (IAM)** → **Check access**.
3. Place a `CanNotDelete` lock named `lock-stNN-shared` on `rg-stNN-shared`.
4. Prove the lock's effect: create NSG `nsg-stNN-verrou` (France Central) in `rg-stNN-shared`, then try to delete it.

**Hints**
- `az ad group show --group <NAME> --query id --output tsv`: object ID of a group (read allowed by the Global Reader role).
- `az role assignment create`: prefer `--assignee-object-id` + `--assignee-principal-type Group`.
- `az role assignment list --assignee <UPN> --all --include-groups`: direct AND group-based assignments.
- `az lock create`, `az lock list`.
- NSG `nsg-stNN-verrou` is kept (free): it is deleted by the end-of-course cleanup.

**Success criteria**
- [ ] Four role assignments visible:
  ```bash
  for R in hub spoke app; do
    az role assignment list --resource-group "rg-${ST}-${R}" \
      --query "[?principalType=='Group'].{group:principalName, role:roleDefinitionName}" \
      --output table
  done
  ```
- [ ] `stNN-lea.martin`: Reader on `rg-stNN-app` only (excluding rights inherited from the subscription)
- [ ] Deletion of `nsg-stNN-verrou` denied with a `ScopeLocked` message
- [ ] Explanation: why the trainee, owner of the group, is blocked too

---

## Challenge 02.4 ⭐⭐⭐ — "VM Operator" custom role (autonomous)
**Duration**: 10 min · **Objective**: 3 (create a custom role, least privilege)
**Context**: Arvéo's internal audit notes that the operations team, with the Virtual Machine Contributor role, can DELETE or resize the customer portal VMs. Its actual need is limited to on-call operations.

**Task**: replace the Virtual Machine Contributor assignment of `stNN-GRP-Exploitation` with a custom role meeting these constraints:
- Name: `stNN-Operateur-VM-Arveo` (unique in the tenant).
- Allowed: view VMs, their power state, disks and network interfaces; start, stop, deallocate and restart VMs.
- Forbidden: create, modify, resize or delete any resource.
- Assignable on `rg-stNN-app` only.
- No wildcard (`*`) in actions.
- To justify: each action kept, based on the list of `Microsoft.Compute` provider operations.

Written question: is a `ReadOnly` lock on `rg-stNN-app` compatible with this team's work? Justify.

**Success criteria**
- [ ] `az role definition list --custom-role-only true --scope <RG_APP_ID>` shows the role with a single assignable scope
- [ ] No `write`, `delete` or `*` action in the definition
- [ ] `stNN-GRP-Exploitation`: custom role on `rg-stNN-app`, no Virtual Machine Contributor assignment left
- [ ] Reasoned answer about the `ReadOnly` lock

---

## Bonus 🚀 — Automatic cost center inheritance
**Context**: tags placed on resource groups are not inherited by resources. Finance wants every resource deployed in the following modules to automatically carry `CentreDeCout` and `Environnement`.

**Task**
1. Assign the built-in policy "Inherit a tag from the resource group if missing" on `rg-stNN-app` and `rg-stNN-spoke`, one assignment per tag (`CentreDeCout`, `Environnement`), named `pa-stNN-tag-<tag>-<suffix>`.
2. Give each assignment a system-assigned managed identity (region `francecentral`) with the role specified in the definition, limited to the resource group.
3. Create NSG `nsg-stNN-tagtest` in `rg-stNN-app` WITHOUT tags, check the inherited tags, then delete the NSG.
4. Explain the purpose of a remediation task for resources created BEFORE the assignment.

**Hints**
- `az policy definition show --name <GUID> --query "policyRule.then.details.roleDefinitionIds"`: role required by the definition.
- `az policy assignment create … --mi-system-assigned --location francecentral --role <ROLE> --identity-scope <RG_ID>`.
- `az policy remediation create --policy-assignment <NAME> --resource-group <RG>`.
