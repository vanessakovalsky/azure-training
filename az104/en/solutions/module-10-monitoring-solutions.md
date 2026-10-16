# Module 10 — Solutions

All commands assume the variable block of the exercises has been run (`NN`, `EMAIL`, `OCT`, `ST`, `RG_*`, `VAULT`, `WS_ID`, `WS`, `DIAG_SA`, functions `vmrun`, `kql`, `alerts`). Outputs are given for trainee `07`; the technical column `TableName` of the `kql` outputs is omitted.

---

## Lab 10.1 ⭐ — Exploring the Arvéo monitoring data

### Solution
The lab steps are complete. Final checks:
```bash
LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
az monitor diagnostic-settings list --resource "$LB_ID" --query "[].name" -o tsv
kql "union withsource=Table AzureMetrics, AzureDiagnostics, AddonAzureBackupJobs
| where TimeGenerated > ago(1h) | summarize Lignes = count() by Table"
```
Expected output (around 13:55; tables empty until the first data is ingested, volumes vary):
```
diag-arveo
Table                 Lignes
--------------------  --------
AzureMetrics          412
AzureDiagnostics      36
AddonAzureBackupJobs  2
```

### Why
- **Preparation at 13:30**: a diagnostic setting only sends the data emitted AFTER its creation. Created at 14:30, the vault and NSG settings would leave lab 10.3 without data; same logic as the 09:00 backup (M9) and the VPN gateways (D2).
- **Vault in resource-specific tables (`Dedicated`)**: Azure Backup recommends this mode; each category has its own typed table (`AddonAzureBackupJobs`, `CoreAzureBackup`…), simpler to query and smaller than the common `AzureDiagnostics` table.
- **NSG and Load Balancer in default mode**: their logs and metrics do not exist as resource-specific tables `[TO VERIFY]`; they land in `AzureDiagnostics` and `AzureMetrics`.
- **`BackendIPAddress` dimension**: `DipAvailability` aggregated over the pool would hide one server out of two being down (50 % average); split by address, it points to the faulty server.
- **Activity log through the CLI**: the export to `AzureActivity` requires a SUBSCRIPTION diagnostic setting, outside the trainee rights (Reader); direct reading (90 days) remains available.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `preparer-supervision.sh`: `log-stNN-shared absent` | Module 3 foundation deleted or not created | `./scripts/catch-up/module-03/deploy.sh <NN>` then rerun |
| `diagnostic-settings create`: `Data sink ... is already used` | Same category already sent to the same workspace (M9 bonus 4 on the vault) | Expected: the script keeps the existing setting; read its name with `diagnostic-settings list` |
| `metrics list`: empty columns for the last time grain | Grain in progress, not aggregated yet | Read the previous grains or use a longer `--offset` |
| Pool health: a single address | One server out of the pool (incomplete M7 catch-up) or VM stopped | `az vm start`; `az network lb address-pool show ... --query "length(backendIPConfigurations)"` |
| Flow log: `InvalidResourceType` or unknown `--vnet` option | CLI version | Up-to-date Cloud Shell; otherwise portal: Network Watcher › Flow logs › Create, type "Virtual network" |
| Flow log: `AuthorizationFailed` on `NetworkWatcherRG` | Network Contributor role missing | Trainer: `provision-stagiaires.sh` (idempotent) |
| `Heartbeat`: AUCUNE | Agent stopped or VM restarted without Internet egress | `az vm extension show ... -n AzureMonitorLinuxAgent`; NAT gateway `ng-stNN-app` on `snet-web` |

---

## Lab 10.2 ⭐⭐ — Arvéo alerts and action group

