# Module 04 — Exercises

Common thread: building the **Arvéo hub-spoke network** in `rg-stNN-hub` and `rg-stNN-spoke`, foundation of the VPN link with Lyon (M5), private endpoints (M6) and application VMs (M7).

| Resource | Name (trainee 07) | Group | Lab |
|---|---|---|---|
| Hub + reserved subnets + VPN gateway | `vnet-st07-hub`, `vpngw-st07-hub` | `rg-st07-hub` | 04.1 (script) |
| App and data spokes | `vnet-st07-spoke-app`, `vnet-st07-spoke-data` | `rg-st07-spoke` | 04.1 |
| Test VMs | `vm-st07-test-web`, `vm-st07-test-data` | `rg-st07-spoke` | 04.1 (script) |
| NSGs and ASG | `nsg-st07-web`, `nsg-st07-data`, `asg-st07-data` | `rg-st07-spoke` | 04.2 |
| Firewall, peerings, route tables | `afw-st07-hub`, `rt-st07-spoke-app`, `rt-st07-spoke-data` | hub / spoke | 04.3 |
| Firewall rules | group `rcg-arveo` in `afwp-st07-hub` | `rg-st07-hub` | 04.4 |
| DNS zones | `arveo.internal`, `arveo-st07.fr` | `rg-st07-hub` | 04.5 |

