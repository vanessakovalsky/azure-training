# Module 07 — Exercises

Common thread: **servers of the Arvéo customer portal and parcel-tracking API**. The web portal runs on two VMs spread across two zones behind a public Load Balancer; the API runs in a Flexible virtual machine scale set (VMSS) behind an internal Load Balancer. No VM has a public IP: administration through Azure Bastion from the hub, Internet egress through a NAT gateway. The web VMs are monitored by the Azure Monitor agent (data used in module 10) and backed up in module 9.

| Resource | Name (trainee 07) | Group | Lab |
|---|---|---|---|
| Bastion and its public IP | `bas-st07-hub`, `pip-st07-bastion` | `rg-st07-hub` | 07.2 (script) |
| NAT gateway | `ng-st07-app`, `pip-st07-natgw` (on `snet-web` and `snet-app`) | `rg-st07-spoke` | 07.2 |
| Web server 1 (zone 1) | `vm-st07-web01`, `nic-st07-web01` (`10.7.4.11`), `disk-st07-web01-data` | `rg-st07-app` | 07.2 |
| Web server 2 (zone 2) | `vm-st07-web02`, `nic-st07-web02` (`10.7.4.12`) | `rg-st07-app` | 07.3 |
| Public Load Balancer | `lbe-st07-web`, `pip-st07-lbe-web`, pool `bp-web` | `rg-st07-app` | 07.4 |
| API | `vmss-st07-api`, `lbi-st07-api` (`10.7.5.100`), `nsg-st07-app`, `as-st07-api` | `rg-st07-app` | 07.5 |
| Monitoring | `log-st07-shared` (module 3, `rg-st07-shared`), `dcr-st07-linux` | shared / app | 07.7 |

Variables used in all labs:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<REPO_URL>` = Git repository of the course, provided by the trainer

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`. Tag names and values stay in French: they are shared with the French-speaking groups of the same tenant. Lab scripts (`scripts/labs/module-07/`) are shared with those groups: their comments and messages are in French.

**Variable block**: paste it into Cloud Shell (Bash) at the start of EVERY lab (session closed after 20 min of inactivity).
```bash
NN=<NN>
OCT=$((10#$NN))
ST="st${NN}"
RG_HUB="rg-${ST}-hub"
RG_SPOKE="rg-${ST}-spoke"
RG_APP="rg-${ST}-app"
RG_SHARED="rg-${ST}-shared"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
DIAG_SA=$(az storage account list -g "$RG_SHARED" \
  --query "[?starts_with(name, 'starveost${NN}diag')].name | [0]" -o tsv)   # module 3
az config set extension.use_dynamic_install=yes_without_prompt -o none
cd ~/formation 2>/dev/null || git clone <REPO_URL> ~/formation && cd ~/formation
vmrun() {   # vmrun <web01|web02> "<BASH COMMAND>": run on vm-stNN-<name> (rg-stNN-app)
  az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
echo "$ST $OCT $RG_APP $RG_SPOKE $DIAG_SA"
```
Expected result (trainee 07; account name with the possible module 3 suffix):
```
st07 7 rg-st07-app rg-st07-spoke starveost07diag
```

**Starting state**: end of module 6 for the network, i.e. the state left by the day 2 cleanup: hub `vnet-st<NN>-hub` (subnet `AzureBastionSubnet` created in M4), app and data spokes WITHOUT firewall or route table, NSG `nsg-st<NN>-web` (inbound HTTP/HTTPS), empty group `rg-st<NN>-app`. Module 3 foundation in `rg-st<NN>-shared`: workspace `log-st<NN>-shared` and diagnostics account `starveost<NN>diag`. Module 7 uses no module 6 storage resource. Late trainee: `./scripts/catch-up/module-07/deploy.sh <NN>` (10 to 20 min) produces the END state of module 7.

---

## Exercise 07.1 ⭐ — Sizing the Arvéo workloads (in pairs)
**Duration** : 10 min · **Objective** : size a VM (size, disks, pricing option) for an Arvéo workload and justify the choice (objective 8)
**Context** : Arvéo IT is preparing the migration budget for four workloads of the Lyon datacenter. For each one, it expects a justified proposal.
**Prerequisites** : S7.1 slides.