### Solution
```bash
# 1. Action group (confirmation email sent to the address)
AG_ID=$(az monitor action-group create -g "$RG_SHARED" -n "ag-${ST}-exploitation" \
  --short-name "ag-${ST}-exp" --action email exploitation "$EMAIL" \
  --tags $TAGS --query id -o tsv)
# 2. Sustained CPU, all the VMs of rg-stNN-app (France Central)
az monitor metrics alert create -g "$RG_SHARED" -n "alr-${ST}-cpu-vm" \
  --scopes "$(az group show -n "$RG_APP" --query id -o tsv)" \
  --target-resource-type Microsoft.Compute/virtualMachines --target-resource-region "$LOC" \
  --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m \
  --severity 2 --action "$AG_ID" --description "Arvéo : CPU moyen > 80 % sur 5 min" \
  --tags $TAGS -o none
# 3. Server out of the pool, one series per address
LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
az monitor metrics alert create -g "$RG_SHARED" -n "alr-${ST}-lb-sante" --scopes "$LB_ID" \
  --condition "avg DipAvailability < 100 where BackendIPAddress includes 10.${OCT}.4.11 or 10.${OCT}.4.12" \
  --window-size 5m --evaluation-frequency 1m --severity 1 --action "$AG_ID" \
  --description "Arvéo : serveur du pool bp-web en échec de sonde" --tags $TAGS -o none
# 4. Deletion of an NSG rule (activity log)
az monitor activity-log alert create -g "$RG_SHARED" -n "alr-${ST}-nsg-regle" \
  --scope "$(az group show -n "$RG_SPOKE" --query id -o tsv)" "$(az group show -n "$RG_APP" --query id -o tsv)" \
  --condition category=Administrative and operationName=Microsoft.Network/networkSecurityGroups/securityRules/delete \
  --action-group "$AG_ID" --description "Arvéo : règle de NSG supprimée" --tags $TAGS -o none
# Checks
az monitor metrics alert list -g "$RG_SHARED" -o table \
  --query "[].{Rule:name, Severity:severity, Enabled:enabled, Window:windowSize, Frequency:evaluationFrequency}"
az monitor activity-log alert list -g "$RG_SHARED" -o table --query "[].{Rule:name, Enabled:enabled}"
```
Expected output:
```
Rule               Severity    Enabled    Window    Frequency
-----------------  ----------  ---------  --------  -----------
alr-st07-cpu-vm    2           True       PT5M      PT1M
alr-st07-lb-sante  1           True       PT5M      PT1M
Rule                Enabled
------------------  ---------
alr-st07-nsg-regle  True
```
Steps 5 and 6 (triggering, check every 2 min):
```bash
alerts
```
Expected output around 14:20 (UTC times; targets and severity of the activity log alert `[TO VERIFY]` labels):
```
Rule                Target          Severity    Condition    Start
------------------  --------------  ----------  -----------  ------------------------
alr-st07-cpu-vm     vm-st07-web01   Sev2        Fired        2026-10-08T12:13:41.52Z
alr-st07-lb-sante   lbe-st07-web    Sev1        Fired        2026-10-08T12:10:12.08Z
alr-st07-nsg-regle  nsg-st07-web    Sev4        Fired        2026-10-08T12:09:55.31Z
```
After step 7, 3 to 6 min later: `alr-st07-cpu-vm` and `alr-st07-lb-sante` switch to `Resolved` (resolution email); `alr-st07-nsg-regle` stays `Fired`.

Step 8 answers:
- **a.** The "resource group" scope covers all the present AND future VMs of the group in the region: the `vmss-st<NN>-api` instances (Flexible orchestration: each instance is a VM) added by scaling are monitored without changing the rule. A fixed list of VMs would have to be maintained at each addition. Each VM remains a distinct series: one alert per VM in violation.
- **b.** An activity log alert is STATELESS: it reacts to a one-off event (the deletion happened), there is no condition that becomes false again. Each deletion creates a new alert; only an operator moves it to "Acknowledged" then "Closed".
- **c.** Observed delay of 6 to 9 min, broken down: metric emission by the platform (about 1 min); window filling (the 5-min average exceeds 80 % after about 4 min at 100 %); wait for the next evaluation (up to 1 min); alert creation and email sending (1 to 2 min). The window is the main factor: it is the price of having no false alerts on spikes.

### Why
- **Action group in `rg-st<NN>-shared`**: cross-cutting object, reused by every rule (and by challenge 10.4); an on-call change is made in a single place.
- **Rules in `rg-st<NN>-shared`, scoped elsewhere**: an alert rule can live in a different group than its target; monitoring stays grouped and survives the rebuild of `rg-st<NN>-app`.
- **Severity 1 for pool health, 2 for CPU**: a server out of the pool halves the portal capacity (degraded HA); a CPU saturation can be transient (API scaling).
- **`systemd-run`**: the load survives the end of the managed run command, which terminates processes started in the classic background `[TO VERIFY]`; `--collect` cleans up the unit when it stops.
- **Two B2s_v2 VMs at 100 %**: B-series CPU credits consumed over 10 to 15 min; without credits, the VM would be throttled to its baseline performance and the 80 % threshold might not be reached (`CPU Credits Remaining` metric).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| No confirmation email | Junk mail, mistyped address | Check `emailReceivers[0].emailAddress`; junk folder; sender `azure-noreply@microsoft.com` `[TO VERIFY]` |
| `metrics alert create`: `--target-resource-region` required | Resource group scope without type or region | Add `--target-resource-type` AND `--target-resource-region` |
| `metrics alert create`: dimension rejected | Syntax of `where ... includes` | Values separated by `or`; or portal ("Split by dimensions") |
| `activity-log alert create`: unknown `--action-group` | Older CLI version | `--action-group` replaced by `az monitor activity-log alert action-group add` `[TO VERIFY]`; or portal |
| CPU alert never fired | CPU credits exhausted (throttled B VM), or load stopped (run command session ended) | `vmrun web01 "systemctl status arveo-charge --no-pager \| head -n 3"`; `CPU Credits Remaining` metric |
| Health alert fired for BOTH addresses | nginx stopped on both VMs, or rule on the pool without dimension | Check `curl` on the public IP; restart nginx |
| `RequestDisallowedByPolicy` (location `global`) | M2 "allowed locations" policy without excluding `global` | Trainer: check the definition (the built-in policy excludes `global`); exemption on `rg-stNN-shared` |
| `alerts`: `az graph` unknown | `resource-graph` extension not installed | `az extension add -n resource-graph` (or dynamic install enabled in the variable block) |

