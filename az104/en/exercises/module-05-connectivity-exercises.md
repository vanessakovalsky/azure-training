# Module 05 — Exercises

Common thread: **connecting the Arvéo network to the Lyon site**. The hub becomes the single entry point: its VPN gateway is shared with the spokes (transit), an IPsec tunnel links it to the Lyon datacenter, and every Lyon ↔ spoke flow crosses the firewall. A disaster recovery (DR) spoke is prepared in West Europe. The Lyon file server created here is reused in module 6 (Azure File Sync).

| Resource | Name (trainee 07) | Group | Lab |
|---|---|---|---|
| Gateway transit | options of links `peer-hub-to-spoke-*`, `peer-spoke-*-to-hub` | hub / spoke | 05.1 |
| DR spoke (West Europe) | `vnet-st07-spoke-pra`, links `peer-hub-to-spoke-pra`, `peer-spoke-pra-to-hub` | `rg-st07-spoke` / `rg-st07-hub` | 05.1 |
| Lyon server | `vm-st07-lyon-fs` (`10.200.7.10`), NIC `nic-st07-lyon-fs` | `rg-st07-lyon` | 05.2 (script) |
| Local network gateway and connection | `lng-st07-lyon`, `cn-st07-hub-to-lyon` | `rg-st07-hub` | 05.2 |
| Hybrid routing and filtering | `rt-st07-gateway`, group `rcg-lyon`, rule `Allow-SQL-From-Lyon` | hub / spoke | 05.3 |