| # | Workload | Profile measured in Lyon |
|---|---|---|
| 1 | Customer web portal | 2 servers, 2 vCPU and 4 GB each, average CPU 15 %, peaks at 60 % from 8 to 10 am |
| 2 | ERP database (SQL Server) | 8 vCPU, 64 GB, 24/7 for at least 3 years, SQL Server licenses with Software Assurance |
| 3 | Nightly route computation | 16 vCPU, 32 GB, 4 h per night, job can be restarted if interrupted |
| 4 | "Lyon" file server | 2 TB of SMB shares, moderate access, kept 6 months during the migration |

### Steps
1. For each workload, propose: family and size, disk type, pricing option.
2. For workload 1, check that the chosen size is available in the three France Central zones:
   ```bash
   az vm list-skus -l francecentral --size Standard_B2s_v2 --resource-type virtualMachines \
     --query "[].{Size:name, Zones:join(',', locationInfo[0].zones)}" -o table
   ```
   Expected result: a `Standard_B2s_v2` line with zones `1,2,3` (order may vary).
3. Note the regional vCPU quota of the shared subscription:
   ```bash
   Q="[?name.value=='cores' || name.value=='standardBSv2Family']"
   az vm list-usage -l francecentral -o table \
     --query "$Q.{Quota:name.localizedValue, Used:currentValue, Limit:limit}"
   ```
   Expected result: two lines (`Total Regional vCPUs`, `Standard BSv2 Family vCPUs`), values vary.
4. For workload 4, ask whether a VM is the right answer (module 6).

### Success criteria
- [ ] One proposal (size, disk, pricing option) per workload, each justified by a criterion of the profile.
- [ ] Workload 3 uses a pricing option suited to an interruptible job.
- [ ] The remaining quota is compared with the module's need (8 vCPU per trainee in France Central).

---

## Lab 07.2 ⭐ — First VM without a public IP, access through Bastion (guided)
**Duration** : 25 min · **Objective** : deploy a VM without a public IP through the CLI, then manage it through Azure Bastion (objective 8)
**Context** : the first Arvéo customer portal server is deployed in zone 1. Security requires: no public IP on servers, administration through a single entry point in the hub, Internet egress controlled by a fixed IP (declared to the transport partners).
**Prerequisites** : variable block run; M4 spokes present.

### Steps
1. **(13:32, before the S7.1 lecture)** Launch the Bastion creation (5 to 10 min):
   ```bash
   ./scripts/labs/module-07/bastion.sh "$NN"
   ```
   Expected result (script messages in French):
   ```
   == Sous-réseau AzureBastionSubnet de vnet-st07-hub
   10.7.1.0/26
   == IP publique pip-st07-bastion
      créée
   == Bastion bas-st07-hub (SKU Basic)
      déploiement lancé en arrière-plan (5 à 10 min)
   Suivi : az network bastion show -g rg-st07-hub -n bas-st07-hub --query provisioningState -o tsv
   ```
2. Create the NAT gateway and associate it with both subnets of the app spoke:
   ```bash
   az network public-ip create -g "$RG_SPOKE" -n "pip-${ST}-natgw" -l "$LOC" \
     --sku Standard --allocation-method Static --tags $TAGS -o none
   az network nat gateway create -g "$RG_SPOKE" -n "ng-${ST}-app" -l "$LOC" \
     --public-ip-addresses "pip-${ST}-natgw" --idle-timeout 4 --tags $TAGS -o none
   for SNET in snet-web snet-app; do
     az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
       -n "$SNET" --nat-gateway "ng-${ST}-app" -o none
   done
   az network vnet subnet list -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
     --query "[].{Name:name, NAT:natGateway.id}" -o tsv | sed 's#/subscriptions/.*/##'
   ```
   Expected result:
   ```
   snet-web	ng-st07-app
   snet-app	ng-st07-app
   ```