### Acceptable variants
- Portal: **Monitor** › **Alerts** › **Create** › **Alert rule**, "resource group" scope, resource type "Virtual machines"; AZ-104 exam path.
- Bicep: `scripts/catch-up/module-10/main.bicep` (same result, versioned; `BackendIPAddress` dimension with value `*` to include any future server of the pool).
- "Azure Resource Manager role" recipient (subscription Owners) instead of an address: no address to maintain, but broader recipients.
- 10-min window for CPU: less noise, later detection.

---

## Lab 10.3 ⭐⭐ — Querying `log-st<NN>-shared` in KQL

### Solution
Q1 (provided query):
```bash
kql "$(sed -n '/^\/\/ Q1/,/^\/\/ Q2/p' scripts/labs/module-10/requetes-arveo.kql)"
```
Expected output (API instances missing: agent installed on the web servers only):
```
Computer       Dernier                       Minutes    Etat
-------------  ----------------------------  ---------  ------
vm-st07-web01  2026-10-08T12:34:11.0000000Z  0          OK
vm-st07-web02  2026-10-08T12:34:09.0000000Z  0          OK
```
Q2 — CPU per minute:
```kql
Perf
| where TimeGenerated > ago(1h)
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| where InstanceName in ("_Total", "total")
| summarize CpuMoyen = round(avg(CounterValue), 1), CpuMax = round(max(CounterValue), 1)
    by Computer, bin(TimeGenerated, 1m)
| order by TimeGenerated desc
| render timechart
```
Expected output (excerpt, during the lab 10.2 load; `render` ignored by the CLI):
```
Computer       TimeGenerated                 CpuMoyen    CpuMax
-------------  ----------------------------  ----------  --------
vm-st07-web01  2026-10-08T12:15:00.0000000Z  99.6        99.8
vm-st07-web02  2026-10-08T12:15:00.0000000Z  1.2         1.9
```
Q3 — Syslog:
```kql
Syslog
| where TimeGenerated > ago(4h)
| summarize Evenements = count() by Facility, SeverityLevel
| order by Evenements desc
```
Expected output (volumes vary; no level below `warning`, filtered by the DCR):
```
Facility    SeverityLevel    Evenements
----------  ---------------  ------------
daemon      warning          41
auth        warning          3
authpriv    warning          11
```
Q4 — Backup jobs:
```kql
AddonAzureBackupJobs
| where TimeGenerated > ago(4h)
| join kind=leftouter (
    CoreAzureBackup
    | where OperationName == "BackupItem"
    | distinct BackupItemUniqueId, BackupItemFriendlyName
  ) on BackupItemUniqueId
| project Heure = JobStartDateTime, Element = BackupItemFriendlyName, Operation = JobOperation,
    Etat = JobStatus, DureeSec = JobDurationInSecs
| order by Heure desc
```
Expected output (rows and reporting delay `[TO VERIFY]`; `Element` empty until `CoreAzureBackup` has emitted the item):
```
Heure                         Element       Operation    Etat       DureeSec
----------------------------  ------------  -----------  ---------  ----------
2026-10-08T11:31:40.0000000Z  partage-lyon  Backup       Completed  64
```
Q5 — Pool health:
```kql
AzureMetrics
| where MetricName == "DipAvailability" and Resource =~ "lbe-st07-web"
| summarize Sante = round(avg(Average), 1) by bin(TimeGenerated, 5m)
| order by TimeGenerated asc
```
Expected output (excerpt around the nginx stop on `web02`):
```
TimeGenerated                 Sante
----------------------------  -------
2026-10-08T12:05:00.0000000Z  100.0
2026-10-08T12:10:00.0000000Z  62.5
2026-10-08T12:15:00.0000000Z  50.0
```
Q6 — Volume per table, then saving:
```bash
Q6='Usage
| where TimeGenerated > ago(24h) and IsBillable == true
| summarize Mo = round(sum(Quantity), 2) by DataType
| order by Mo desc'
kql "$Q6"
az monitor log-analytics workspace saved-search create -g "$RG_SHARED" \
  --workspace-name "log-${ST}-shared" -n arveo-volume-tables --category Arveo \
  --display-name "Volume ingéré par table" --saved-query "$Q6" -o none
```
Expected output (volumes vary):
```
DataType              Mo
--------------------  ------
Perf                  4.12
AzureMetrics          1.37
Syslog                0.41
Heartbeat             0.19
AzureDiagnostics      0.08
AddonAzureBackupJobs  0.01
```

