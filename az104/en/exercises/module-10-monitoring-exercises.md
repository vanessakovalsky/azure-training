# Module 10 — Exercises

Common thread: **Arvéo monitoring center**. Since module 7, the foundation workspace `log-stNN-shared` (module 3) receives the heartbeats, performance counters and Syslog of the web servers; it now also receives the logs of the backup vault (module 9) and of the portal NSG, the Load Balancer metrics and the network flows of the application spoke. Three alerts warn the operations team (CPU saturation, server removed from the pool, filtering rule deleted), a fourth one detects SSH brute-force attacks. Finally, Network Watcher is used to diagnose the ticket opened by the ERP team since the firewall was deleted.

| Resource | Name (trainee 07) | Group | Lab |
|---|---|---|---|
| Diagnostic settings | `diag-arveo` on `rsv-st07-arveo` and `nsg-st07-web` (13:30), on `lbe-st07-web` (lab) | shared / spoke / app | 10.1 |
| Action group | `ag-st07-exploitation` (short name `ag-st07-exp`) | `rg-st07-shared` | 10.2 |
| Metric alerts | `alr-st07-cpu-vm`, `alr-st07-lb-sante` | `rg-st07-shared` | 10.2 |
| Activity log alert | `alr-st07-nsg-regle` | `rg-st07-shared` | 10.2 |
| Log search alert, KQL function | `alr-st07-ssh-echecs`, `ArveoEchecsSsh` | `rg-st07-shared` | 10.4 |
| VNet flow log, extension | `fl-st07-spoke-app` (13:30), `NetworkWatcherAgentLinux` on `vm-st07-web01` | `NetworkWatcherRG` / `rg-st07-app` | 10.5 |

Variables used in all labs:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<EMAIL>` = trainee's email address, accessible during the course (alert notifications)
- `<REPO_URL>` = Git repository of the course, provided by the trainer

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`. Tag names and values stay in French: they are shared with the French-speaking groups of the same tenant. Lab scripts (`scripts/labs/module-10/`) are shared with those groups: their comments and messages are in French. KQL column aliases of the shared files (`IpSource`…) are kept in French for the same reason.

**Variable block**: paste it into Cloud Shell (Bash) at the start of EVERY lab (session closed after 20 min of inactivity).
```bash
NN=<NN>
EMAIL=<EMAIL>
OCT=$((10#$NN))
ST="st${NN}"
RG_SHARED="rg-${ST}-shared"
RG_APP="rg-${ST}-app"
RG_SPOKE="rg-${ST}-spoke"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
VAULT="rsv-${ST}-arveo"
WS_ID=$(az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" --query id -o tsv)
WS=$(az monitor log-analytics workspace show --ids "$WS_ID" --query customerId -o tsv)
DIAG_SA=$(az storage account list -g "$RG_SHARED" \
  --query "[?starts_with(name, 'starveost${NN}diag')].name | [0]" -o tsv)   # module 3
az config set extension.use_dynamic_install=yes_without_prompt -o none
cd ~/formation 2>/dev/null || git clone <REPO_URL> ~/formation && cd ~/formation
vmrun() {   # vmrun <web01|web02> "<BASH COMMAND>": run on vm-stNN-<name> (rg-stNN-app)
  az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
kql() {     # kql "<QUERY>": run in log-stNN-shared
  az monitor log-analytics query -w "$WS" --analytics-query "$1" -o table
}
alerts() {  # alerts: alerts fired by rules alr-stNN-* (Azure Resource Graph)
  az graph query --first 50 -o table --query "data" -q "alertsmanagementresources
    | where type =~ 'microsoft.alertsmanagement/alerts' and name startswith 'alr-${ST}-'
    | project Rule=name, Target=tostring(properties.essentials.targetResourceName),
      Severity=tostring(properties.essentials.severity),
      Condition=tostring(properties.essentials.monitorCondition),
      Start=tostring(properties.essentials.startDateTime) | order by Start desc"
}
echo "$ST ${WS_ID##*/} ${#WS} $DIAG_SA $EMAIL"
```
Expected result (trainee 07; diagnostics account name with the possible module 3 suffix):
```
st07 log-st07-shared 36 starveost07diag firstname.lastname@example.com
```
`36`: length of the workspace customer ID (GUID), used by `kql`. The `kql` outputs include a technical `TableName` column, omitted from the expected results.