3. Generate the admin password of the Arvéo VMs (kept outside the Git repository):
   ```bash
   mkdir -p ~/.arveo
   [[ -s ~/.arveo/web-admin.txt ]] || ( umask 077; echo "Arv-$(openssl rand -hex 8)-Z9" > ~/.arveo/web-admin.txt )
   ADMIN_PW=$(cat ~/.arveo/web-admin.txt)
   echo "${#ADMIN_PW} characters"
   ```
   Expected result: `23 characters`.
4. Create the NIC (fixed IP) then the VM in zone 1, without a public IP, configured by cloud-init, with boot diagnostics in the module 3 account:
   ```bash
   SNET_WEB=$(az network vnet subnet show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
     -n snet-web --query id -o tsv)
   az network nic create -g "$RG_APP" -n "nic-${ST}-web01" -l "$LOC" --subnet "$SNET_WEB" \
     --private-ip-address "10.${OCT}.4.11" --tags $TAGS -o none
   az vm create -g "$RG_APP" -n "vm-${ST}-web01" -l "$LOC" --zone 1 --nics "nic-${ST}-web01" \
     --image Ubuntu2404 --size Standard_B2s_v2 \
     --os-disk-name "osdisk-${ST}-web01" --storage-sku StandardSSD_LRS \
     --admin-username arveoadmin --authentication-type password \
     --admin-password "$ADMIN_PW" \
     --custom-data scripts/labs/module-07/cloud-init-web.yaml \
     --boot-diagnostics-storage "$DIAG_SA" --tags $TAGS \
     --query "{State:powerState, IP:privateIpAddress, Zone:zones}" -o table
   ```
   Expected result (2 to 3 min):
   ```
   State       IP         Zone
   ----------  ---------  ------
   VM running  10.7.4.11  1
   ```
5. Wait for cloud-init to finish, then check the web page and the egress IP:
   ```bash
   vmrun web01 "cloud-init status --wait >/dev/null; curl -s localhost; curl -s --max-time 5 https://api.ipify.org; echo"
   az network public-ip show -g "$RG_SPOKE" -n "pip-${ST}-natgw" --query ipAddress -o tsv
   ```
   Expected result (1 to 3 min):
   ```
   <h1>Arveo - portail client v1</h1><p>Serveur : vm-st07-web01 - zone 1</p>
   <NAT_IP>
   <NAT_IP>
   ```
   The same address appears twice: the VM goes out through the NAT gateway. (The page text is in French: "customer portal", "server".)
6. Create a 32 GiB data disk in the VM's zone, attach it to LUN 0, then format it and mount it on `/srv/arveo`:
   ```bash
   az disk create -g "$RG_APP" -n "disk-${ST}-web01-data" -l "$LOC" --zone 1 \
     --size-gb 32 --sku StandardSSD_LRS --tags $TAGS -o none
   az vm disk attach -g "$RG_APP" --vm-name "vm-${ST}-web01" \
     --name "disk-${ST}-web01-data" --lun 0 --caching ReadOnly -o none
   vmrun web01 "$(cat scripts/labs/module-07/init-data-disk.sh)"
   ```
   Expected result (device name and rounded size vary):
   ```
   /dev/sdc1     32G /srv/arveo
   ```
7. Check that Bastion is ready (`Succeeded`), then connect in the portal: `vm-st<NN>-web01` → **Connect** → **Connect via Bastion** → authentication type **VM Password**, user `arveoadmin`, password from `~/.arveo/web-admin.txt`. In the terminal that opens:
   ```bash
   hostname; df -h /srv/arveo | tail -n 1; curl -s localhost
   ```
   Expected result:
   ```
   vm-st07-web01
   /dev/sdc1        32G   24K   30G   1% /srv/arveo
   <h1>Arveo - portail client v1</h1><p>Serveur : vm-st07-web01 - zone 1</p>
   ```
8. List the resources created by `az vm create` and check that no public IP and no NSG was created implicitly:
   ```bash
   az resource list -g "$RG_APP" --query "[].{Name:name, Type:type}" -o table
   ```
9. In the portal, open `vm-st<NN>-web01` → **Help** → **Boot diagnostics**: display the screenshot and the serial log (end of boot, final `cloud-init` line). Check the account used:
   ```bash
   az vm show -g "$RG_APP" -n "vm-${ST}-web01" \
     --query "diagnosticsProfile.bootDiagnostics.storageUri" -o tsv
   ```
   Expected result: `https://starveost07diag.blob.core.windows.net/`.