Step 5 answers:
- **a.** Usually `Perf`: 3 counters sampled every minute, per instance (each core, each disk) and per VM. Monthly estimate = sum of Q6 × 30, to be corrected since the VMs only ran for part of the day (here a few tens of MB per month, so a low cost). In production: watch Q6 every week and reduce the sampling frequency or the counters before touching retention.
- **b.** `AzureActivity` is only fed by a SUBSCRIPTION diagnostic setting (activity log export). Trainees are only Readers of the subscription: no export configured. The activity log still exists (90 days, portal and `az monitor activity-log list`).
- **c.** Gap of a few minutes and value 50 instead of 0: `AzureMetrics` receives one-minute aggregates WITHOUT dimension (average of both servers: one out of two failing = 50 %), grouped here in 5-min bins, with an ingestion delay; the alert evaluates the platform metric per address (`BackendIPAddress`), over a 5-min sliding window, every minute.

### Why
- **`where` on `TimeGenerated` first**: reduces the data read; a query without a time filter scans the whole retention (30 days).
- **`join kind=leftouter`**: keeps a job even if the item has no row yet in `CoreAzureBackup` (less frequent emission `[TO VERIFY]`).
- **`=~` on `Resource`**: `AzureMetrics` stores the resource name in uppercase (`LBE-ST07-WEB`).
- **Saved query**: shared by every user of the workspace, versionable through ARM; a query in a local file is not.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `Failed to resolve table or column expression named 'AddonAzureBackupJobs'` | Table not created yet (no data received) | Wait; check the vault setting (lab 10.1 step 5); M9 jobs prior to 13:30 are not reported |
| Q2 empty | Different instance label | `Perf \| where ObjectName == "Processor" \| distinct InstanceName` |
| Q5 empty | Load Balancer `diag-arveo` setting created after the nginx stop | Expected: no history; stop nginx on `web02` again for 5 min |
| `kql`: `BadArgumentError` | Query quotes badly escaped in Bash | Query between single quotes in a variable (`Q6='...'`), or `.kql` file read through `$(cat ...)` |
| `saved-search create`: empty `--saved-query` | Variable not defined in the new Cloud Shell session | Define `Q6` again |

### Acceptable variants
- Q2 with `make-series` instead of `summarize ... bin()`: complete series (missing values set to 0), suited to charts.
- Q4 from the portal: vault › **Backup Reports** (workbook based on the same tables) `[TO VERIFY]` refresh delay.
- Q6 with `_BilledSize` on each table (`union withsource=Table * | summarize sum(_BilledSize) by Table`): more accurate, much more expensive to run.

---

## Challenge 10.4 ⭐⭐⭐ — Detecting SSH brute-force attacks