**Starting state**: end of module 9. `web01` and `web02` running since 09:00 (portal v2 served by `lbe-st<NN>-web`), Azure Monitor Agent and rule `dcr-st<NN>-linux` active since module 7; API instances of `vmss-st<NN>-api` deallocated since the end of D3; vault `rsv-st<NN>-arveo` with its backup jobs; Lyon server deallocated at 12:28 (not used here); module 4 test VMs deallocated, firewall and route tables deleted since the end of D2. Module 10 uses no module 8 resource. Late trainee: `./scripts/catch-up/module-10/deploy.sh <NN> <EMAIL>` (10 to 15 min) produces the END state of module 10.

---

## Lab 10.1 ⭐ — Exploring Arvéo monitoring data (guided)
**Duration** : 12 min in class (+ 3 min at 13:30) · **Objective** : use the metrics, diagnostic settings and activity log of the Arvéo resources (objective 11)
**Context** : before defining alerts, the operations team takes stock of what is already measured. Resource logs have no history, so the 13:30 preparation enables them at the very beginning of the module: by 14:30, the tables will be populated.
**Prerequisites** : variable block run; starting state as described.

### Steps
1. **(13:30, back from the lunch break)** Launch the monitoring preparation (2 to 4 min):
   ```bash
   ./scripts/labs/module-10/preparer-supervision.sh "$NN"
   ```
   Expected result (script messages in French; number of instances and IDs vary):
   ```
   == VMs web
      vm-st07-web01 : VM running
      vm-st07-web02 : VM running
   == API vmss-st07-api
      2 instance(s) : démarrage lancé ; mise à l'échelle as-st07-api réactivée
   == VM de test de la base (vm-st07-test-data)
      démarrage lancé (lab 10.5)
   == Agent Network Watcher sur vm-st07-web01
      NetworkWatcherAgentLinux : Succeeded
   == Paramètres de diagnostic vers log-st07-shared
      rsv-st07-arveo : diag-arveo créé (6 catégories, tables spécifiques à la ressource)
      nsg-st07-web : diag-arveo créé (allLogs)
   == Sauvegarde de partage-lyon (travail pour la table AddonAzureBackupJobs)
      travail lancé : InProgress
   == Journal de flux de VNet fl-st07-spoke-app (Traffic analytics toutes les 10 min)
      créé dans NetworkWatcherRG (stockage starveost07diag)
   == Pulsations des 15 dernières minutes (log-st07-shared)
      vm-st07-web01 vm-st07-web02
   ```

2. **(13:43)** Read the CPU of both web servers over the last half hour:
   ```bash
   for VM in web01 web02; do
     az monitor metrics list --resource "$(az vm show -g "$RG_APP" -n "vm-${ST}-${VM}" --query id -o tsv)" \
       --metric "Percentage CPU" --interval PT5M --aggregation Average Maximum --offset 30m -o table
   done
   ```
   Expected result (values vary, one line per 5-min interval and per VM):
   ```
   Timestamp            Name            Average    Maximum
   -------------------  --------------  ---------  ---------
   2026-10-08 13:15:00  Percentage CPU  2.41       6.8
   2026-10-08 13:20:00  Percentage CPU  1.97       3.12
   ```

3. Read the health of pool `bp-web` per server (metric `DipAvailability`, dimension `BackendIPAddress`):
   ```bash
   LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
   az monitor metrics list --resource "$LB_ID" --metric DipAvailability --interval PT1M \
     --aggregation Average --offset 15m --filter "BackendIPAddress eq '*'" -o table \
     --query "value[0].timeseries[].{IP:metadatavalues[0].value, Health:max(data[?average!=null].average)}"
   ```
   Expected result:
   ```
   IP         Health
   ---------  --------
   10.7.4.11  100.0
   10.7.4.12  100.0
   ```