### Success criteria
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web01 -d --query "[zones[0], publicIps, privateIps]" -o tsv` shows `1`, an empty value and `10.<OCT>.4.11`.
- [ ] The egress IP noted in step 5 is that of `pip-st<NN>-natgw`.
- [ ] `vmrun web01 "findmnt -no SOURCE,TARGET /srv/arveo"` shows a partition mounted on `/srv/arveo`.
- [ ] Bastion session opened on `vm-st<NN>-web01`.
- [ ] Boot diagnostics active towards `starveost<NN>diag` (screenshot visible in the portal).

---

## Exercise 07.3 ⭐⭐ — Second web server in Bicep (semi-autonomous)
**Duration** : 15 min · **Objective** : deploy a VM reproducibly with Bicep, in another zone (objective 8)
**Context** : the Arvéo operations team wants a single model for every web server, versioned in the Git repository. The second portal server is created in zone 2 from this model.
**Prerequisites** : lab 07.2 completed (NAT gateway, password).

**Assignment** :
1. Copy `scripts/labs/module-07/vm-web-squelette.bicep` to `scripts/labs/module-07/vm-web.bicep` (same folder, for `loadTextContent`). The file comments are in French; parameter `nomCourt` = short name (e.g. `web02`).
2. Complete the five `TODO`s: zone, Ubuntu Server 24.04 LTS image, OS disk (`osdisk-st<NN>-<nomCourt>`, Standard SSD LRS, deleted with the VM), custom data `cloud-init-web.yaml`, password authentication.
3. Build with no error or warning, then preview the deployment of `web02` (zone 2, IP `10.<OCT>.4.12`) with `what-if`. If the module 3 diagnostics account has a suffix, pass `diagStorageName="$DIAG_SA"`.
4. Deploy, then check the page served by `vm-st<NN>-web02` (zone shown: 2).
5. Rerun `what-if` with the same parameters, then with `zone=3`. Note both results.
6. Answer in writing:
   - a. Why does the OS disk of `web02` not need a declared zone?
   - b. What would happen when deploying with `zone=3`? How can a VM be moved from one zone to another?
   - c. Change `cloud-init-web.yaml` then redeploy: does the `web02` page change? Why?

**Hints** :
- Zone property: `zones: [ zone ]` at the same level as `properties`.
- Image: `imageReference` object (`publisher`, `offer`, `sku`, `version`).
- OS disk: `createOption: 'FromImage'`, `deleteOption: 'Delete'`, `managedDisk.storageAccountType`.
- Custom data: `base64(loadTextContent('cloud-init-web.yaml'))`.
- Linux: `linuxConfiguration.disablePasswordAuthentication`.
- Build: `az bicep build --file <FILE>`; preview: `az deployment group what-if -g <GROUP> --template-file <FILE> --parameters ...`.
- Password: `adminPassword="$(cat ~/.arveo/web-admin.txt)"` (never in clear text in a file).

**Success criteria** :
- [ ] `az bicep build --file scripts/labs/module-07/vm-web.bicep` produces no error and no warning.
- [ ] `az vm show -g rg-st<NN>-app -n vm-st<NN>-web02 --query "[zones[0], storageProfile.osDisk.name]" -o tsv` shows `2` and `osdisk-st<NN>-web02`.
- [ ] `vmrun web02 "curl -s localhost"` shows `vm-st<NN>-web02 - zone 2`.
- [ ] The step 5 results and the three step 6 answers are written.

---

## Lab 07.4 ⭐⭐ — Public Load Balancer and cross-zone failover (semi-autonomous)
**Duration** : 20 min · **Objective** : make the portal highly available behind a Load Balancer and prove the failover (objective 8)
**Context** : Arvéo customers reach the portal through a single public address. Losing one server, or a whole France Central zone, must not interrupt the service.
**Prerequisites** : `vm-st<NN>-web01` (zone 1) and `vm-st<NN>-web02` (zone 2) running.

**Assignment** :
1. In `rg-st<NN>-app`, create the zone-redundant public IP `pip-st<NN>-lbe-web` and the Standard Load Balancer `lbe-st<NN>-web` (frontend `fe-web`, pool `bp-web`).
2. Create probe `hp-http` (HTTP, port 80, path `/`) and rule `rule-http` (TCP 80 → 80) WITHOUT outbound SNAT.
3. Add NICs `nic-st<NN>-web01` and `nic-st<NN>-web02` to pool `bp-web`.
4. From Cloud Shell, send 10 requests to the Load Balancer public IP and count the responses per server.
5. Simulate a failure: stop nginx on `web01`, wait 15 s, send 10 requests again. Display the pool health (metric or portal), then restart nginx.
6. Answer in writing:
   - a. Why disable the rule's outbound SNAT? Which way do the pool VMs go out?
   - b. Which rule of NSG `nsg-st<NN>-web` lets the clients in? What would happen without an NSG on `snet-web`?
   - c. Why must the module 4 test VMs (`vm-st<NN>-test-web`) NOT join this pool?

**Hints** :
- `az network public-ip create --sku Standard --zone 1 2 3`; `az network lb create --sku Standard --public-ip-address --frontend-ip-name --backend-pool-name`.
- `az network lb probe create --protocol Http --path /`; `az network lb rule create --disable-outbound-snat true`.
- IP configuration name of the NICs: `ipconfig1`; adding to the pool: `az network nic ip-config address-pool add`.
- Counting: `for i in $(seq 10); do curl -s http://<IP>/ ; echo; done | grep -o 'vm-st[0-9]*-web0[12]' | sort | uniq -c`.
- Failure: `vmrun web01 "systemctl stop nginx"` then `systemctl start nginx`.
- Health: Load Balancer metric `DipAvailability` (`az monitor metrics list --resource <LB_ID> --metric DipAvailability --interval PT1M`) or Load Balancer **Insights** in the portal.