Lyon side (trainer, read-only for trainees): `vnet-lyon` (`10.200.0.0/16`), subnet `snet-st07` (`10.200.7.0/24`), gateway `vpngw-lyon`, local network gateway `lng-lyon-st07` and connection `cn-lyon-to-st07`, in `rg-formation-lyon`. Resource names keep the French abbreviation `pra` (*plan de reprise d'activité*, disaster recovery) shared with the French-speaking groups.

Variables used in all labs:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<REPO_URL>` = Git repository of the course, provided by the trainer
- `<SHARED_KEY>` = tunnel shared key, provided by the trainer in lab 05.2

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`. Tag names and values stay in French: they are shared with the French-speaking groups of the same tenant.

**Variable block**: paste it into Cloud Shell (Bash) at the start of EVERY lab (session closed after 20 min of inactivity).
```bash
NN=<NN>
OCT=$((10#$NN))
ST="st${NN}"
RG_HUB="rg-${ST}-hub"
RG_SPOKE="rg-${ST}-spoke"
RG_LYON_ST="rg-${ST}-lyon"
RG_LYON="rg-formation-lyon"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
cd ~/formation 2>/dev/null || git clone <REPO_URL> ~/formation && cd ~/formation
tester() {   # tester <web|data> "<BASH COMMAND>": run on vm-stNN-test-<web|data>
  az vm run-command invoke -g "$RG_SPOKE" -n "vm-${ST}-test-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
lyon() {     # lyon "<POWERSHELL COMMAND>": run on vm-stNN-lyon-fs
  az vm run-command invoke -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" \
    --command-id RunPowerShellScript --scripts "$1" \
    --query "value[0].message" -o tsv
}
echo "$ST $OCT $RG_HUB $RG_SPOKE $RG_LYON_ST"
```
Expected result (trainee 07):
```
st07 7 rg-st07-hub rg-st07-spoke rg-st07-lyon
```

**Starting state**: end of module 4 (hub, gateway `vpngw-st<NN>-hub` in `Succeeded`, spokes peered with the hub, firewall `afw-st<NN>-hub` and its rules, spoke route tables, test VMs running). Late trainee: `./scripts/catch-up/module-04/deploy.sh <NN>` (10 to 20 min) during the S5.1 lecture.

---

## Lab 05.1 ⭐⭐ — Gateway transit and global peering (semi-autonomous)
**Duration** : 40 min · **Objective** : configure gateway transit and a global peering, then check their state (objective 6)
**Context** : Arvéo will pay for a single VPN gateway, the hub one; the spokes must use it to reach Lyon. IT is also preparing a disaster recovery plan in West Europe: a DR spoke, empty for now, must be connected to the France Central hub and benefit from the same access to Lyon. A second address range will be added to it during the project.
**Prerequisites** : module 4 completed (or catch-up), variable block run.

**Assignment** :
1. Check that `vpngw-st<NN>-hub` is `Succeeded`, then list the hub peering links with their state and their four options.
2. Enable gateway transit on the existing links: `allowGatewayTransit` on `peer-hub-to-spoke-app` and `peer-hub-to-spoke-data`, then `useRemoteGateways` on `peer-spoke-app-to-hub` and `peer-spoke-data-to-hub`.
3. Create `vnet-st<NN>-spoke-pra` in `rg-st<NN>-spoke`, region **West Europe**, range `10.<OCT>.12.0/23`, subnet `snet-pra` (`10.<OCT>.12.0/24`), mandatory tags.
4. Create the hub ↔ DR global peering: `peer-hub-to-spoke-pra` (access, forwarded traffic, gateway transit), then `peer-spoke-pra-to-hub` (access, forwarded traffic, remote gateway).
5. Display, for the three hub links: name, state, sync level, gateway transit; for the three spoke links: name and `useRemoteGateways`.
6. Add range `10.<OCT>.14.0/23` to the DR spoke. Note the sync level of the hub links, synchronize the relevant link, then check.
7. With the Network Watcher next hop, determine where a packet from `vm-st<NN>-test-web` to `10.<OCT>.12.4` (DR spoke address) would go.
8. Answer in writing:
   - a. Why is the "hub first, spoke next" order required in step 2?
   - b. Does the app spoke reach the DR spoke directly thanks to the global peering? What does step 7 show?
   - c. Why does the DR spoke not need a gateway of its own to reach Lyon?

**Hints** :
- Gateway state: `az network vnet-gateway show ... --query provisioningState -o tsv`.
- Updating an existing link: `az network vnet peering update ... --set allowGatewayTransit=true` (or `useRemoteGateways=true`).
- Creating a link with options: `az network vnet peering create --allow-vnet-access --allow-forwarded-traffic --allow-gateway-transit` (hub link) or `--use-remote-gateways` (spoke link). Remote VNet ID: `az network vnet show ... --query id -o tsv`.
- JMESPath projection: `--query "[].{Name:name, State:peeringState, Sync:peeringSyncLevel, Transit:allowGatewayTransit}" -o table`.
- Additional range: `az network vnet update --address-prefixes <RANGE1> <RANGE2>` (complete list); synchronization: `az network vnet peering sync`.
- Next hop: `az network watcher show-next-hop -g <VM_GROUP> --vm <VM> --source-ip <IP> --dest-ip <IP>`.

**Success criteria** :
- [ ] `az network vnet peering list -g rg-st<NN>-hub --vnet-name vnet-st<NN>-hub --query "[].[name, peeringState, peeringSyncLevel, allowGatewayTransit]" -o tsv` shows three links `Connected`, `FullyInSync`, `True`.
- [ ] The three `peer-spoke-*-to-hub` links have `useRemoteGateways` set to `true`.
- [ ] `az network vnet show -g rg-st<NN>-spoke -n vnet-st<NN>-spoke-pra --query "[location, addressSpace.addressPrefixes]" -o tsv` shows `westeurope` and both ranges.
- [ ] The three answers of step 8 are written.

---

## Lab 05.2 ⭐⭐ — Site-to-site VPN tunnel to Lyon (semi-autonomous)
**Duration** : 25 min (including 2 min BEFORE the S5.2 lecture) · **Objective** : establish a site-to-site VPN tunnel between the hub and the simulated Lyon site (objective 6)
**Context** : the Lyon network team has configured its side of the tunnel (`lng-lyon-st<NN>`, `cn-lyon-to-st<NN>`) and sent the shared key. What remains: declare Lyon in Azure, bring the tunnel up and check that a Lyon server sees the Arvéo network.
**Prerequisites** : lab 05.1 completed; shared key `<SHARED_KEY>` received.

**Assignment** :
1. **(14:30, before the lecture)** Launch the creation of the Lyon file server:
   ```bash
   ./scripts/labs/module-05/lyon-vm.sh "$NN"
   ```
   Expected result (script messages in French):
   ```
   Carte nic-st07-lyon-fs créée (10.200.7.10)
   VM vm-st07-lyon-fs : création lancée en arrière-plan (5 à 10 min)
   Mot de passe administrateur (arveoadmin) : /home/<USER>/.arveo/lyon-fs-admin.txt
   Suivi : az vm list -g rg-st07-lyon -d --query "[].{Nom:name, Etat:powerState, IP:privateIps}" -o table
   ```
2. Note the public IP of `vpngw-lyon` (`pip-lyon-vpngw`, group `rg-formation-lyon`) and that of your own gateway (`pip-st<NN>-vpngw`). Read the local network gateway `lng-lyon-st<NN>` created by the trainer: which IP and which range does it declare? Why a `/20`?
3. Create local network gateway `lng-st<NN>-lyon` (France Central): IP of `vpngw-lyon`, range `10.200.<OCT>.0/24`.
4. Create the IPsec connection `cn-st<NN>-hub-to-lyon` between `vpngw-st<NN>-hub` and `lng-st<NN>-lyon`, with the shared key received.
5. Follow the connection state until `Connected` (1 to 5 min), then note the inbound and outbound byte counters.
6. Display the effective routes of `nic-st<NN>-lyon-fs` whose next hop is `VirtualNetworkGateway`.
7. From `vm-st<NN>-lyon-fs`, query `http://10.<OCT>.4.10` (test web server of the app spoke): observe the failure.
8. Determine the next hop from `vm-st<NN>-lyon-fs` to `10.<OCT>.4.10`, then from `vm-st<NN>-test-web` to `10.200.<OCT>.10`.
9. Explain the step 7 failure by following the outbound packet, then the reply.

**Hints** :
- Public IP: `az network public-ip show -g <GROUP> -n <NAME> --query ipAddress -o tsv` (read allowed on the whole subscription).
- Local network gateway: `az network local-gateway show` (read) and `az network local-gateway create --gateway-ip-address --local-address-prefixes`.
- Connection: `az network vpn-connection create --vnet-gateway1 <GATEWAY> --local-gateway2 <LNG> --shared-key <KEY>`; never paste the key into a versioned file.
- State: properties `connectionStatus`, `ingressBytesTransferred`, `egressBytesTransferred` of `az network vpn-connection show`.
- Effective routes: `az network nic show-effective-route-table` (running VM).
- Test from Lyon: `lyon "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://<IP>).Content.Trim() } catch { 'ECHEC' }"` (30 to 60 s).
- Next hop of a West Europe VM: West Europe Network Watcher, same `show-next-hop` command.
- Step 9: `GatewaySubnet` routes (no UDR at this stage) and the `0.0.0.0/0` route of `snet-web` (module 4).

**Success criteria** :
- [ ] `az network vpn-connection show -g rg-st<NN>-hub -n cn-st<NN>-hub-to-lyon --query connectionStatus -o tsv` returns `Connected`.
- [ ] The effective routes of `nic-st<NN>-lyon-fs` contain `10.<OCT>.0.0/20` to `VirtualNetworkGateway`.
- [ ] Both next hops of step 8 are noted (`VirtualNetworkGateway`, `VirtualAppliance`).
- [ ] The step 9 explanation names the outbound path, the return path and the reason for the drop.

---

## Challenge 05.3 ⭐⭐⭐ 🔸 Optional — Lyon ↔ Arvéo hybrid flows as IaC (autonomous)
**Duration** : 50 min · **Objective** : route hybrid traffic through the firewall and prove allowed and blocked flows (objective 6)

> 🔸 **Optional** — Creates: route table `rt-st<NN>-gateway` (associated with `GatewaySubnet`, routes to spokes via firewall), rule collection group `rcg-lyon` in `afwp-st<NN>-hub`, NSG rule `Allow-SQL-From-Lyon` in `nsg-st<NN>-data`. Adjusted session: deploy `scripts/m5/catch-up/module-05/lyon-connectivity.bicep` directly (commented, provided by trainer). Full catch-up: `PSK='<SHARED_KEY>' ./scripts/m5/catch-up/module-05/deploy.sh <NN>`
**Context** : IT approves the flow matrix between the Lyon site and Azure for the migration period. Lyon applications must reach the web portal and the Azure database; no flow may leave Azure towards Lyon. The configuration must be versioned and replayable, like the module 4 rules.

**Flow matrix** :

| Source | Destination | Protocol / port | Decision |
|---|---|---|---|
| Lyon `10.200.<OCT>.0/24` | `snet-web` | TCP 80, 443 | Allow |
| Lyon `10.200.<OCT>.0/24` | `snet-data` | TCP 1433 | Allow |
| Lyon `10.200.<OCT>.0/24` | Any other Arvéo port or network | Any | Deny |
| App and data spokes | Lyon | Any | Deny |

**Assignment** :
1. Write `lyon-connectivity.bicep`, deployed into `rg-st<NN>-hub`, which:
   - creates route table `rt-st<NN>-gateway` (routes to both spokes through the firewall) and associates it with `GatewaySubnet`;
   - adds rule collection group `rcg-lyon` (priority 300) to the EXISTING policy `afwp-st<NN>-hub`;
   - adds rule `Allow-SQL-From-Lyon` (priority 110) to the existing NSG `nsg-st<NN>-data`, through a module.
2. Constraints:
   - a single mandatory parameter: the trainee number;
   - firewall private IP READ from the existing resource, never typed in;
   - ranges computed from the number;
   - existing resources referenced (`existing`), never redeclared, except `GatewaySubnet`.
3. Preview with `what-if`, deploy, then prove the matrix with five tests:
   - a. Lyon → `http://10.<OCT>.4.10`: response `vm-st<NN>-test-web`;
   - b. Lyon → `http://10.<OCT>.8.10:1433`: response `vm-st<NN>-test-data`;
   - c. Lyon → `http://10.<OCT>.8.10` (port 80): failure;
   - d. `vm-st<NN>-test-web` → `10.200.<OCT>.10`, port 3389: failure;
   - e. next hop from `vm-st<NN>-lyon-fs` to `10.<OCT>.8.10` and from `vm-st<NN>-test-data` to `10.200.<OCT>.10`.
4. Answer in writing:
   - a. Why would test b still fail with the firewall rule alone?
   - b. Why does `rt-st<NN>-gateway` contain neither a `0.0.0.0/0` route nor a route to the hub?
   - c. What would happen to the tunnel if gateway route propagation were disabled on this table?

**Success criteria** :
- [ ] `az bicep build --file lyon-connectivity.bicep` produces no error.
- [ ] `az network vnet subnet show -g rg-st<NN>-hub --vnet-name vnet-st<NN>-hub -n GatewaySubnet --query routeTable.id -o tsv` ends with `rt-st<NN>-gateway`.
- [ ] The five tests give the expected result.
- [ ] Redeploying the file: `what-if` with no rule or route change.
- [ ] The three answers of step 4 are written.

---

## Case study 05.4 — Choosing hybrid connectivity (group)
**Duration** : 5 min · **Objective** : justify choosing VPN, ExpressRoute or Virtual WAN for a given need (objective 6)
**Context** : Arvéo's executive committee asks for a recommendation for three upcoming needs.

**Assignment** : for each need, name the solution, give two arguments and one risk.
1. **Lyon datacenter migration**: 40 TB of data to transfer in 3 months; the ERP will stay 18 months in hybrid production (database in Lyon, application servers in Azure) with a guaranteed latency required by the vendor.
2. **Branch network**: 14 regional branches (fiber broadband box, no local IT team) and 60 mobile sales staff must reach the Azure applications; branches must also reach Lyon.
3. **After the Lyon closure (end of 2027)**: no on-site server left, network budget cut by half, only head-office workstations (200 users, business Internet) access the applications.

**Success criteria** :
- [ ] One justified solution per need, with at least one quantified criterion (throughput, lead time, number of sites or cost).
- [ ] One risk or limit identified for each solution.

---

## Bonus 🚀
1. **DNS resolution from Lyon**: from `vm-st<NN>-lyon-fs`, resolve `sql.arveo.internal` (`Resolve-DnsName`). Explain the result and propose, without deploying it, the architecture that would make this resolution possible (course S4.4).
2. **DR reachable from Lyon**: extend `lyon-connectivity.bicep` so that the Lyon → `snet-pra` flow (TCP 443) crosses the firewall, then check with `show-next-hop` from `vm-st<NN>-lyon-fs` to `10.<OCT>.12.4`. Which additional resources are needed on the DR side for symmetric routing, and in which region?
3. **Effective IPsec policy**: list the custom IPsec/IKE policy of `cn-st<NN>-hub-to-lyon` (`az network vpn-connection ipsec-policy list`). Interpret an empty result, then explain why enforcing a policy on only one side of the tunnel can prevent it from coming up.

## Cleanup
- **End of day 2 (16:55)**, in this order, in the background if possible:
  ```bash
  ./scripts/cleanup/module-05-vpn.sh "$NN"
  ./scripts/cleanup/module-04-firewall.sh "$NN"
  ```
  `module-05-vpn.sh` deletes the connection, the local network gateway, the VPN gateway (10 to 20 min) and its public IP, disables gateway transit and stops `vm-st<NN>-lyon-fs`. Safe to rerun if the Cloud Shell session closes during the deletion.
- Kept: VNets (including the DR spoke), peerings, `rt-st<NN>-gateway`, group `rcg-lyon`, rule `Allow-SQL-From-Lyon`, stopped Lyon server (reused in module 6).
- Lyon side: the trainer deletes connections, local network gateways and `vpngw-lyon` (`lyon-site.sh cleanup`).
- Re-creation later if needed: `./scripts/prereq-vpn-gateways.sh <NN>` (45 min), then `PSK='<SHARED_KEY>' ./scripts/catch-up/module-05/deploy.sh <NN>`.
- Costs: VpnGw1AZ VPN gateways and public IPs billed hourly, global peering traffic and VPN egress billed per GB, Windows B2s_v2 VM and its disk `[TO VERIFY]` Azure pricing calculator.