4. List the diagnostic categories of the Load Balancer, then create diagnostic setting `diag-arveo` (metrics to the workspace):
   ```bash
   az monitor diagnostic-settings categories list --resource "$LB_ID" \
     --query "[].{Category:name, Type:categoryType}" -o table
   az monitor diagnostic-settings create -n diag-arveo --resource "$LB_ID" --workspace "$WS_ID" \
     --metrics '[{"category":"AllMetrics","enabled":true}]' --query name -o tsv
   ```
   Expected result (possible log category `[TO VERIFY]` depending on the region):
   ```
   Category                 Type
   -----------------------  -------
   LoadBalancerHealthEvent  Logs
   AllMetrics               Metrics
   diag-arveo
   ```

5. Check the three Arvéo diagnostic settings (two created at 13:30, one in step 4):
   ```bash
   VAULT_ID=$(az backup vault show -g "$RG_SHARED" -n "$VAULT" --query id -o tsv)
   NSG_ID=$(az network nsg show -g "$RG_SPOKE" -n "nsg-${ST}-web" --query id -o tsv)
   for ID in "$VAULT_ID" "$NSG_ID" "$LB_ID"; do
     az monitor diagnostic-settings list --resource "$ID" -o tsv \
       --query "[].[name, workspaceId, logAnalyticsDestinationType]" | sed "s#/subscriptions/.*/#${ID##*/} -> #"
   done
   ```
   Expected result:
   ```
   diag-arveo	rsv-st07-arveo -> log-st07-shared	Dedicated
   diag-arveo	nsg-st07-web -> log-st07-shared	None
   diag-arveo	lbe-st07-web -> log-st07-shared	None
   ```
   `Dedicated`: resource-specific tables (`AddonAzureBackupJobs`…); `None`: default mode (`AzureDiagnostics`, `AzureMetrics`).

6. Read the day's write operations on `rg-st<NN>-app` in the activity log:
   ```bash
   az monitor activity-log list -g "$RG_APP" --offset 8h -o table \
     --query "[?category.value=='Administrative' && status.value=='Succeeded'] | [:8].{Time:eventTimestamp, Operation:operationName.localizedValue}"
   ```
   Expected result (extract; operations and labels vary):
   ```
   Time                              Operation
   --------------------------------  ----------------------------------------
   2026-10-08T11:33:10.512341+00:00  Create or Update Diagnostic Setting
   2026-10-08T11:31:02.120554+00:00  Start Virtual Machine
   2026-10-08T10:14:48.881920+00:00  Run Command on Virtual Machine
   ```

7. **Portal**: **Monitor** › **Metrics**: plot `Percentage CPU` (average) of `vm-st<NN>-web01` and `vm-st<NN>-web02` over the last hour, on the same chart; then **Monitor** › **Activity log**, resource group filter `rg-st<NN>-app`, 6-hour time span: open an operation and note its caller (`Caller`).

### Success criteria
- [ ] `az monitor diagnostic-settings list --resource <LB_ID> --query "[].name" -o tsv` returns `diag-arveo`.
- [ ] The three resources (vault, web NSG, Load Balancer) have a diagnostic setting to `log-st<NN>-shared`.
- [ ] The pool health shows both addresses `10.<OCT>.4.11` and `10.<OCT>.4.12`.
- [ ] The portal chart shows both VMs; the caller of an activity log operation is noted.

---

