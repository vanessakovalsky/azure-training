# Module 12 — Synthesis case: Arvéo end-of-migration audit

Common thread: **end of the Arvéo migration**. The audit firm hired by the IT department arrives on Monday. Seven requests to handle in the `st<NN>` environment, with one proof each.

Use: self-paced revision case, after the training. Full solution in `solutions/module-12-synthesis-solutions.md`. Each request uses one or more modules; the "Modules" column shows where to read again.

**Indicative duration** : 45 min · **Prerequisites** : end-of-training state (modules 6, 7, 9 and 10), or the matching catch-ups · **Level** : ⭐⭐

**Variable block** :
```bash
NN=<NN>
ST="st${NN}"
SES=<SES>
SUB_ID=$(az account show --query id -o tsv)
```
`<NN>` = two-digit trainee number · `<SES>` = module 6 session code (storage account suffix)

---

## The seven requests

| # | Request | Modules | Expected proof |
|---|---|---|---|
| 1 | Assigned security group `st<NN>-GRP-Audit`, created in administrative unit `AU-st<NN>`; **Reader** role on `rg-st<NN>-data` only, assigned to the group | M1, M2 | `az role assignment list -g rg-st<NN>-data`: the group, role `Reader`; no other assignment for this group |
| 2 | Tag `Audit=2026` added to `rg-st<NN>-app` WITHOUT overwriting existing tags; attempt to create an NSG `nsg-st<NN>-eval` in **West Europe** in `rg-st<NN>-app` | M2 | Existing tags kept; `RequestDisallowedByPolicy` message noted |
| 3 | File `eval.bicep`: NSG `nsg-st<NN>-eval` in France Central in `rg-st<NN>-app`, inbound rule `Deny-SSH-Internet` (TCP 22, source `Internet`, priority 100, deny); deployment, then a second identical deployment | M3, M4 | Second deployment `Succeeded` with no change (`what-if`: `NoChange`) |
| 4 | Effective rules of the network interface of `vm-st<NN>-web01` | M4, M7 | Name of the rule allowing HTTP, name of the default rule denying the rest; one sentence of explanation |
| 5 | Container `audit` in `starveost<NN>arch<SES>`, file `preuve.txt`, read-only **user delegation SAS**, valid 1 h, HTTPS only | M6 | `curl` with the SAS: file content; write with the same SAS: denied (`403`) |
| 6 | Immediate backup of `vm-st<NN>-web02` in `rsv-st<NN>-arveo`, 7-day retention | M9 | Job ID; status `InProgress` or `Completed` |
| 7 | Metric alert rule `ar-st<NN>-eval-cpu`: CPU of `vm-st<NN>-web02` > 80% over 5 min, action group `ag-st<NN>-exploitation`; KQL query: last `Heartbeat` per computer | M10 | Rule visible; query and result (one line per web VM) |

## Written questions
1-2 sentences each:
- a. Request 5: why does `starveost<NN>data<SES>` return `403` from Cloud Shell, even with a valid SAS?
- b. Request 6: which recovery point is available first, and why?
- c. Request 1: why assign the role to the group rather than to the user?
- d. Request 3: what does the second identical deployment bring to an audit?

## Hints
- Request 1: creation in the AU with `az rest` on `https://graph.microsoft.com/v1.0/directory/administrativeUnits/<AU_ID>/members` (same principle as in module 1).
- Request 2: `az tag update --operation Merge`.
- Request 4: `az network nic list-effective-nsg` (VM running).
- Request 5: `az storage container generate-sas --as-user --auth-mode login`; a data role on the account is required.
- Request 6: `az backup protection backup-now --retain-until`.
- Request 7: `az monitor metrics alert create --condition "avg Percentage CPU > 80"`.

## Self-assessment
15 questions, a single correct answer, answers in the solutions. Benchmark: 10/15.

1. Group whose members are added automatically based on the user's department: which type, and which licence?
   - A. Assigned group, no licence
   - B. Dynamic user group, Entra ID P1 at least
   - C. Microsoft 365 group, Exchange licence
   - D. Administrative unit, Entra ID P2
2. An "Allowed locations" assignment exists on a resource group. Effect on an existing resource outside the region?
   - A. Deleted automatically
   - B. Moved to an allowed region
   - C. Kept, flagged non-compliant; only new creations are denied
   - D. Locked read-only
3. An auditor must read the resources of a single resource group. Correct assignment?
   - A. `Reader` on the subscription
   - B. `Contributor` on the resource group
   - C. `Reader` on the resource group, assigned to an Entra ID group
   - D. Entra ID Global Reader
4. Main advantage of a Bicep file over a series of CLI commands?
   - A. Faster execution
   - B. Declarative and idempotent: a second deployment recreates nothing
   - C. No RBAC permission needed
   - D. Free resources
5. Traffic from a spoke to the Internet forced through Azure Firewall: which object?
   - A. Route table (UDR) `0.0.0.0/0` → firewall private IP, associated with the subnet
   - B. Outbound NSG rule to the firewall
   - C. Peering with "Use remote gateways"
   - D. Private DNS zone
6. Hub ↔ spoke peering; the spoke must reach Lyon through the hub VPN gateway. Settings?
   - A. None: peering is transitive
   - B. "Allow gateway transit" on the hub side, "Use remote gateways" on the spoke side
   - C. One VPN gateway per spoke
   - D. A second spoke ↔ Lyon peering
7. Guaranteed private link, 10 Gbps, no Internet transit, to the datacenter: which service?
   - A. Site-to-site VPN
   - B. Point-to-site VPN
   - C. ExpressRoute
   - D. Global peering
8. Storage account with private endpoint and public access disabled: request from the Internet with a valid SAS?
   - A. Accepted: SAS takes precedence over network
   - B. Denied (`403`): the account firewall applies before authorization
   - C. Redirected to the private endpoint
   - D. Accepted read-only
9. Azure File Sync, cloud tiering enabled: effect on the Lyon server?
   - A. Rarely used files replaced by pointers, content recalled on demand
   - B. Files deleted from the server after sync
   - C. Read-only share
   - D. None: tiering only concerns the Archive account
10. Highest SLA for two identical web VMs?
   - A. Two VMs in the same availability set
   - B. Two VMs in two availability zones, behind a Standard Load Balancer
   - C. One VM with a Premium SSD disk
   - D. Two VMs in the same zone
11. Configuring an existing VM without interactive login, replayable: which tool?
   - A. Bastion
   - B. Custom Script extension
   - C. Image capture
   - D. Availability set
12. Zero-downtime release of a new version on App Service?
   - A. Restart the app
   - B. Deploy to a `staging` slot, then swap
   - C. Scale up the plan
   - D. Delete and recreate the app
13. Restoring a specific file of `web01` without touching the production VM?
   - A. Replace existing
   - B. Restore disks, attach the disk to a work VM, copy the file
   - C. Site Recovery, failover
   - D. Snapshot of the production OS disk
14. Alert when a VM's CPU exceeds 80% for 5 min, with an email to operations?
   - A. Diagnostic setting to Log Analytics
   - B. Metric alert rule linked to an action group
   - C. Activity log alert
   - D. Azure Monitor workbook
15. VM unreachable on port 1433: which Network Watcher tool shows the NSG rule involved?
   - A. IP flow verify
   - B. Packet capture
   - C. Topology
   - D. Connection monitor

## Cleanup
```bash
az network nsg delete -g "rg-${ST}-app" -n "nsg-${ST}-eval"
az monitor metrics alert delete -g "rg-${ST}-app" -n "ar-${ST}-eval-cpu"
az group update -n "rg-${ST}-app" --remove tags.Audit -o none
```
