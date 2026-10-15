# Module 12 — Synthesis case: solutions

Solution of the seven requests of `module-12-synthesis-exercises.md`, with the variable block of the exercise. Outputs shown for `st07`, `SES=1510`.

---

## Request 1 — Auditor access (M1, M2)

```bash
AU_ID=$(az rest --method get \
  --url "https://graph.microsoft.com/v1.0/directory/administrativeUnits?\$filter=displayName eq 'AU-${ST}'" \
  --query "value[0].id" -o tsv)
az rest --method post \
  --url "https://graph.microsoft.com/v1.0/directory/administrativeUnits/${AU_ID}/members" \
  --headers "Content-Type=application/json" \
  --body "{\"@odata.type\":\"#microsoft.graph.group\",\"displayName\":\"${ST}-GRP-Audit\",
           \"mailEnabled\":false,\"mailNickname\":\"${ST}-grp-audit\",\"securityEnabled\":true}" -o none
GID=$(az ad group show --group "${ST}-GRP-Audit" --query id -o tsv)
az role assignment create --assignee-object-id "$GID" --assignee-principal-type Group \
  --role Reader --scope "$(az group show -n "rg-${ST}-data" --query id -o tsv)" -o none
az role assignment list -g "rg-${ST}-data" \
  --query "[?principalName=='${ST}-GRP-Audit'].{Role:roleDefinitionName, Scope:scope}" -o table
```
Expected output:
```
Role    Scope
------  ------------------------------------------------------------------
Reader  /subscriptions/<ID>/resourceGroups/rg-st07-data
```

### Why
- Creation IN the AU: the only path open to a delegated groups administrator (module 1).
- `--assignee-principal-type Group`: avoids the replication error when the group has just been created.
- Question c: the role follows the function (the group), not the person; someone leaving = removal from the group, no change to assignments.

---

## Request 2 — Compliance (M2)

```bash
az tag update --resource-id "$(az group show -n "rg-${ST}-app" --query id -o tsv)" \
  --operation Merge --tags Audit=2026 -o none
az group show -n "rg-${ST}-app" --query tags -o json
az network nsg create -g "rg-${ST}-app" -n "nsg-${ST}-eval" -l westeurope
```
Expected output: existing tags (`Projet`, `Environnement`, `Proprietaire`) + `Audit`, then `(RequestDisallowedByPolicy) Resource 'nsg-st07-eval' was disallowed by policy.`

### Why
- `--operation Merge` adds without overwriting; `az group update --tags` replaces ALL tags.
- Denied by the module 2 "Regions autorisees" assignment: `deny` effect evaluated at creation.

---

## Request 3 — Versioned rule (M3, M4)

`eval.bicep`:
```bicep
param location string = 'francecentral'
param numero string

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-st${numero}-eval'
  location: location
  tags: {
    Projet: 'Arveo'
    Environnement: 'Formation'
    Proprietaire: 'st${numero}'
  }
  properties: {
    securityRules: [
      {
        name: 'Deny-SSH-Internet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Deny'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}
```
```bash
az deployment group create -g "rg-${ST}-app" -f eval.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
az deployment group what-if -g "rg-${ST}-app" -f eval.bicep -p numero="$NN"
az deployment group create -g "rg-${ST}-app" -f eval.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
```
Expected output: `Succeeded`, then `what-if`: `Resource changes: 1 no change.`, then `Succeeded`.

### Why
- Tags in the template: otherwise the module 2 "mandatory tag" policy would deny the NSG.
- Question d: idempotence = proof that the actual state matches the code; the auditor reads the file, not the portal.

---

## Request 4 — Effective flows (M4, M7)

```bash
az vm start -g "rg-${ST}-app" -n "vm-${ST}-web01" -o none
az network nic list-effective-nsg -g "rg-${ST}-app" -n "nic-${ST}-web01" \
  --query "value[].effectiveSecurityRules[?direction=='Inbound'].{Name:name, Access:access, Port:destinationPortRange, Priority:priority}" -o table
```
Expected output (excerpt):
```
Name                                 Access  Port     Priority
-----------------------------------  ------  -------  --------
securityRules/Allow-HTTP-HTTPS-Inbound  Allow   80-80    100
defaultSecurityRules/AllowVnetInBound   Allow   0-65535  65000
defaultSecurityRules/DenyAllInBound     Deny    0-65535  65500
```
Explanation: HTTP traffic from the Load Balancer is allowed by `Allow-HTTP-HTTPS-Inbound` (priority 100); any other flow from the Internet falls on `DenyAllInBound`. Effective rules = subnet NSG + NIC NSG, evaluated in that order inbound.