## Lab 10.2 ⭐⭐ — Arvéo alerts and action group (semi-autonomous)
**Duration** : 20 min · **Objective** : create metric and activity log alerts linked to an action group, then prove that they fire and resolve (objective 11)
**Context** : Arvéo IT sets three monitoring rules for the portal: be warned of a SUSTAINED CPU saturation on any application VM (future API instances included), know when a web server leaves the Load Balancer pool, and track any deletion of a network filtering rule. Notifications are sent by email to the operations team.
**Prerequisites** : lab 10.1 completed; address `<EMAIL>` accessible.

**Assignment** :
1. Create action group `ag-st<NN>-exploitation` (short name `ag-st<NN>-exp`) in `rg-st<NN>-shared`, with an email notification to `<EMAIL>`. Check that the confirmation email of the addition to the group is received.
2. Create rule `alr-st<NN>-cpu-vm` (severity 2): average CPU > 80 % over 5 min, evaluated every minute, for ALL the VMs of `rg-st<NN>-app` in France Central.
3. Create rule `alr-st<NN>-lb-sante` (severity 1) on `lbe-st<NN>-web`: average `DipAvailability` < 100 over 5 min, evaluated every minute, one time series per pool address (`BackendIPAddress`).
4. Create rule `alr-st<NN>-nsg-regle` (activity log): deletion of an NSG security rule in `rg-st<NN>-spoke` OR `rg-st<NN>-app`.
5. Trigger the three rules (provided):
   ```bash
   vmrun web01 "systemd-run --unit=arveo-charge --collect timeout 900 \
     sh -c 'yes >/dev/null & yes >/dev/null & wait'; echo charge lancée"
   vmrun web02 "systemctl stop nginx; echo nginx arrêté"
   az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-web" -n Test-Alerte \
     --priority 4090 --access Deny --protocol Tcp --destination-port-ranges 9999 -o none
   az network nsg rule delete -g "$RG_SPOKE" --nsg-name "nsg-${ST}-web" -n Test-Alerte
   date +%T
   ```
   Expected result: `charge lancée`, `nginx arrêté`, then the launch time (start of the measurement).
6. Follow the alerts (`alerts` function or portal **Monitor** › **Alerts**) until the three rules have fired; note the time of each email received.
7. End both incidents (provided), then wait for the stateful alerts to resolve:
   ```bash
   vmrun web01 "systemctl stop arveo-charge; echo charge arrêtée"
   vmrun web02 "systemctl start nginx; echo nginx démarré"
   ```
8. Answer in writing:
   - a. Why a "resource group" scope rather than the list of both web VMs for the CPU rule?
   - b. Why does alert `alr-st<NN>-nsg-regle` never reach the "Resolved" state?
   - c. Break down the delay observed between the start of the load and the email of the CPU rule.

**Hints** :
- Action group: `az monitor action-group create --short-name <SHORT_NAME> --action email <RECEIVER_NAME> <ADDRESS> --tags ...`; ID: `--query id -o tsv`.
- CPU rule: `az monitor metrics alert create --scopes <GROUP_ID> --target-resource-type Microsoft.Compute/virtualMachines --target-resource-region francecentral --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m --severity 2 --action <ACTION_GROUP_ID>`.
- Dimension: `--condition "avg DipAvailability < 100 where BackendIPAddress includes 10.<OCT>.4.11 or 10.<OCT>.4.12"`.
- Activity log: `az monitor activity-log alert create --scope <RG_ID_1> <RG_ID_2> --condition category=Administrative and operationName=Microsoft.Network/networkSecurityGroups/securityRules/delete --action-group <ACTION_GROUP_ID>`.
- Indicative delays: CPU 6 to 10 min (5-min window + evaluation), pool health 2 to 6 min, activity log 3 to 10 min `[TO VERIFY]` measured on D-1.
- List of rules: `az monitor metrics alert list -g rg-st<NN>-shared -o table` and `az monitor activity-log alert list -g rg-st<NN>-shared -o table`.