### Solution
Query and function (CLI):
```bash
SSH_KQL='Syslog
| where Facility in ("auth", "authpriv") and SyslogMessage has "Failed password"
| parse SyslogMessage with * "from " IpSource " port " *
| project TimeGenerated, Computer, IpSource, SyslogMessage'
az monitor log-analytics workspace saved-search create -g "$RG_SHARED" \
  --workspace-name "log-${ST}-shared" -n arveo-echecs-ssh --category Arveo \
  --display-name "Échecs SSH Arvéo" --saved-query "$SSH_KQL" --func-alias ArveoEchecsSsh -o none
```
Alert rule (versioned Bicep, `scripts/catch-up/module-10/alerte-ssh.bicep`: function AND rule):
```bash
AG_ID=$(az monitor action-group show -g "$RG_SHARED" -n "ag-${ST}-exploitation" --query id -o tsv)
az deployment group what-if -g "$RG_SHARED" \
  --template-file scripts/catch-up/module-10/alerte-ssh.bicep \
  --parameters numero="$NN" actionGroupId="$AG_ID"
az deployment group create -g "$RG_SHARED" -n defi-m10 \
  --template-file scripts/catch-up/module-10/alerte-ssh.bicep \
  --parameters numero="$NN" actionGroupId="$AG_ID" --query "properties.outputs" -o json
```
Expected output:
```
{
  "functionAlias": { "type": "String", "value": "ArveoEchecsSsh" },
  "ruleName": { "type": "String", "value": "alr-st07-ssh-echecs" }
}
```
File excerpt (rule criteria):
```bicep
criteria: {
  allOf: [
    {
      query: requete
      timeAggregation: 'Count'
      dimensions: [
        { name: 'Computer', operator: 'Include', values: [ '*' ] }
        { name: 'IpSource', operator: 'Include', values: [ '*' ] }
      ]
      operator: 'GreaterThanOrEqual'
      threshold: seuil
      failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
    }
  ]
}
```
Evidence (step 3):
```bash
./scripts/labs/module-10/simuler-echecs-ssh.sh "$NN"
sleep 300
kql "ArveoEchecsSsh | summarize Echecs = count() by Computer, IpSource"
alerts
```
Expected output (5 to 12 min after the simulation for the alert):
```
Computer       IpSource      Echecs
-------------  ------------  --------
vm-st07-web01  203.0.113.50  8
vm-st07-web01  198.51.100.7  3
Rule                 Target           Severity    Condition    Start
-------------------  ---------------  ----------  -----------  ------------------------
alr-st07-ssh-echecs  log-st07-shared  Sev1        Fired        2026-10-08T12:52:03.11Z
```
Portal: alert › **Details**: dimensions `Computer = vm-st07-web01`, `IpSource = 203.0.113.50`, value `8`. No alert for `198.51.100.7` (3 < 5). If both simulations are run in the same 10-min window, `198.51.100.7` still does not fire: dimensions keep the counters separate.

Step 4 answers:
- **a.** Measured delay of 5 to 12 min: local write and sending by the agent (seconds), ingestion into the workspace (1 to 5 min), wait for the next evaluation (0 to 5 min), alert creation and email (1 to 2 min). Reduction: 1-min evaluation frequency (higher rule cost `[TO VERIFY]` pricing); ingestion cannot be compressed. For a reaction in seconds: Microsoft Defender for Servers or Microsoft Sentinel (analytics rules, automated response), outside the AZ-104 scope.
- **b.** No: `dcr-st<NN>-linux` only collects `authpriv` from `Warning` upwards; real `sshd` failures (`info` level) are NOT collected, so the rule would never see a real attack. Fix: add to `dcr-arveo-linux.bicep` a second Syslog source `authpriv` from `Info` (the other facilities stay at `Warning`), then redeploy; the agents pick up the configuration without reinstallation. Impact: every logged connection and every `sudo` becomes billable; contain the volume with a DCR transformation (`transformKql` keeping only `Failed password` and `Accepted`) and track it with query Q6.
- **c.** A metric alert evaluates numeric series emitted by the platform (CPU, bytes, probes); no metric counts SSH failures, let alone per source address. The information only exists in the text of the guest OS logs: only a KQL query can extract it (`parse`) and group it.

### Why
- **10-min window, 5-min frequency**: each minute is examined twice (overlapping windows), so a burst straddling two evaluations is detected.
- **`Computer` and `IpSource` dimensions**: one alert per pair; the security team immediately knows which server and which address to block. Without dimensions, 8 + 3 failures = 11 would fire a single alert with no attribution.
- **`autoMitigate`**: the alert resolves when the window no longer contains 5 failures; a new burst creates a new alert.
- **Full query in the rule, separate function**: the rule does not depend on an object other teams can change; the function is used for investigations.
- **RFC 5737 addresses**: reserved for documentation, no risk of blaming a real address.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `kql "ArveoEchecsSsh"`: unknown function | Missing alias (`--func-alias`) or publication delay | `saved-search show ... --query functionAlias`; wait 1 to 2 min |
| No `Failed password` row | Simulation not run, or DCR changed (level) | Rerun the simulation; `kql "Syslog \| where ProcessName == 'sshd' \| take 5"` |
| Empty `IpSource` | `parse` pattern different from the message (spaces) | Test `parse` on `take 5`; pattern `"from " IpSource " port "` |
| Deployment: `ScheduledQueryRules ... query is invalid` | Query not returning the dimension columns | `project` must contain `Computer` and `IpSource` |
| A single alert, without dimension | Dimensions omitted | Add both dimensions with value `*` |
| Alert never resolved | `autoMitigate` disabled | Property `autoMitigate: true` |