**Success criteria** :
- [ ] `az network lb address-pool show -g rg-st<NN>-app --lb-name lbe-st<NN>-web -n bp-web --query "length(backendIPConfigurations)"` returns `2`.
- [ ] Step 4 shows responses from BOTH servers (zones 1 and 2).
- [ ] During the failure, 10 requests out of 10 are served by `web02`, with no error.
- [ ] The three step 6 answers are written.

---

## Challenge 07.5 ⭐⭐⭐ — Parcel-tracking API on a VMSS (autonomous)
**Duration** : 30 min · **Objective** : deploy a zone-redundant scale set with autoscale behind an internal Load Balancer (objective 8)
**Context** : the parcel-tracking API is called by the portal (and tomorrow by the drivers' mobile apps). Its load varies strongly with delivery times. The API must never be exposed to the Internet: only the portal (`snet-web`) may call it, and administration goes through Bastion.

**Requirements** :

| Element | Requirement |
|---|---|
| Instances | Flexible VMSS `vmss-st<NN>-api`, `Standard_B2s_v2`, Ubuntu 24.04, zones 1, 2 and 3, in `snet-app` |
| Configuration | `scripts/labs/module-07/cloud-init-api.yaml` (nginx on 8080, JSON response) |
| Load balancing | Internal Standard Load Balancer `lbi-st<NN>-api`, static zone-redundant frontend `10.<OCT>.5.100`, TCP 8080, HTTP probe `/` |
| Autoscale | `as-st<NN>-api`: 2 to 4 instances; +1 if average CPU > 70 % over 5 min; -1 if < 25 % over 10 min |
| Filtering | `nsg-st<NN>-app` on `snet-app`: 8080 from `snet-web`, 22 from `AzureBastionSubnet`, Load Balancer probe, deny the rest of VNet traffic |

**Assignment** :
1. Deploy the whole set, preferably in Bicep (file `vmss-api.bicep` in a personal folder), otherwise with documented CLI. Constraints: no public IP, subnet `snet-app` NOT redeclared in Bicep, NAT gateway kept on `snet-app`.
2. Prove it works with four tests:
   - a. from `web01`, six calls to `http://10.<OCT>.5.100:8080/`: at least two different instances respond;
   - b. the instances are spread across at least two zones;
   - c. from `web01`, TCP connection to port 22 of an instance: refused or timed out;
   - d. the autoscale profile shows min 2, max 4 and two rules.
3. Answer in writing:
   - a. Why Flexible rather than Uniform orchestration here?
   - b. What happens to the API if France Central zone 1 is lost? And if the minimum were 1?
   - c. Why associate the NSG and the NAT gateway with the subnet through the CLI rather than redeclaring `snet-app` in the Bicep file?

**Success criteria** :
- [ ] `az vmss show -g rg-st<NN>-app -n vmss-st<NN>-api --query "[orchestrationMode, zones]" -o json` shows `Flexible` and the three zones.
- [ ] The four tests give the expected result.
- [ ] `az network vnet subnet show -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-app -n snet-app --query "[natGateway.id, networkSecurityGroup.id]" -o tsv` returns `ng-st<NN>-app` and `nsg-st<NN>-app`.
- [ ] Redeploying the same file: `what-if` with no change on the VMSS or the Load Balancer.
- [ ] The three step 3 answers are written.

---

## Lab 07.6 ⭐⭐ — Portal v2 through the Custom Script extension (semi-autonomous)
**Duration** : 15 min · **Objective** : automate VM configuration with the Custom Script extension (objective 8)
**Context** : version 2 of the portal relays `/api/` calls to the parcel-tracking API. It must be deployed on both existing web servers, with no interactive session, in a replayable way.
**Prerequisites** : lab 07.4 completed; challenge 07.5 completed or catch-up run (otherwise `/api/` returns `502`).

**Assignment** :
1. Read `scripts/labs/module-07/portail-v2.sh`: identify what it changes and why it waits for cloud-init to finish.
2. Replace `__OCT__` with the trainee octet, base64-encode the script and apply it through the Custom Script extension (Linux, version 2.1) to `vm-st<NN>-web01` then `vm-st<NN>-web02`, as a PROTECTED setting.
3. Check the extension state, then the home page (`v2`) and `/api/` through `lbe-st<NN>-web`.
4. Reapply the extension on `web01` with exactly the same settings: does the script run? Prove it with the handler log. Do it again with the forced rerun option.
5. Answer in writing:
   - a. Why a protected setting rather than a public setting for the script?
   - b. What would happen if a second Custom Script extension with another script were then applied?
   - c. Would the `vmss-st<NN>-api` instances added by autoscale receive this script? Where should it be declared for them to receive it?

**Hints** :
- Encoding: `sed "s/__OCT__/${OCT}/g" <FILE> | base64 -w0`.
- `az vm extension set --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 --protected-settings '{"script": "<BASE64>"}'`.
- State: `az vm extension list ... --query "[].{Name:name, State:provisioningState}"`.
- Log: `vmrun web01 "tail -n 5 /var/log/azure/custom-script/handler.log"`.
- Rerun: `--force-update` option.

**Success criteria** :
- [ ] `CustomScript` in `Succeeded` on both VMs.
- [ ] `curl -s http://<LB_IP>/` shows `portail client v2` and `curl -s http://<LB_IP>/api/` returns the API JSON (`"service":"api-suivi-colis"`).
- [ ] The difference between a plain reapply and `--force-update` is proven by the log.
- [ ] The three step 5 answers are written.

---

## Lab 07.7 ⭐⭐ — Azure Monitor agent and data collection rule (semi-autonomous)
**Duration** : 20 min · **Objective** : install the Azure Monitor agent as an extension and collect Syslog and performance data from the web VMs (objective 8, preparing objective 11)
**Context** : the Arvéo operations team wants to centralize authentication logs and performance counters of the web servers in the single workspace of the foundation (module 3), used in module 10.
**Prerequisites** : `vm-st<NN>-web01` and `vm-st<NN>-web02` running, Internet egress through the NAT gateway.

**Assignment** :
1. Check the Log Analytics workspace `log-st<NN>-shared` created in module 3 in `rg-st<NN>-shared`: region, pricing tier, retention, customer ID.
2. Assign a system-assigned managed identity to both web VMs.
3. Install extension `AzureMonitorLinuxAgent` (publisher `Microsoft.Azure.Monitor`) on both VMs, automatic upgrade enabled.
4. Read then deploy `scripts/labs/module-07/dcr-arveo-linux.bicep` into `rg-st<NN>-app`. List the data collection rule associations of `web01`.
5. Generate a warning Syslog event on `web01`, then, after 5 to 10 min, query the workspace: latest heartbeats (`Heartbeat`) per computer and latest Syslog event of `web01`.
6. Answer in writing:
   - a. Why does the agent need a managed identity?
   - b. How would the same data be collected on a future Windows VM without changing the existing rule?
   - c. Which resource must be changed to also collect the `cron` facility?

**Hints** :
- `az monitor log-analytics workspace show --query "{Region:location, Tier:sku.name, Retention:retentionInDays, ID:customerId}"`; missing: module 3 catch-up.
- `az vm identity assign`; `az vm extension set --publisher Microsoft.Azure.Monitor --name AzureMonitorLinuxAgent --enable-auto-upgrade true`.
- Deployment: `az deployment group create -g <GROUP> --template-file <FILE> --parameters numero=<NN>`.
- Associations: `az monitor data-collection rule association list --resource <VM_ID>`.
- Event: `vmrun web01 "logger -p auth.warning 'Arveo test AMA st<NN>'"`.
- Query: `az monitor log-analytics query -w <WORKSPACE_CUSTOMER_ID> --analytics-query "<KQL>" -o table`; customer ID: `customerId` property of the workspace.

**Success criteria** :
- [ ] `AzureMonitorLinuxAgent` in `Succeeded` on both VMs.
- [ ] Association `dcra-vm-st<NN>-web01` points to `dcr-st<NN>-linux`.
- [ ] The `Heartbeat` query returns one line per web VM, less than 15 min old.
- [ ] The `Arveo test AMA` event is found in the `Syslog` table.
- [ ] The three step 6 answers are written.

---

## Bonus 🚀
1. **Public name of the portal**: update record `www` of public zone `arveo-st<NN>.fr` (module 4), which still points to the IP of the deleted firewall, so that it designates `pip-st<NN>-lbe-web`. Check the resolution with `nslookup www.arveo-st<NN>.fr <AZURE_NAME_SERVER>`.
2. **Entra ID sign-in**: install extension `AADSSHLoginForLinux` on `web02`, assign your own account the "Virtual Machine Administrator Login" role on `rg-st<NN>-app`, then connect through Bastion with Microsoft Entra ID authentication `[TO VERIFY]` support by the Basic SKU. Compare traceability with the local `arveoadmin` account.
3. **Availability set**: try to create `vm-st<NN>-test-as` in a set `avail-st<NN>-web` WITH `--zone 1`. Interpret the error. Immediately delete any resource created.
4. **Autoscale under load**: on an API instance, run `timeout 900 yes > /dev/null &` (twice, one per vCPU with `B2s_v2`) and watch the autoscale history (`az monitor activity-log list --resource-group rg-st<NN>-app --offset 30m`). Explain why a single loaded instance is not always enough to trigger the scale-out.

## Cleanup
- **End of day 3 (16:55)**:
  ```bash
  ./scripts/cleanup/module-07-vm.sh "$NN"
  ```
  The script deletes Bastion and its public IP (5 to 10 min), disables autoscale and deallocates the web VMs and the API instances. Safe to rerun if the Cloud Shell session closes.
- Kept for day 4: VMs (deallocated) and disks, Load Balancers, NAT gateway, NSG, extensions, data collection rule (modules 8 to 10); module 3 foundation unchanged.
- Bonus 3: delete `vm-st<NN>-test-as`, its disks and `avail-st<NN>-web` if they were created.
- Costs: Bastion Basic and public IPs billed hourly; NAT gateway per hour and per processed GB; Standard Load Balancer per rule and processed data; B2s_v2/B2s_v2 VMs per hour (deallocated: disks only); Log Analytics per ingested GB `[TO VERIFY]` Azure pricing calculator.