**Success criteria** :
- [ ] `az monitor action-group show -g rg-st<NN>-shared -n ag-st<NN>-exploitation --query "emailReceivers[0].status" -o tsv` returns `Enabled`.
- [ ] The three rules exist and are enabled (`enabled` = `true`).
- [ ] `alerts` shows an `alr-st<NN>-cpu-vm` alert on `vm-st<NN>-web01`, an `alr-st<NN>-lb-sante` one and an `alr-st<NN>-nsg-regle` one.
- [ ] After step 7, the CPU and pool health alerts are `Resolved`.
- [ ] The three step 8 answers are written, backed by the measured delays.

---

## Lab 10.3 ⭐⭐ — Querying `log-st<NN>-shared` with KQL (semi-autonomous)
**Duration** : 20 min · **Objective** : query a Log Analytics workspace with KQL to diagnose the state of VMs, backups and network, and measure its cost (objective 11)
**Context** : Arvéo's operations manager prepares the weekly meeting. Six figures are expected, each one produced by a reusable query kept in the Git repository.
**Prerequisites** : lab 10.2 step 5 launched (CPU load on `web01`); 13:30 diagnostic settings active for at least 45 min.

**Assignment** :
1. Open `scripts/labs/module-10/requetes-arveo.kql`. Query Q1 is complete; Q2 to Q6 contain `TODO`s.
2. Run Q1 in the portal (**log-st<NN>-shared** › **Logs**, KQL mode), then with the `kql` function.
3. Complete and run Q2 to Q6, in the CLI or in the portal:
   - Q2: average and maximum CPU per minute of each web server over the last hour; in the portal, plot the chart (`render timechart`) and spot the lab 10.2 load;
   - Q3: number of Syslog events per facility and per level over the last 4 hours;
   - Q4: backup jobs since 13:30 (operation, status, protected item name, duration);
   - Q5: average availability of pool `bp-web` per 5-min interval from table `AzureMetrics`; spot the nginx stop on `web02`;
   - Q6: billable volume ingested per table over 24 h, in MB, sorted by decreasing volume.
4. Save Q6 in the workspace as a query (category `Arveo`, name "Ingested volume per table").
5. Answer in writing:
   - a. Which table costs the most? Estimate the monthly volume of the workspace at the current rate.
   - b. Why is table `AzureActivity` missing, although the activity log contains events?
   - c. Does Q5 show the nginx stop at the same minute as alert `alr-st<NN>-lb-sante`? Explain any gap.

**Hints** :
- Tables and columns: portal **Tables** pane, or `<TABLE> | getschema`; sample: `<TABLE> | take 5`.
- Q2: `Perf`, `ObjectName == "Processor"`, `CounterName == "% Processor Time"`, total instance (`InstanceName in ("_Total", "total")` `[TO VERIFY]` Linux AMA label), `summarize avg(), max() by Computer, bin(TimeGenerated, 1m)`.
- Q3: `Syslog`, `summarize count() by Facility, SeverityLevel`.
- Q4: `AddonAzureBackupJobs` (`JobOperation`, `JobStatus`, `JobDurationInSecs`, `BackupItemUniqueId`); item name: `CoreAzureBackup` (`BackupItemUniqueId`, `BackupItemFriendlyName`) with `join kind=leftouter`.
- Q5: `AzureMetrics`, `MetricName == "DipAvailability"`, `Resource =~ "lbe-st<NN>-web"`, `bin(TimeGenerated, 5m)`.
- Q6: `Usage`, columns `DataType`, `Quantity` (MB), `IsBillable`.
- Saved query: `az monitor log-analytics workspace saved-search create -g <GROUP> --workspace-name <WORKSPACE> -n <ID> --category Arveo --display-name "<NAME>" --saved-query "<KQL>"`.

**Success criteria** :
- [ ] Q1 to Q6 run without error; Q2 shows `web01` above 80 % during the lab 10.2 load.
- [ ] Q4 returns at least the `Backup` job of `partage-lyon` launched at 13:30.
- [ ] Q5 shows a value below 100 while nginx is stopped on `web02`.
- [ ] `az monitor log-analytics workspace saved-search list -g rg-st<NN>-shared --workspace-name log-st<NN>-shared --query "[?category=='Arveo'].displayName" -o tsv` displays query Q6.
- [ ] The three step 5 answers are written.