### Acceptable variants
- CLI: `az monitor scheduled-query create --scopes <WORKSPACE_ID> --condition "count 'Echecs' >= 5 where Computer includes * and IpSource includes * at least 1 violations out of 1 aggregated points" --condition-query Echecs="<KQL>" --evaluation-frequency 5m --window-size 10m --severity 1 --action-groups <ACTION_GROUP_ID>` `[TO VERIFY]` `--condition` grammar for dimensions.
- Measure through `summarize count() by Computer, IpSource` in the query, then threshold on the column (`Total` aggregation): equivalent, more explicit.
- Threshold of 10 failures in 15 min: fewer false positives (user mistyping a password), later detection.

---

## Lab 10.5 ⭐⭐ — Diagnosing the Arvéo flows with Network Watcher

### Solution
```bash
# 1. Instance and flow log
az network watcher list -o table \
  --query "[?location=='francecentral'].{Name:name, Group:resourceGroup, Status:provisioningState}"
FA="flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration"
az network watcher flow-log show --location "$LOC" --name "fl-${ST}-spoke-app" -o json \
  --query "{Target:targetResourceId, Storage:storageId, Enabled:enabled, TA:${FA}.enabled, Interval:${FA}.trafficAnalyticsInterval}" \
  | sed 's#/subscriptions/[^"]*/##'
```
Expected output:
```
Name                          Group             Status
----------------------------  ----------------  ---------
NetworkWatcher_francecentral  NetworkWatcherRG  Succeeded
{
  "Enabled": true,
  "Interval": 10,
  "Storage": "starveost07diag",
  "TA": true,
  "Target": "vnet-st07-spoke-app"
}
```
Step 2: commands of the exercise statement (provided).
```bash
# 3. Connection troubleshoot (30 to 60 s each)
az network watcher test-connectivity -g "$RG_APP" --source-resource "vm-${ST}-web01" \
  --dest-address "10.${OCT}.5.100" --dest-port 8080 --protocol Tcp \
  --query "{Status:connectionStatus, Sent:probesSent, Failed:probesFailed}" -o table
az network watcher test-connectivity -g "$RG_APP" --source-resource "vm-${ST}-web01" \
  --dest-address sql.arveo.internal --dest-port 1433 --protocol Tcp -o json \
  --query "{Status:connectionStatus, Sent:probesSent, Failed:probesFailed, Issues:hops[].issues[].type}"
```
Expected output (number of probes varies; issue type `[TO VERIFY]` label):
```
Status     Sent    Failed
---------  ------  --------
Reachable  66      0
{
  "Failed": 30,
  "Issues": [ "UserDefinedRoute" ],
  "Sent": 30,
  "Status": "Unreachable"
}
```
The name `sql.arveo.internal` is resolved (private zone linked to the app spoke, module 4): DNS is not the cause.
```bash
# 4. Next hop
for DEST in "10.${OCT}.8.10" "10.${OCT}.5.100"; do
  az network watcher show-next-hop -g "$RG_APP" --vm "vm-${ST}-web01" \
    --source-ip "10.${OCT}.4.11" --dest-ip "$DEST" \
    --query "{Destination:'${DEST}', Hop:nextHopType, Route:routeTableId}" -o table
done
```
Expected output:
```
Destination    Hop    Route
-------------  -----  ------------
10.7.8.10      None   System Route
Destination    Hop        Route
-------------  ---------  ------------
10.7.5.100     VnetLocal  System Route
```
```bash
# 5. IP flow verify (inbound direction)
ipflow() {   # ipflow <VM> <LOCAL_IP:PORT> <REMOTE_IP:PORT>
  az network watcher test-ip-flow -g "$RG_APP" --vm "$1" --direction Inbound --protocol TCP \
    --local "$2" --remote "$3" --query "[access, ruleName]" -o tsv | paste - -
}
ipflow "vm-${ST}-web01" "10.${OCT}.4.11:80" 198.51.100.10:50000
ipflow "vm-${ST}-web01" "10.${OCT}.4.11:22" 198.51.100.10:50000
ipflow "$API_VM" "${API_IP}:8080" "10.${OCT}.4.11:50000"
ipflow "$API_VM" "${API_IP}:8080" "10.${OCT}.8.10:50000"
```
Expected output (rule name prefix `[TO VERIFY]` depending on the API version):
```
Allow	securityRules/Allow-HTTP-HTTPS-Inbound
Deny	defaultSecurityRules/DenyAllInBound
Allow	securityRules/Allow-API-From-Web
Deny	defaultSecurityRules/DenyAllInBound
```
```bash
# 6. Traffic analytics (after 15:30)
kql "NTANetAnalytics
| where TimeGenerated > ago(2h) and SubType == 'FlowLog'
| summarize Lignes = count() by FlowType, FlowStatus, DestIp, DestPort
| top 10 by Lignes"
kql "NTANetAnalytics
| where TimeGenerated > ago(2h) and SubType == 'FlowLog' and FlowStatus == 'Denied'
| project TimeGenerated, SrcIp, DestIp, DestPort, NsgRule"
```
Expected output (excerpt; types, labels and volumes `[TO VERIFY]` depending on processing):
```
FlowType     FlowStatus    DestIp      DestPort    Lignes
-----------  ------------  ----------  ----------  --------
AzurePublic  Allowed       10.7.4.11   80          14
AzurePublic  Allowed       10.7.4.12   80          13
IntraVNet    Allowed       10.7.5.4    8080        9
IntraVNet    Denied        10.7.5.4    22          1
TimeGenerated                 SrcIp      DestIp    DestPort    NsgRule
----------------------------  ---------  --------  ----------  ------------------------------
2026-10-08T13:20:00.0000000Z  10.7.4.11  10.7.5.4  22          nsg-st07-app/Deny-VNet-Inbound
```
- Portal clients as `AzurePublic`: the requests come from Cloud Shell, hosted in Azure (an Internet client would be `ExternalPublic`).
- SQL attempt to `10.<OCT>.8.10` missing or without an NSG decision: the packet is dropped for lack of a route, before any filtering `[TO VERIFY]` behavior of virtual network flow logs.