---

## Request 5 — Sharing evidence (M6)

```bash
SA_ARCH="starveost${NN}arch${SES}"
az role assignment create --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Storage Blob Data Contributor" \
  --scope "$(az storage account show -n "$SA_ARCH" --query id -o tsv)" -o none
sleep 60   # data role propagation
az storage container create --account-name "$SA_ARCH" -n audit --auth-mode login -o none
echo "Preuve d'audit Arvéo $(date -u +%F)" > preuve.txt
az storage blob upload --account-name "$SA_ARCH" -c audit -n preuve.txt -f preuve.txt --auth-mode login -o none
EXP=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%MZ)
SAS=$(az storage container generate-sas --account-name "$SA_ARCH" -n audit --permissions r \
  --expiry "$EXP" --https-only --as-user --auth-mode login -o tsv)
URL="https://${SA_ARCH}.blob.core.windows.net/audit/preuve.txt?${SAS}"
curl -s "$URL"
curl -s -o /dev/null -w "%{http_code}\n" -X PUT -H "x-ms-blob-type: BlockBlob" -d "x" "$URL"
```
Expected output: `Preuve d'audit Arvéo 2026-10-16`, then `403`.

### Why
- User delegation SAS: signed with an Entra ID key, lifetime limited to 7 days, revocable; works even with `allowSharedKeyAccess=false`.
- Question a: `starveost<NN>data<SES>` has public access disabled (challenge 06.4); the account firewall is evaluated BEFORE authorization: no token gets through from the Internet.

---

## Request 6 — On-demand backup (M9)

```bash
VAULT="rsv-${ST}-arveo"
CONT=$(az backup container list -g "rg-${ST}-shared" -v "$VAULT" --backup-management-type AzureIaasVM \
  --query "[?contains(name,'vm-${ST}-web02')].name | [0]" -o tsv)
az backup protection backup-now -g "rg-${ST}-shared" -v "$VAULT" -c "$CONT" \
  -i "vm-${ST}-web02" --backup-management-type AzureIaasVM \
  --retain-until "$(date -u -d '+7 days' +%d-%m-%Y)" --query name -o tsv
az backup job list -g "rg-${ST}-shared" -v "$VAULT" \
  --query "[?properties.entityFriendlyName=='vm-${ST}-web02'] | [0].{Status:properties.status, Operation:properties.operation}" -o table
```
Expected output: a job ID, then `InProgress  Backup`.

### Why
- Question b: the **snapshot** recovery point (local snapshot, "Snapshot" tier) is available within minutes; the **vault** point arrives after the transfer, later. Fastest restore = snapshot.

---

## Request 7 — Monitoring (M10)

```bash
az monitor metrics alert create -g "rg-${ST}-app" -n "ar-${ST}-eval-cpu" \
  --scopes "$(az vm show -g "rg-${ST}-app" -n "vm-${ST}-web02" --query id -o tsv)" \
  --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m --severity 2 \
  --action "$(az monitor action-group show -g "rg-${ST}-shared" -n "ag-${ST}-exploitation" --query id -o tsv)" -o none
```
KQL query (workspace `log-st<NN>-shared`):
```kusto
Heartbeat
| summarize DernierBattement = max(TimeGenerated) by Computer
| order by Computer asc
```
Expected output: two lines, `vm-st07-web01` and `vm-st07-web02`, timestamp less than 5 min old.

Action group `ag-st<NN>-exploitation`: in `rg-st<NN>-shared` (lab 10.2 and module 10 catch-up).

---

## Self-assessment — answers

| Q | Answer | Rationale |
|---|---|---|
| 1 | B | Dynamic membership rule = Entra ID P1 |
| 2 | C | `deny` effect evaluated at creation and update; existing resources are flagged non-compliant |
| 3 | C | Least privilege: minimal scope, assignment to a group |
| 4 | B | Declarative = target state; idempotence checked in request 3 |
| 5 | A | The NSG filters, the UDR routes |
| 6 | B | Non-transitive peering; explicit gateway transit on both sides |
| 7 | C | Private carrier circuit, guaranteed bandwidth |
| 8 | B | Network before authorization |
| 9 | A | Pointers (reparse points), recalled when opened |
| 10 | B | 99.99% with zones versus 99.95% with an availability set |
| 11 | B | Script run by the agent, replayable |
| 12 | B | Swap = warm-up then traffic switch |
| 13 | B | Disk restored alongside, production VM untouched |
| 14 | B | Metric signal + action group |
| 15 | A | Allowing or blocking rule named for a 5-tuple |