---

## Challenge 10.4 ⭐⭐⭐ — Detecting SSH brute-force attacks (autonomous)
**Duration** : 10 min in class (rule delivered; proof checked after the break) · **Objective** : create a log search alert with dimensions, linked to the action group, and assess its limits (objective 11)
**Context** : Arvéo's CISO notices SSH connection attempts on the web servers in the module 7 logs. An automatic detection is requested, per server and per source address, notified to operations, together with a query reusable by the security team. The rule must be delivered in versioned form.

Simulation of the attempts (provided, to run BEFORE testing the rule):
```bash
./scripts/labs/module-10/simuler-echecs-ssh.sh "$NN"
```
Expected result (script messages in French):
```
== Échecs SSH simulés sur vm-st07-web01 (journal authpriv, niveau warning)
   203.0.113.50 : 8 échecs
   198.51.100.7 : 3 échecs
Visibles dans la table Syslog sous 1 à 5 min.
```

**Requirements** :

| Element | Requirement |
|---|---|
| Detection | At least 5 `Failed password` messages in 10 min, per server AND per source address |
| Rule | `alr-st<NN>-ssh-echecs`, severity 1, evaluated every 5 min, automatically resolved, `ag-st<NN>-exploitation` |
| Reuse | KQL function `ArveoEchecsSsh` saved in `log-st<NN>-shared` (category `Arveo`) |
| Delivery | Versioned Bicep file (or CLI script), Arvéo tags, no hard-coded trainee-specific value |
| Proof | Alert fired for `vm-st<NN>-web01` and `203.0.113.50`, none for `198.51.100.7` |

**Assignment** :
1. Write and test the query in the portal, then save it as function `ArveoEchecsSsh` (columns `TimeGenerated`, `Computer`, `IpSource`, `SyslogMessage`).
2. Deploy the alert rule according to the requirements.
3. Run the simulation, then prove the result: alert fired (`alerts` function, dimensions visible in the portal), email received.
4. Answer in writing:
   - a. Measured delay between the simulation and the email: what does it consist of? How can it be reduced, and at what cost?
   - b. A real `sshd` daemon logs its failures at the `info` level of `authpriv`. Would rule `dcr-st<NN>-linux` (module 7) collect them? What should change, with what impact on cost?
   - c. Why can a metric alert not meet this need?

**Success criteria** :
- [ ] `az monitor scheduled-query show -g rg-st<NN>-shared -n alr-st<NN>-ssh-echecs --query "{Freq:evaluationFrequency, Window:windowSize, Sev:severity, Auto:autoMitigate}" -o table` displays `PT5M`, `PT10M`, `1`, `True`.
- [ ] `kql "ArveoEchecsSsh | summarize count() by Computer, IpSource"` returns 8 lines for `203.0.113.50` and 3 for `198.51.100.7`.
- [ ] `alerts` shows `alr-st<NN>-ssh-echecs` fired; no time series for `198.51.100.7` in the portal.
- [ ] The Bicep file (or the script) is versioned; the three step 4 answers are written.

---

## Lab 10.5 ⭐⭐ — Diagnosing Arvéo flows with Network Watcher (semi-autonomous)
**Duration** : 20 min (5 min before the break, 15 min after) · **Objective** : diagnose network flows with Network Watcher and use virtual network flow logs (objective 11)
**Context** : the ERP team opens a ticket: "since Tuesday evening, the test database `sql.arveo.internal:1433` (`vm-st<NN>-test-data`) can no longer be reached from the portal; the API still answers". In parallel, the security team asks for proof that SSH is denied from the Internet on the web servers and that the API only accepts the portal. The flow log of the application spoke has been active since 13:30.
**Prerequisites** : 13:30 preparation completed (Network Watcher agent, flow log, test VM started); variable block run.