Variables used in all labs:
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<REPO_URL>` = Git repository of the course, provided by the trainer

Mandatory tags on every resource (module 2 policy): `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`. Tag names and values stay in French: they are shared with the French-speaking groups of the same tenant.

**Variable block**: paste it into Cloud Shell (Bash) at the start of EVERY lab (session closed after 20 min of inactivity).
```bash
NN=<NN>
OCT=$((10#$NN))
ST="st${NN}"
RG_HUB="rg-${ST}-hub"
RG_SPOKE="rg-${ST}-spoke"
LOC="francecentral"
TAGS="Projet=Arveo Environnement=Formation Proprietaire=${ST}"
cd ~/formation 2>/dev/null || git clone <REPO_URL> ~/formation && cd ~/formation
echo "$ST $OCT $RG_HUB $RG_SPOKE"
```
Expected result (trainee 07):
```
st07 7 rg-st07-hub rg-st07-spoke
```
`OCT` = number without a leading zero, the only valid form in an IP address (`10.7.0.0`, never `10.07.0.0`).

---

## Lab 04.1 ⭐ — Address plan and hub-spoke networks (guided)
**Duration** : 30 min · **Objective** : design a non-overlapping address plan and deploy the hub-spoke networks (objective 5)
**Context** : Arvéo groups connectivity (VPN to Lyon) and security (firewall) in a hub, and isolates the web portal and the data in two spokes. The VPN gateway needs 30 to 45 min to provision: it is launched first.
**Prerequisites** : module 3 completed; Cloud Shell in Bash; variable block run.

### Steps
1. **(09:00, before the lecture)** Run the hub and VPN gateway pre-deployment script.
   ```bash
   ./scripts/prereq-vpn-gateways.sh "$NN"
   ```
   Expected result (less than 2 min; script messages are in French):
   ```
   == Réseau vnet-st07-hub (10.7.0.0/22) dans rg-st07-hub
      créé avec GatewaySubnet 10.7.0.0/27
      sous-réseau AzureFirewallSubnet 10.7.0.64/26 créé
      sous-réseau AzureFirewallManagementSubnet 10.7.0.128/26 créé
      sous-réseau AzureBastionSubnet 10.7.1.0/26 créé
      sous-réseau snet-shared 10.7.2.0/24 créé
   == IP publique pip-st07-vpngw (Standard, zones 1 2 3)
   == Passerelle vpngw-st07-hub (VpnGw1AZ, route-based)
      déploiement lancé en arrière-plan (30 à 45 min)
   Suivi : az network vnet-gateway show -g rg-st07-hub -n vpngw-st07-hub --query provisioningState -o tsv
   ```

2. Fill in, on paper, the address plan for your own number (model: trainee 07, course S4.1).

   | Network or subnet | Range for trainee `<NN>` | Assignable addresses |
   |---|---|---|
   | `vnet-st<NN>-hub` | | |
   | `GatewaySubnet` | | |
   | `AzureFirewallSubnet` | | |
   | `vnet-st<NN>-spoke-app` / `snet-web` / `snet-app` | | |
   | `vnet-st<NN>-spoke-data` / `snet-data` / `snet-pe` | | |
   | Trainee's Lyon subnet | | |

   Expected result: no shared range between lines of different networks; number of addresses = block size − 5.

3. Inspect the hub created by the script.
   ```bash
   az network vnet subnet list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
     --query "[].{Name:name, Range:addressPrefix}" -o table
   ```
   Expected result:
   ```
   Name                           Range
   -----------------------------  -------------
   GatewaySubnet                  10.7.0.0/27
   AzureFirewallSubnet            10.7.0.64/26
   AzureFirewallManagementSubnet  10.7.0.128/26
   AzureBastionSubnet             10.7.1.0/26
   snet-shared                    10.7.2.0/24
   ```

4. Create the app spoke with its two subnets.
   ```bash
   az network vnet create -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" -l "$LOC" \
     --address-prefixes "10.${OCT}.4.0/22" \
     --subnet-name snet-web --subnet-prefixes "10.${OCT}.4.0/24" \
     --tags $TAGS -o none
   az network vnet subnet create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
     -n snet-app --address-prefixes "10.${OCT}.5.0/24" -o none
   ```
   Expected result: no output, back to the prompt within 30 s.

5. Create the data spoke with `snet-data` (`10.<OCT>.8.0/24`) and `snet-pe` (`10.<OCT>.9.0/24`, M6 private endpoints).
   ```bash
   az network vnet create -g "$RG_SPOKE" -n "vnet-${ST}-spoke-data" -l "$LOC" \
     --address-prefixes "10.${OCT}.8.0/22" \
     --subnet-name snet-data --subnet-prefixes "10.${OCT}.8.0/24" \
     --tags $TAGS -o none
   az network vnet subnet create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
     -n snet-pe --address-prefixes "10.${OCT}.9.0/24" -o none
   ```

6. Check the three address spaces.
   ```bash
   az network vnet list \
     --query "[?starts_with(name, 'vnet-${ST}-')].{Name:name, Range:addressSpace.addressPrefixes[0], Region:location}" \
     -o table
   ```
   Expected result:
   ```
   Name                  Range        Region
   --------------------  -----------  -------------
   vnet-st07-hub         10.7.0.0/22  francecentral
   vnet-st07-spoke-app   10.7.4.0/22  francecentral
   vnet-st07-spoke-data  10.7.8.0/22  francecentral
   ```

7. Observe the reserved addresses: `.3` is reserved, `.10` is free.
   ```bash
   az network vnet check-ip-address -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" \
     --ip-address "10.${OCT}.4.3" --query available
   az network vnet check-ip-address -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" \
     --ip-address "10.${OCT}.4.10" --query available
   ```
   Expected result:
   ```
   false
   true
   ```

8. Create a test Standard public IP, inspect it, then delete it.
   ```bash
   az network public-ip create -g "$RG_SPOKE" -n "pip-${ST}-test" -l "$LOC" \
     --sku Standard --allocation-method Static --zone 1 2 3 --tags $TAGS -o none
   az network public-ip show -g "$RG_SPOKE" -n "pip-${ST}-test" \
     --query "{IP:ipAddress, SKU:sku.name, Allocation:publicIPAllocationMethod, Zones:join(',', zones)}" \
     -o table
   az network public-ip delete -g "$RG_SPOKE" -n "pip-${ST}-test"
   ```
   Expected result (address specific to each trainee):
   ```
   IP               SKU       Allocation    Zones
   ---------------  --------  ------------  -------
   <ASSIGNED_IP>    Standard  Static        1,2,3
   ```

9. Launch the creation of the two test VMs (used in S4.2, S4.3 and S4.4).
   ```bash
   ./scripts/labs/module-04/test-vms.sh "$NN"
   ```
   Expected result (script messages in French):
   ```
   Carte nic-st07-test-web créée (10.7.4.10)
   VM vm-st07-test-web : création lancée en arrière-plan (2 à 4 min)
   Carte nic-st07-test-data créée (10.7.8.10)
   VM vm-st07-test-data : création lancée en arrière-plan (2 à 4 min)
   ```

10. Follow the VPN gateway.
    ```bash
    az network vnet-gateway show -g "$RG_HUB" -n "vpngw-${ST}-hub" --query provisioningState -o tsv
    ```
    Expected result: `Updating` (deployment in progress), then `Succeeded` around 09:45.

### Success criteria
- [ ] Address table filled in, with no overlap.
- [ ] `az network vnet list` (step 6) shows three consecutive `/22` VNets.
- [ ] `az network vnet subnet list -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-data -o table` shows `snet-data` and `snet-pe`.
- [ ] `az vm list -g rg-st<NN>-spoke -d --query "[].{Name:name, IP:privateIps}" -o table` shows both VMs on `.4.10` and `.8.10`.

---

## Exercise 04.2 ⭐⭐ — Filtering with NSGs and ASGs (semi-autonomous)
**Duration** : 30 min · **Objective** : filter flows with NSGs and ASGs, then check effective rules (objective 5)
**Context** : Arvéo's future database (data spoke) must accept only SQL traffic coming from the web subnet. The web subnet will receive HTTP/HTTPS traffic from a load balancer (M7). IT requires readable rules, named by role rather than by address.
**Prerequisites** : Lab 04.1 completed, test VMs in `VM running` state.

**Assignment** :
1. Create `nsg-st<NN>-web` and associate it with `snet-web`, with an inbound rule `Allow-HTTP-HTTPS-Inbound` (TCP 80 and 443, any source, priority 100).
2. Create application security group `asg-st<NN>-data` and place NIC `nic-st<NN>-test-data` in it.
3. Create `nsg-st<NN>-data`, associate it with `snet-data`, with two inbound rules:
   - `Allow-SQL-From-Web` (priority 100): TCP 1433 from `snet-web` to `asg-st<NN>-data`;
   - `Deny-VNet-Inbound` (priority 4000): all traffic from the `VirtualNetwork` tag denied.
4. Display the effective inbound rules of NIC `nic-st<NN>-test-data` (name, priority, access).
5. With IP flow verify, test the four inbound flows to `10.<OCT>.8.10` and note the deciding rule for each:

   | Case | Source | Destination port |
   |---|---|---|
   | a | `10.<OCT>.4.10` (snet-web) | 1433 |
   | b | `10.<OCT>.5.20` (snet-app) | 1433 |
   | c | `10.<OCT>.4.10` (snet-web) | 22 |
   | d | `10.<OCT>.9.20` (snet-pe, same VNet) | 1433 |

6. Explain in writing why cases b and c are NOT decided by `Deny-VNet-Inbound`, whereas case d is.

**Hints** :
- `az network asg create`, `az network nic ip-config update --application-security-groups` (IP configuration `ipconfig1`).
- `az network nsg rule create --help`: `--source-address-prefixes`, `--destination-asgs`, `--destination-port-ranges`.
- Effective rules: `az network nic list-effective-nsg` (running VM required); filter `effectiveSecurityRules` on `direction`.
- IP flow verify: `az network watcher test-ip-flow --vm ... --local <IP>:<PORT> --remote <IP>:<PORT>`.
- Cases b and c: compare the content of the `VirtualNetwork` tag (course S4.2) with the current topology (no peering).

**Success criteria** :
- [ ] `az network vnet subnet show -g rg-st<NN>-spoke --vnet-name vnet-st<NN>-spoke-data -n snet-data --query networkSecurityGroup.id -o tsv` ends with `nsg-st<NN>-data`.
- [ ] `az network nic show -g rg-st<NN>-spoke -n nic-st<NN>-test-data --query "ipConfigurations[0].applicationSecurityGroups[0].id" -o tsv` ends with `asg-st<NN>-data`.
- [ ] Case a: `Allow` by `Allow-SQL-From-Web`; case d: `Deny` by `Deny-VNet-Inbound`.
- [ ] Explanation of cases b and c written (`VirtualNetwork` tag without peering).

---

## Exercise 04.3 ⭐⭐ — Firewall, peerings and routes (semi-autonomous)
**Duration** : 20 min (including 3 min BEFORE the S4.3 lecture) · **Objective** : force inter-spoke and outbound traffic through Azure Firewall with UDRs (objective 5)
**Context** : Arvéo IT wants a single control point for flows between spokes and to the Internet. The firewall is described in a Bicep file approved by the network team; it remains to deploy it, connect the spokes to the hub and steer traffic to it.
**Prerequisites** : exercise 04.2 completed; VPN gateway `Succeeded` (otherwise hub-side peering is rejected while the gateway is updating).

**Assignment** :
1. **(Before the lecture)** Read `scripts/labs/module-04/firewall.bicep`, then launch its deployment into `rg-st<NN>-hub` under the name `firewall`, without waiting for completion:
   ```bash
   az deployment group create -g "$RG_HUB" -n firewall \
     -f scripts/labs/module-04/firewall.bicep -p numero="$NN" --no-wait
   ```
   Reading questions: which resources are created? Why two public IPs? Which subnet carries each IP configuration? What does the policy filter when created?
2. Create the four peering links (hub ↔ app spoke, hub ↔ data spoke), forwarded traffic allowed on both sides; names: `peer-hub-to-spoke-app`, `peer-spoke-app-to-hub`, `peer-hub-to-spoke-data`, `peer-spoke-data-to-hub`.
3. From `vm-st<NN>-test-web`, test `http://10.<OCT>.8.10:1433`: observe the failure and explain it.
4. Wait for the firewall deployment to complete and store its private IP in variable `FW_IP`.
5. Create `rt-st<NN>-spoke-app` (associated with `snet-web` and `snet-app`) and `rt-st<NN>-spoke-data` (associated with `snet-data`): BGP propagation disabled, route `default-via-fw` `0.0.0.0/0` → `VirtualAppliance` `$FW_IP`.
6. Display the effective routes of `nic-st<NN>-test-web`, then the next hop from `10.<OCT>.4.10` to `10.<OCT>.8.10`.
7. Run the step 3 test again: it still fails. Explain how its cause differs from step 3.

**Hints** :
- VNet ID: `az network vnet show -g <GROUP> -n <VNET> --query id -o tsv` (the remote VNet is in another group).
- Peering: `az network vnet peering create --remote-vnet <ID> --allow-vnet-access --allow-forwarded-traffic`; state: `peeringState`.
- Test from a VM without a public IP: `az vm run-command invoke --command-id RunShellScript --scripts "<COMMAND>" --query "value[0].message" -o tsv` (30 to 60 s per call).
- Test command: `curl -s -m 5 http://<IP>:<PORT> || echo ECHEC`.
- Waiting: `az deployment group wait --created`, then deployment output `firewallPrivateIp`.
- Next hop: `az network watcher show-next-hop`.

**Success criteria** :
- [ ] `az network vnet peering list -g rg-st<NN>-hub --vnet-name vnet-st<NN>-hub --query "[].peeringState" -o tsv` shows `Connected` twice.
- [ ] `az network firewall show -g rg-st<NN>-hub -n afw-st<NN>-hub --query provisioningState -o tsv` returns `Succeeded` (or the `az resource show` equivalent).
- [ ] Effective routes of `nic-st<NN>-test-web`: `0.0.0.0/0` → `VirtualAppliance` `$FW_IP`, source `User`.
- [ ] `show-next-hop` returns `VirtualAppliance` and the firewall IP.
- [ ] Both failure causes (steps 3 and 7) explained.

---

## Challenge 04.4 ⭐⭐⭐ 🔸 Optional — Firewall rules as IaC (autonomous)
**Duration** : 20 min · **Objective** : define the hub filtering policy in Bicep and check allowed and blocked flows (objective 5)

> 🔸 **Optional** — Creates: rule collection group `rcg-arveo` in `afwp-st<NN>-hub` (network and application rules, Internet filtering for spokes). Used in M5 (inter-spoke flows and Internet egress via firewall). Catch-up: `./scripts/m4/catch-up/module-04/deploy.sh <NN>`
**Context** : Arvéo's flow matrix has been approved by IT. It must be applied by a versioned file, replayable on every environment, and proven by reproducible tests.

**Flow matrix** :

| Source | Destination | Protocol / port | Decision |
|---|---|---|---|
| `snet-web` | `snet-data` | TCP 1433 | Allow |
| `snet-data` | `snet-web` | Any | Deny |
| App and data spokes | Ubuntu repositories `*.ubuntu.com` | HTTP 80, HTTPS 443 | Allow |
| App and data spokes | Any other Internet site | Any | Deny |

**Assignment** :
1. Write `firewall-rules.bicep` that adds rule collection group `rcg-arveo` to the EXISTING policy `afwp-st<NN>-hub`.
2. Constraints:
   - a single mandatory parameter: the trainee number;
   - ranges computed from the number, no address hard-coded for a given trainee;
   - list of allowed FQDNs supplied as a parameter, defaulting to `*.ubuntu.com`;
   - policy referenced, never redeclared.
3. Preview with `what-if`, deploy, then prove the matrix with five tests run on the test VMs:
   - a. web → `http://10.<OCT>.8.10:1433`: response `vm-st<NN>-test-data`;
   - b. data → `http://10.<OCT>.4.10`: failure;
   - c. web → `http://azure.archive.ubuntu.com/ubuntu/`: HTTP code `200`;
   - d. web → `http://www.example.com`: HTTP code `470` (firewall denial);
   - e. web → `https://www.example.com`: failure.
4. Explain why test d returns an HTTP response whereas test e fails with no response.

**Success criteria** :
- [ ] `az bicep build --file firewall-rules.bicep` produces no error.
- [ ] `az network firewall policy rule-collection-group show -g rg-st<NN>-hub --policy-name afwp-st<NN>-hub -n rcg-arveo --query provisioningState -o tsv` returns `Succeeded` (or the `az resource show` equivalent).
- [ ] The five tests give the expected result.
- [ ] Redeploying the file: `what-if` with no change at all.

---

## Exercise 04.5 ⭐⭐ 🔸 Optional — Private and public DNS zones (semi-autonomous)
**Duration** : 30 min · **Objective** : resolve names with Azure DNS public and private zones (objective 5)

> 🔸 **Optional** — Creates: private zone `arveo.internal` (links `link-hub`, `link-spoke-app`, `link-spoke-data`, A record `sql`) and public zone `arveo-st<NN>.fr` in `rg-st<NN>-hub`. Used in M6 (DNS resolution for private endpoints) and M7 (`sql.arveo.internal` from application VMs). Catch-up: `./scripts/m4/catch-up/module-04/deploy.sh <NN>`
**Context** : Arvéo applications must reach the database through a stable name, independent of the server address. The future public site will be published behind the firewall.
**Prerequisites** : challenge 04.4 completed (or catch-up script), test VMs running.

**Assignment** :
1. Create private zone `arveo.internal` in `rg-st<NN>-hub` and three virtual network links:
   - `link-hub` to `vnet-st<NN>-hub`, without auto-registration;
   - `link-spoke-app` and `link-spoke-data` to the spokes, with auto-registration.
2. Add A record `sql` → `10.<OCT>.8.10`.
3. List the zone records: both test VMs must appear without manual action.
4. From `vm-st<NN>-test-web`:
   - resolve `sql.arveo.internal` and `vm-st<NN>-test-data.arveo.internal`;
   - query `http://sql.arveo.internal:1433`.
5. Create public zone `arveo-st<NN>.fr` in `rg-st<NN>-hub` and A record `www` → public IP `pip-st<NN>-fw`.
6. From Cloud Shell, query `www.arveo-st<NN>.fr` directly on the zone's first name server, then through a regular resolver.
7. Explain both results of step 6.

**Hints** :
- `az network private-dns zone create`, `az network private-dns link vnet create` (`--registration-enabled` mandatory), `az network private-dns record-set a add-record`.
- Resolution on the VM: `getent hosts <NAME>` in `az vm run-command invoke`.
- Public zone: `az network dns zone create`, `az network dns record-set a add-record`; servers: zone property `nameServers`.
- Targeted query: `dig +short @<SERVER> <NAME>` (or `nslookup <NAME> <SERVER>`).

**Success criteria** :
- [ ] `az network private-dns link vnet list -g rg-st<NN>-hub -z arveo.internal --query "[].{Name:name, Auto:registrationEnabled, State:virtualNetworkLinkState}" -o table` shows three `Completed` links, two of them with `True`.
- [ ] The record list contains `sql`, `vm-st<NN>-test-web` and `vm-st<NN>-test-data`.
- [ ] From the web VM, `curl http://sql.arveo.internal:1433` returns `vm-st<NN>-test-data`.
- [ ] `dig` on the Azure server returns the `pip-st<NN>-fw` IP; the step 7 explanation is written.

---

## Bonus 🚀
1. **DNAT publishing**: add to `firewall-rules.bicep` a DNAT collection publishing port 80 of `vm-st<NN>-test-web` on port 8080 of the firewall public IP; test from Cloud Shell with `curl http://<FIREWALL_PUBLIC_IP>:8080`.
2. **VirtualNetwork tag**: replay case b of exercise 04.2 (IP flow verify, `10.<OCT>.5.20` → `10.<OCT>.8.10:1433`) after the UDRs are in place. Compare the deciding rule and explain it.
3. **Cross-check**: from `vm-st<NN>-test-web`, test `http://10.<OCT>.5.20` (free address of `snet-app`), then read the next hop with `show-next-hop`: does intra-spoke traffic go through the firewall?

## Cleanup
- End of morning: nothing to delete, everything is reused in module 5 (afternoon).
- **End of day 2** (after module 5): `./scripts/cleanup/module-04-firewall.sh <NN>` deletes the firewall and its two public IPs, dissociates the route tables and stops the test VMs. Policy, rules, route tables, NSGs and DNS zones are kept.
- Re-creation later if needed: `./scripts/catch-up/module-04/deploy.sh <NN>`.
- Costs: Azure Firewall Basic, Standard public IPs and B2s_v2 VMs billed hourly `[TO VERIFY]` Azure pricing calculator; DNS zones and NSGs: negligible or no cost.