Step 7 answers:
- **a.** Cause: the end-of-D2 cleanup (`module-04-firewall.sh`) deleted the firewall and dissociated the route tables; the app and data spokes are only peered with the hub, and peering is NOT transitive. The app spoke has no route to `10.<OCT>.8.0/22`: the system route `10.0.0.0/8` → `None` drops the packet. Fixes: (1) recreate the firewall and the UDRs (`./scripts/catch-up/module-04/deploy.sh <NN>`): target architecture, centralized filtering, hourly cost of the firewall; (2) direct peering app spoke ↔ data spoke: no hourly charge (traffic billed per GB), but bypasses central control. Changing `nsg-st<NN>-data` is useless: the packet never leaves the app spoke, and that NSG already allows TCP 1433 from `snet-web` (`Allow-SQL-From-Web`).
- **b.** `Deny-VNet-Inbound` has as its source the `VirtualNetwork` tag of the app spoke: its address space, the peered VNets (hub) and the networks learned through a gateway. The data spoke is not peered with the app spoke: `10.<OCT>.8.10` does not belong to the tag. No explicit rule applies, nor does `AllowVnetInBound`: the default rule `DenyAllInBound` decides. Same mechanism as cases b and c of exercise 04.2.
- **c.** A flow log has no history, and traffic analytics adds 10 to 30 min of processing. Enabled when the ticket is opened, it would show neither the start of the incident nor the "normal" reference state. On a critical network, it is enabled permanently: its cost (per GB) is that of an insurance policy.

### Why
- **Order route → filtering → connection**: a `None` hop makes any NSG analysis pointless; connection troubleshoot then confirms the end-to-end diagnosis, with real packets.
- **`NetworkWatcherAgentLinux` extension**: connection troubleshoot sends probes from the VM; IP flow verify and next hop only read the configuration (no extension).
- **Flow log on the whole VNet**: covers `snet-web` and `snet-app`, present and future VMs (API instances), without depending on an NSG; NSG flow logs can no longer be created (retirement on September 30, 2027).
- **`starveost<NN>diag` storage**: same region as the VNet (flow log requirement), Standard account already present (module 3), 7-day retention sufficient for the course.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `test-connectivity`: extension required | `NetworkWatcherAgentLinux` missing (preparation not run) | `az vm extension set --publisher Microsoft.Azure.NetworkWatcher --name NetworkWatcherAgentLinux` |
| `test-connectivity`: `AuthorizationFailed` | Rights on `NetworkWatcherRG` | Trainer: Network Contributor role (provisioning) |
| Connection to the API `Unreachable` | API instances still deallocated or starting | `az vm list -g rg-stNN-app -d -o table`; wait for `VM running` and the Load Balancer probe |
| `test-ip-flow` on the instance: VM not found | Instance name copied incorrectly | `echo "$API_VM"`; define the step 2 variables again |
| `NTANetAnalytics` unknown or empty | Less than 20 to 30 min since creation, or traffic generated too late | Rerun step 2 and wait; check the blobs: `az storage blob list --account-name <ACCOUNT> -c insights-logs-flowlogflowevent --auth-mode login --num-results 3 -o table` |
| No `Denied` flow | Step 2 not run (SSH attempt) | Rerun step 2; wait for the next processing |