**Assignment** :
1. **(15:10, before the break)** Check the France Central Network Watcher instance and the configuration of flow log `fl-st<NN>-spoke-app`: target, storage account, state, traffic analytics interval.
2. **(Before the break)** Generate traffic (provided): client requests on the portal, API calls from `web01`, SSH attempt from `web01` to an API instance, SQL attempt to the test database.
   ```bash
   LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
   API_VM=$(az vm list -g "$RG_APP" --query "[?virtualMachineScaleSet!=null] | [0].name" -o tsv)
   API_IP=$(az vm list-ip-addresses -g "$RG_APP" -n "$API_VM" \
     --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
   for i in $(seq 20); do curl -s -o /dev/null "http://${LB_IP}/"; curl -s -o /dev/null "http://${LB_IP}/api/"; done
   vmrun web01 "curl -s -m 3 -o /dev/null http://10.${OCT}.5.100:8080/ && echo API-OK
   timeout 3 bash -c '</dev/tcp/${API_IP}/22' 2>/dev/null && echo SSH-OUVERT || echo SSH-REFUSE
   timeout 3 bash -c '</dev/tcp/10.${OCT}.8.10/1433' 2>/dev/null && echo SQL-OK || echo SQL-ECHEC"
   echo "$API_VM $API_IP"
   ```
   Expected result (instance name and address vary):
   ```
   API-OK
   SSH-REFUSE
   SQL-ECHEC
   vmss-st07-api_1a2b3c4d 10.7.5.4
   ```
3. **(15:30, after the break)** Connection troubleshoot from `vm-st<NN>-web01`: to the API (`10.<OCT>.5.100`, TCP 8080), then to `sql.arveo.internal` (TCP 1433). Note the status, the number of failed probes and the issues reported on the hops.
4. Next hop from `web01` (`10.<OCT>.4.11`) to `10.<OCT>.8.10`, then to `10.<OCT>.5.100`.
5. IP flow verify, inbound direction, and deciding rule of each case:

   | Case | Target VM | Local port | Remote source |
   |---|---|---|---|
   | a | `vm-st<NN>-web01` | TCP 80 | `198.51.100.10:50000` (Internet) |
   | b | `vm-st<NN>-web01` | TCP 22 | `198.51.100.10:50000` (Internet) |
   | c | API instance (`$API_VM`) | TCP 8080 | `10.<OCT>.4.11:50000` (`web01`) |
   | d | API instance (`$API_VM`) | TCP 8080 | `10.<OCT>.8.10:50000` (test database) |

6. Query `NTANetAnalytics`: the 10 most frequent flow type / status / destination / port combinations over 2 h, then the DENIED flows (source, destination, port, NSG rule). Find the SSH attempt of step 2.
7. Answer in writing:
   - a. Cause of the ERP ticket and two possible fixes. Why would changing `nsg-st<NN>-data` be useless?
   - b. Why is case d not decided by `Deny-VNet-Inbound`?
   - c. Why was the flow log created at 13:30 and not when the ticket was opened?

**Hints** :
- Instance: `az network watcher list --query "[?location=='francecentral']"`.
- Flow log: `az network watcher flow-log show --location francecentral --name <NAME>` (properties `targetResourceId`, `storageId`, `enabled`, `flowAnalyticsConfiguration`).
- Connection: `az network watcher test-connectivity -g <GROUP> --source-resource <VM> --dest-address <ADDRESS_OR_NAME> --dest-port <PORT> --protocol Tcp` (30 to 60 s); properties `connectionStatus`, `probesFailed`, `hops[].issues`.
- Next hop: `az network watcher show-next-hop -g <GROUP> --vm <VM> --source-ip <IP> --dest-ip <IP>`.
- IP flow verify: `az network watcher test-ip-flow -g <GROUP> --vm <VM> --direction Inbound --protocol TCP --local <IP>:<PORT> --remote <IP>:<PORT>`; instance IP: `$API_IP`.
- Traffic analytics: columns `SubType` (`FlowLog`), `FlowType`, `FlowStatus`, `SrcIp`, `DestIp`, `DestPort`, `NsgRule`; data processed every 10 min, visible 20 to 30 min after the flow `[TO VERIFY]`.
- Reminders: M4 (`VirtualNetwork` service tag, non-transitive peering), D2 cleanup (`module-04-firewall.sh`).

**Success criteria** :
- [ ] Connection to the API: `Reachable`; to `sql.arveo.internal:1433`: `Unreachable`.
- [ ] Next hop to `10.<OCT>.8.10`: `None`; to `10.<OCT>.5.100`: `VnetLocal`.
- [ ] The four IP flow verify cases are noted with their deciding rule (a: allowed; b, c, d: decision and rule justified).
- [ ] The `NTANetAnalytics` query returns flows of the application spoke, including at least one denied flow.
- [ ] The three step 7 answers are written.

---

## Bonus 🚀
1. **Maintenance window**: create alert processing rule `apr-st<NN>-maintenance` that suppresses the notifications of the `rg-st<NN>-app` alerts every Tuesday from 22:00 to 23:00 (Paris time). Check that it does not prevent the alerts from being created. Hint: `az monitor alert-processing-rule create --rule-type RemoveAllActionGroups --schedule-recurrence-type Weekly` `[TO VERIFY]` scheduling options.
2. **Connection monitor**: create `cm-st<NN>-api`, which tests every 30 s the TCP 8080 connection from `vm-st<NN>-web01` to `10.<OCT>.5.100`, results in `log-st<NN>-shared`. Deallocate an API instance and observe table `NWConnectionMonitorTestResult` `[TO VERIFY]` table name.
3. **Packet capture**: capture 60 s of TCP 80 traffic on `vm-st<NN>-web02` to `starveost<NN>diag`, generate a few requests on the portal, download the `.cap` file and open it with Wireshark (or `tcpdump -r`). Spot the Load Balancer probes (`168.63.129.16`).
4. **"Arvéo Health" workbook**: create a workbook in `rg-st<NN>-shared` with three visualizations (Q1 as a table, Q2 as a chart, active alerts of the subscription filtered on `alr-st<NN>-`), a time range parameter, then export it as an ARM template (**Edit** › **Advanced Editor**).
5. **Dynamic threshold**: create a copy of the CPU rule with a dynamic threshold (medium sensitivity) and compare, in the portal, the computed band of "normal" values with the static 80 % threshold.

## Cleanup
- **End of the module (15:43)**, before the assessment:
  ```bash
  ./scripts/cleanup/module-10-monitoring.sh "$NN"
  ```
  The script stops the CPU load and restarts nginx on `web02` if needed, deletes flow log `fl-st<NN>-spoke-app` (traffic analytics cost), the bonus packet captures and connection monitors, and deallocates test VM `vm-st<NN>-test-data`. Safe to rerun.
- Kept for the final assessment: diagnostic settings, action group, alert rules, KQL function, Network Watcher extension.
- **End of the course**, before deleting the resource groups (after `module-09-backup.sh --purge`):
  ```bash
  ./scripts/cleanup/module-10-monitoring.sh "$NN" --purge
  ```
  Also deletes the alert rules, the alert processing rule, the action group, the saved queries, the diagnostic settings and the Network Watcher extension. The objects created in `NetworkWatcherRG` (flow logs, connection monitors, captures) do NOT disappear with the `rg-st<NN>-*` groups: this script is the only one that deletes them.
- Full module catch-up: `./scripts/catch-up/module-10/deploy.sh <NN> <EMAIL>`.
- Costs: Log Analytics ingestion per GB, metric alert rules per monitored time series, log search alert rules by evaluation frequency, flow logs per GB collected, traffic analytics per GB processed, notifications (emails included in a free quota) `[TO VERIFY]` Azure pricing calculator.