### Acceptable variants
- Portal: **Network Watcher** › **Next hop**, **IP flow verify**, **Connection troubleshoot** (same results, AZ-104 exam path).
- **NSG diagnostics** (`az network watcher run-configuration-diagnostic`) instead of IP flow verify: evaluates every NSG on the path (subnet and NIC) and returns the evaluation order `[TO VERIFY]` parameters.
- Step 6: **Traffic analytics** in the portal (maps, denied flows per subnet), fed by the same table.

---

## Bonus

1. **Maintenance window** `[TO VERIFY]` CLI scheduling options:
   ```bash
   az monitor alert-processing-rule create -g "$RG_SHARED" -n "apr-${ST}-maintenance" \
     --scopes "$(az group show -n "$RG_APP" --query id -o tsv)" \
     --rule-type RemoveAllActionGroups --description "Correctifs du mardi soir" \
     --schedule-recurrence-type Weekly --schedule-recurrence Tuesday \
     --schedule-start-time 22:00:00 --schedule-end-time 23:00:00 \
     --schedule-time-zone "Romance Standard Time" --tags $TAGS -o none
   ```
   Alerts fired during the window appear in **Alerts**; no email is sent. Windows time zone `Romance Standard Time` = Paris (daylight saving time included).
2. **Connection monitor** `[TO VERIFY]` options:
   ```bash
   az network watcher connection-monitor create --location "$LOC" --name "cm-${ST}-api" \
     --endpoint-source-name web01 \
     --endpoint-source-resource-id "$(az vm show -g "$RG_APP" -n "vm-${ST}-web01" --query id -o tsv)" \
     --endpoint-dest-name api --endpoint-dest-address "10.${OCT}.5.100" \
     --test-config-name tcp8080 --protocol Tcp --tcp-port 8080 --frequency 30 \
     --workspace-ids "$WS_ID" -o none
   ```
   Query: `NWConnectionMonitorTestResult | summarize avg(AvgRoundTripTimeMs), max(ChecksFailedPercent) by bin(TimeGenerated, 5m)` `[TO VERIFY]` columns. Deallocating one instance does not make the test fail (Load Balancer): only losing both instances would.
3. **Packet capture**:
   ```bash
   az network watcher packet-capture create -g "$RG_APP" --vm "vm-${ST}-web02" -n "pc-${ST}-web02" \
     --storage-account "$DIAG_SA" --time-limit 60 \
     --filters '[{"protocol":"TCP","localPort":"80"}]' -o none
   ```
   The `.cap` file is written to the `network-watcher-logs` container of the account. Load Balancer probes arrive from `168.63.129.16` roughly every 5 s; client requests keep the client source address (no inbound SNAT on a public Load Balancer).
4. **Workbook**: **Monitor** › **Workbooks** › **New**; add a "Time range" parameter, three query items (Q1 as a grid, Q2 as a line chart, Resource Graph query `alertsmanagementresources | where name startswith 'alr-st<NN>-'` as a grid), save in `rg-st<NN>-shared`; **Edit** › **</>** (Advanced Editor) › **ARM Template** for the IaC version.
5. **Dynamic threshold** `[TO VERIFY]` grammar:
   ```bash
   az monitor metrics alert create -g "$RG_SHARED" -n "alr-${ST}-cpu-dyn" \
     --scopes "$(az vm show -g "$RG_APP" -n "vm-${ST}-web01" --query id -o tsv)" \
     --condition "avg Percentage CPU > dynamic medium 2 of 4" \
     --window-size 5m --evaluation-frequency 5m --severity 3 --tags $TAGS -o none
   ```
   With only a few hours of history, the computed band is narrow and unreliable; a dynamic threshold becomes relevant after several days (daily and weekly seasonality).

---

## QCM — Answers
1. **B** — Platform metrics are collected by default; the guest OS requires the Azure Monitor Agent and a DCR.
2. **B** — A diagnostic setting only sends the data emitted after its creation: no retroactive history.
3. **B** — The activity log is kept 90 days; beyond that, export through a subscription diagnostic setting.
4. **C** — The 5-min average (about 22 %) stays below 80 %: the window filters out spikes.
5. **B** — The action group gathers notifications and actions, reusable by every rule.
6. **C** — A scheduled alert processing rule suppresses notifications without preventing the creation of alerts.
7. **C** — `summarize ... by` aggregates (for example `count()`) grouping by one or more columns.
8. **B** — The `Heartbeat` table receives one heartbeat per minute from each agent.
9. **B** — `None`: no route leads to the destination, the packet is dropped before any NSG.
10. **B** — NSG flow logs are being retired (September 30, 2027) and can no longer be created.
