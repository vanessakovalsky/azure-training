# Module 04 — Solutions

Examples given for trainee 07 (`NN=07`, `OCT=7`). All solutions assume the exercises' variable block has been run in Cloud Shell (Bash).

## Lab 04.1 ⭐ — Address plan and hub-spoke networks

### Solution
Address plan for trainee 07:

| Network or subnet | Range | Assignable addresses |
|---|---|---|
| `vnet-st07-hub` | `10.7.0.0/22` | 1,024 addresses to split (no reservation at VNet level) |
| `GatewaySubnet` | `10.7.0.0/27` | 32 − 5 = 27 |
| `AzureFirewallSubnet` | `10.7.0.64/26` | 64 − 5 = 59 |
| `AzureFirewallManagementSubnet` | `10.7.0.128/26` | 59 |
| `AzureBastionSubnet` | `10.7.1.0/26` | 59 |
| `snet-shared` | `10.7.2.0/24` | 251 |
| `vnet-st07-spoke-app` / `snet-web` / `snet-app` | `10.7.4.0/22` / `10.7.4.0/24` / `10.7.5.0/24` | 251 + 251 (reserve `10.7.6.0/23`) |
| `vnet-st07-spoke-data` / `snet-data` / `snet-pe` | `10.7.8.0/22` / `10.7.8.0/24` / `10.7.9.0/24` | 251 + 251 (reserve `10.7.10.0/23`) |
| Trainee's Lyon subnet | `10.200.7.0/24` | 251 |

Commands: those of the lab steps, unchanged.

### Why
- One /22 per network: 4 /24s per VNet, 2 of them kept as growth reserve; blocks `10.NN.0.0/22`, `10.NN.4.0/22`, `10.NN.8.0/22` are aligned (start address a multiple of 4 on the third octet), a condition for a valid /22 prefix.
- Second octet = trainee number: no overlap between trainees, none with Lyon (`10.200.0.0/16`), range readable at a glance in logs.
- Hub created by the gateway script with ALL its subnets: a gateway being provisioned locks VNet changes for 30 to 45 min.
- `$((10#$NN))`: Bash reads `07` in base 10 (without `10#`, `08` and `09` are invalid octal numbers) and drops the leading zero, rejected by Azure in an IP address.
- `check-ip-address`: `.0` to `.3` and `.255` reserved in a /24 (network, default gateway, two Azure DNS addresses, broadcast); first assignable address `.4`.
- Standard public IP + `--zone 1 2 3`: zone-redundant, required by `AZ` gateway SKUs and recommended everywhere else; deleted right away because it is billed hourly, even unused.
- Test VMs with no public IP and no NIC NSG: no inbound access from the Internet, filtering carried only by the subnet NSGs of exercise 04.2, tests through `run-command` (Azure agent channel, not the network).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `InvalidAddressPrefixFormat` or address `10.07.4.0` | Variable `NN` used instead of `OCT` | Use `10.${OCT}...`; check `echo $OCT` |
| `bash: 10#08: value too great for base` | `$((NN))` syntax without `10#` | `OCT=$((10#$NN))` |
| `NetcfgInvalidSubnet` / `InvalidCIDRNotation` | Unaligned prefix (e.g. `10.7.5.0/22`) | Block start a multiple of its size: `10.7.4.0/22` |
| `NetcfgSubnetRangesOverlap` | Subnet overlapping another one in the same VNet | Compare with `az network vnet subnet list` |
| `RequestDisallowedByPolicy` on the VNet or the public IP | `--tags` forgotten or region not allowed (M2) | Add `--tags $TAGS`, check `LOC` |
| Gateway script fails on `vnet-gateway create`: quota or `PublicIPCountLimitReached` | Public IP or gateway quota of the shared subscription | Tell the trainer (quota request D-10) |
| `test-vms.sh`: `RequestDisallowedByPolicy` on a disk | Implicit OS disk created without tags, M2 "required tag" policy in deny mode | Trainer: exclude `Microsoft.Compute/disks` or use the "inherit tag from resource group" effect |
| `SkuNotAvailable` for the test VMs | Size unavailable in France Central or vCPU quota reached | `VM_SIZE=Standard_F1als_v7 ./scripts/labs/module-04/test-vms.sh $NN` or `VM_SIZE=Standard_F1alds_v7 …` depending on availability (the script picks automatically based on NN) |
| `--tags $TAGS` creates a single `Projet` tag holding the whole text | Variable in quotes (`"$TAGS"`) | Leave `$TAGS` unquoted (split into three pairs) |

## Exercise 04.2 ⭐⭐ — Filtering with NSGs and ASGs

### Solution
```bash
# 1. Web subnet NSG
az network nsg create -g "$RG_SPOKE" -n "nsg-${ST}-web" -l "$LOC" --tags $TAGS -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-web" \
  -n Allow-HTTP-HTTPS-Inbound --priority 100 --direction Inbound \
  --access Allow --protocol Tcp --destination-port-ranges 80 443 -o none
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
  -n snet-web --network-security-group "nsg-${ST}-web" -o none

# 2. ASG and data VM NIC
az network asg create -g "$RG_SPOKE" -n "asg-${ST}-data" -l "$LOC" --tags $TAGS -o none
az network nic ip-config update -g "$RG_SPOKE" --nic-name "nic-${ST}-test-data" \
  -n ipconfig1 --application-security-groups "asg-${ST}-data" -o none

# 3. Data subnet NSG
az network nsg create -g "$RG_SPOKE" -n "nsg-${ST}-data" -l "$LOC" --tags $TAGS -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-data" \
  -n Allow-SQL-From-Web --priority 100 --direction Inbound --access Allow \
  --protocol Tcp --source-address-prefixes "10.${OCT}.4.0/24" \
  --destination-asgs "asg-${ST}-data" --destination-port-ranges 1433 -o none
az network nsg rule create -g "$RG_SPOKE" --nsg-name "nsg-${ST}-data" \
  -n Deny-VNet-Inbound --priority 4000 --direction Inbound --access Deny \
  --protocol '*' --source-address-prefixes VirtualNetwork \
  --destination-address-prefixes '*' --destination-port-ranges '*' -o none
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
  -n snet-data --network-security-group "nsg-${ST}-data" -o none

# 4. Effective inbound rules
az network nic list-effective-nsg -g "$RG_SPOKE" -n "nic-${ST}-test-data" \
  --query "value[0].effectiveSecurityRules[?direction=='Inbound'].{Name:name, Prio:priority, Access:access}" \
  -o table
```
Expected output (step 4):
```
Name                                                Prio    Access
--------------------------------------------------  ------  --------
securityRules/Allow-SQL-From-Web                    100     Allow
securityRules/Deny-VNet-Inbound                     4000    Deny
defaultSecurityRules/AllowVnetInBound               65000   Allow
defaultSecurityRules/AllowAzureLoadBalancerInBound  65001   Allow
defaultSecurityRules/DenyAllInBound                 65500   Deny
```

IP flow verify (step 5):
```bash
test_flow() {   # test_flow <SOURCE_IP> <DESTINATION_PORT>
  az network watcher test-ip-flow -g "$RG_SPOKE" --vm "vm-${ST}-test-data" \
    --direction Inbound --protocol TCP \
    --local "10.${OCT}.8.10:$2" --remote "$1:50000" \
    --query "[access, ruleName]" -o tsv | paste -sd' '
}
test_flow "10.${OCT}.4.10" 1433   # case a
test_flow "10.${OCT}.5.20" 1433   # case b
test_flow "10.${OCT}.4.10" 22     # case c
test_flow "10.${OCT}.9.20" 1433   # case d
```
Expected output (20 to 40 s per test):
```
Allow securityRules/Allow-SQL-From-Web
Deny defaultSecurityRules/DenyAllInBound
Deny defaultSecurityRules/DenyAllInBound
Deny securityRules/Deny-VNet-Inbound
```

Expected explanation (step 6): without peering, the `VirtualNetwork` tag of NIC `nic-st07-test-data` only contains the data spoke address space (`10.7.8.0/22`). Sources `10.7.4.10` and `10.7.5.20` are not in it: neither `Deny-VNet-Inbound` nor `AllowVnetInBound` applies, so default rule `DenyAllInBound` decides. Source `10.7.9.20` belongs to the same VNet: without the explicit priority 4000 rule, `AllowVnetInBound` (65000) would have ALLOWED it.

### Why
- NSG at subnet level: one rule covers every current and future VM of the subnet; no NIC NSG, so a single evaluation point.
- Destination as an ASG, source as an IP range: all NICs of an ASG must be in the same VNet, and a rule using ASGs as both source AND destination requires NICs in a single VNet. Web and data live in two different spokes.
- `Deny-VNet-Inbound` at priority 4000: below business allow rules (100 to 3999), above default rules (65000+); it neutralizes `AllowVnetInBound`, too broad for a data subnet.
- No "deny all from Internet" rule: already ensured by `DenyAllInBound`; `AllowAzureLoadBalancerInBound` kept for health probes (M7).
- `list-effective-nsg`: merged view of subnet and NIC NSGs, as enforced by the platform; requires a running VM.
- IP flow verify: logical test on the platform side, without a real packet; it names the deciding rule, which a failing `curl` never does.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `SecurityRuleInvalidAddressPrefix` / ASG rejected | ASG from another VNet used as source and destination | Source as IP range `10.<OCT>.4.0/24` |
| `ApplicationSecurityGroupsNotInSameVnet` `[TO VERIFY]` wording | NIC from another VNet added to `asg-stNN-data` | Remove the NIC; one ASG = one VNet |
| `list-effective-nsg`: `NetworkInterfaceNotAttachedToVM` or stopped VM error | VM deallocated or still being created | `az vm start` or wait for `VM running` |
| `test-ip-flow`: `AuthorizationFailed` on `NetworkWatcherRG` | Missing Network Watcher permissions | Trainer: Network Contributor role on `NetworkWatcherRG` |
| `test-ip-flow`: `NetworkWatcherNotFound` | Network Watcher not enabled in France Central | Trainer: `az network watcher configure -g NetworkWatcherRG -l francecentral --enabled true` |
| Case d decided by `AllowVnetInBound` | Rule `Deny-VNet-Inbound` missing, set as `Outbound` or with a source other than `VirtualNetwork` | `az network nsg rule list -g $RG_SPOKE --nsg-name nsg-$ST-data -o table` |
| `Rule name ... already exists` on rerun | Script replayed | Harmless: `rule create` on an existing name updates the rule `[TO VERIFY]` depending on the CLI version |

### Acceptable variants
- Deny rule with destination `asg-stNN-data` instead of `*`: equivalent today, but less protective if a VM without the ASG is added to the subnet.
- NSG created with Bicep: preferable in production (consistent with M3), longer to write in the allotted time.
- `--destination-port-ranges 80 443` replaced by two separate rules: correct, but two priorities to manage.

## Exercise 04.3 ⭐⭐ — Firewall, peerings and routes

### Solution
```bash
# 1. Firewall deployment (before the lecture)
az deployment group create -g "$RG_HUB" -n firewall \
  -f scripts/labs/module-04/firewall.bicep -p numero="$NN" --no-wait

# 2. Peerings
HUB_ID=$(az network vnet show -g "$RG_HUB" -n "vnet-${ST}-hub" --query id -o tsv)
APP_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" --query id -o tsv)
DATA_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-data" --query id -o tsv)

az network vnet peering create -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-app --remote-vnet "$APP_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
az network vnet peering create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
  -n peer-spoke-app-to-hub --remote-vnet "$HUB_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
az network vnet peering create -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-data --remote-vnet "$DATA_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
az network vnet peering create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
  -n peer-spoke-data-to-hub --remote-vnet "$HUB_ID" \
  --allow-vnet-access --allow-forwarded-traffic --query peeringState -o tsv
```
Expected output:
```
Initiated
Connected
Initiated
Connected
```

Test before routing (step 3):
```bash
az vm run-command invoke -g "$RG_SPOKE" -n "vm-${ST}-test-web" \
  --command-id RunShellScript \
  --scripts "curl -s -m 5 http://10.${OCT}.8.10:1433 || echo ECHEC" \
  --query "value[0].message" -o tsv
```
Expected output:
```
Enable succeeded: 
[stdout]
ECHEC

[stderr]
```

End of deployment and firewall IP (step 4):
```bash
az deployment group wait --created -g "$RG_HUB" -n firewall
FW_IP=$(az deployment group show -g "$RG_HUB" -n firewall \
  --query properties.outputs.firewallPrivateIp.value -o tsv)
echo "$FW_IP"
```
Expected output:
```
10.7.0.68
```

Route tables (step 5):
```bash
for spoke in app data; do
  az network route-table create -g "$RG_SPOKE" -n "rt-${ST}-spoke-${spoke}" -l "$LOC" \
    --disable-bgp-route-propagation true --tags $TAGS -o none
  az network route-table route create -g "$RG_SPOKE" \
    --route-table-name "rt-${ST}-spoke-${spoke}" -n default-via-fw \
    --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance \
    --next-hop-ip-address "$FW_IP" -o none
done
for subnet in snet-web snet-app; do
  az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
    -n "$subnet" --route-table "rt-${ST}-spoke-app" -o none
done
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-data" \
  -n snet-data --route-table "rt-${ST}-spoke-data" -o none
```

Effective routes and next hop (step 6):
```bash
az network nic show-effective-route-table -g "$RG_SPOKE" -n "nic-${ST}-test-web" \
  --query "value[?state=='Active' && nextHopType!='None'].{Source:source, Prefix:addressPrefix[0], Hop:nextHopType, IP:nextHopIpAddress[0]}" \
  -o table
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.${OCT}.8.10" \
  --query "{Hop:nextHopType, IP:nextHopIpAddress}" -o table
```
Expected output:
```
Source    Prefix       Hop               IP
--------  -----------  ----------------  ---------
Default   10.7.4.0/22  VnetLocal
Default   10.7.0.0/22  VNetPeering
User      0.0.0.0/0    VirtualAppliance  10.7.0.68

Hop               IP
----------------  ---------
VirtualAppliance  10.7.0.68
```

The step 7 test (same command as step 3) still returns `ECHEC`.

Answers to the Bicep reading questions (step 1):
- Resources: `pip-stNN-fw`, `pip-stNN-fw-mgmt`, policy `afwp-stNN-hub` (Basic tier), firewall `afw-stNN-hub`; the hub VNet is only referenced (`existing`).
- Two public IPs: one for traffic (outbound SNAT, inbound DNAT), the other for service management by the platform, required by the Basic tier.
- `ipConfigurations` → `AzureFirewallSubnet`; `managementIpConfiguration` → `AzureFirewallManagementSubnet`.
- Policy empty when created: NO flow allowed (implicit deny).

Expected failure causes:
- Step 3: no route to `10.7.8.0/22` in the app spoke (peering is not transitive); the packet follows system route `10.0.0.0/8` → `None` and is dropped before even leaving the spoke.
- Step 7: the packet reaches the firewall (`VirtualAppliance` hop), which denies it for lack of a matching rule.

### Why
- Firewall deployment launched before the lecture: 5 to 15 min of provisioning absorbed by the theory.
- Peering = two objects: each VNet declares its side; `Initiated` signals a link without its counterpart, `Connected` a complete link.
- `--allow-forwarded-traffic` on the spoke side: traffic coming from the other spoke arrives with a source address outside the hub; without this setting, the spoke rejects it. On the hub side, useful for the return of relayed flows.
- `--allow-vnet-access`: allows direct hub ↔ spoke communication (firewall ↔ VMs).
- No gateway option (`--allow-gateway-transit`, `--use-remote-gateways`) at this point: handled in M5 with the VPN link.
- One table per spoke, single `0.0.0.0/0` route: covers the Internet AND the other spoke (absent from system routes); intra-spoke traffic stays on `VnetLocal`, a longer prefix.
- Table associated with BOTH spokes: symmetric routing; a single table would produce a return path outside the firewall, dropped by its connection tracking.
- BGP propagation disabled: in M5, Lyon routes learned by the gateway will not reach the spokes; traffic to Lyon will follow the `0.0.0.0/0` route, hence the firewall.
- Reserved `None` routes (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`): marked `Invalid` when a `0.0.0.0/0` UDR exists `[TO VERIFY]` state label; hence the `nextHopType!='None'` filter for a readable display.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Hub-side `peering create`: `AnotherOperationInProgress` or `ReferencedResourceNotProvisioned` | VPN gateway still `Updating` | Wait for `Succeeded` (`az network vnet-gateway show ... --query provisioningState`), then rerun |
| `RemoteVnetHasOverlappingAddressSpace` / overlap | Spoke range identical to the hub (`OCT` error) | Fix the spoke range (delete and recreate) |
| `peeringState` stays `Initiated` | Reverse link not created, or created with a wrong ID | `az network vnet peering list` on both sides |
| `az deployment group wait` never returns | Deployment failed or still running | `az deployment group show -g ... -n firewall --query properties.provisioningState`; on failure, `--query properties.error` |
| Firewall deployment: `AzureFirewallManagementSubnet` not found | Hub created by hand or by an older script | Rerun `./scripts/prereq-vpn-gateways.sh $NN` (idempotent, adds missing subnets) |
| `FW_IP` empty | Deployment not finished or variable lost (session closed) | Rerun `az deployment group show ... --query properties.outputs.firewallPrivateIp.value -o tsv` |
| `run-command`: `Conflict` or very long run | A `run-command` is already running on the VM | Wait for the previous one (one at a time per VM) |
| `show-effective-route-table`: stopped VM error | VM deallocated | `az vm start -g $RG_SPOKE -n vm-$ST-test-web` |

### Acceptable variants
- Peerings and route tables in Bicep: recommended in production; this is the approach of the catch-up script `scripts/catch-up/module-04/`.
- Specific routes to the other spoke (`10.<OCT>.8.0/22` → firewall) on top of `0.0.0.0/0`: more explicit, no different effect here.
- Peering created in the portal: a single operation creates both links; acceptable, but not reproducible.

## Challenge 04.4 ⭐⭐⭐ — Firewall rules as IaC

### Solution
File `firewall-rules.bicep` (identical to `scripts/catch-up/module-04/firewall-rules.bicep`, whose comments are in French; collection and rule names are kept as is):
```bicep
// firewall-rules.bicep — Arvéo firewall rules (challenge 04.4 solution)
// Adds rule collection group rcg-arveo to the existing policy afwp-stNN-hub.
targetScope = 'resourceGroup'

@description('Two-digit trainee number')
@minLength(2)
@maxLength(2)
param numero string

@description('FQDNs allowed outbound from the spokes (HTTP and HTTPS)')
param allowedFqdns array = [
  '*.ubuntu.com'
]

var prefix = 'st${numero}'
var octet = int(numero)
var webSubnet = '10.${octet}.4.0/24'
var dataSubnet = '10.${octet}.8.0/24'
var spokeApp = '10.${octet}.4.0/22'
var spokeData = '10.${octet}.8.0/22'

resource policy 'Microsoft.Network/firewallPolicies@2023-11-01' existing = {
  name: 'afwp-${prefix}-hub'
}

resource rcg 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: policy
  name: 'rcg-arveo'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-reseau-autoriser'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'web-vers-data-sql'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              webSubnet
            ]
            destinationAddresses: [
              dataSubnet
            ]
            destinationPorts: [
              '1433'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-application-autoriser'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'spokes-vers-depots-ubuntu'
            sourceAddresses: [
              spokeApp
              spokeData
            ]
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: allowedFqdns
          }
        ]
      }
    ]
  }
}
```

Check, preview, deploy:
```bash
az bicep build --file firewall-rules.bicep --stdout > /dev/null && echo "Syntax OK"
az deployment group what-if -g "$RG_HUB" -f firewall-rules.bicep -p numero="$NN"
az deployment group create -g "$RG_HUB" -n firewall-rules \
  -f firewall-rules.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
```
Expected `what-if` output (end):
```
  + Microsoft.Network/firewallPolicies/afwp-st07-hub/ruleCollectionGroups/rcg-arveo [2023-11-01]

Resource changes: 1 to create.
```
Then `Succeeded` after 2 to 5 min (update of the associated firewall).

Matrix tests:
```bash
run_on() {   # run_on <web|data> "<COMMAND>": shows standard output only
  az vm run-command invoke -g "$RG_SPOKE" -n "vm-${ST}-test-$1" \
    --command-id RunShellScript --scripts "$2" \
    --query "value[0].message" -o tsv | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'
}
run_on web  "curl -s -m 5 http://10.${OCT}.8.10:1433 || echo ECHEC"                     # a
run_on data "curl -s -m 5 http://10.${OCT}.4.10 || echo ECHEC"                          # b
run_on web  "curl -s -o /dev/null -w '%{http_code}' -m 10 http://azure.archive.ubuntu.com/ubuntu/"  # c
run_on web  "curl -s -o /dev/null -w '%{http_code}' -m 10 http://www.example.com"       # d
run_on web  "curl -s -o /dev/null -w '%{http_code}' -m 10 https://www.example.com || echo ' ECHEC'" # e
```
Expected output (an empty line may follow each result):
```
vm-st07-test-data
ECHEC
200
470
000 ECHEC
```

Expected explanation (step 4): over HTTP, the firewall reads the `Host` header in clear text and answers itself with an HTTP 470 error page ("Action: Deny", `[TO VERIFY]` exact wording). Over HTTPS, it only sees the SNI name of the TLS handshake; without TLS inspection (Premium only), it cannot answer with an HTTP page and resets the connection: `curl` gets no code (`000`).

### Why
- `existing` on the policy: the file only owns its rule collection group; no risk of overwriting the tier (`Basic`) or another group.
- Ranges computed with `int(numero)`: same file for every trainee, no address typed for a given trainee (same logic as M3 `socle.bicep`).
- Network (200) and application (300) collections in a single group: readability; priority 100 left free for a DNAT collection (bonus 1).
- Network rule for SQL (TCP 1433 is not HTTP); application rule for Ubuntu repositories (FQDN filtering, impossible in a network rule with the Basic tier: no DNS proxy).
- No explicit deny rule: the firewall implicit deny covers the "any other site" line and the data → web flow; a deny rule would only help with named logging.
- `*.ubuntu.com`: covers `azure.archive.ubuntu.com` and `security.ubuntu.com` (updates of the M7 VMs).
- NSG `nsg-stNN-data` still applies after the firewall: test a succeeds because the source seen by the VM is still `10.<OCT>.4.10` (no SNAT for private destinations), matching `Allow-SQL-From-Web`.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `BCP035` / `BCP037` on `ruleCollections` | Misplaced property (`rules` outside the collection, missing `ruleType`) | VS Code completion; compare with the solution structure |
| `FirewallPolicyRuleCollectionGroupInvalidPriority` or priority < 100 | Priority outside 100 to 65000 | Priorities ≥ 100 |
| Deployment `Conflict` / `AnotherOperationInProgress` | Firewall still updating (previous deployment) | Wait 2 to 5 min, rerun |
| Test a: `ECHEC` although the rule exists | NSG `nsg-stNN-data` without `Allow-SQL-From-Web`, or ASG not attached to the NIC | IP flow verify (exercise 04.2), check the ASG of `nic-stNN-test-data` |
| Test c: `470` | FQDN mistyped (`ubuntu.com` without `*.`) or source outside the ranges | Check `targetFqdns` and `sourceAddresses` |
| Test c: `000` (timeout) | Route table not associated with `snet-web`, or VM DNS unavailable | `show-effective-route-table`; `run_on web "getent hosts azure.archive.ubuntu.com"` |
| Test b: response `vm-stNN-test-web` | Network rule too broad (source `10.<OCT>.0.0/16` or ports `*`) | Narrow source, destination and port |
| `what-if` after redeployment: `~` on undeclared properties | Default values added by the platform | Acceptable noise if no rule changes |

### Acceptable variants
- Rules created with Azure CLI (`az network firewall policy rule-collection-group create`, then `collection add-filter-collection`, `azure-firewall` extension): correct, but outside the IaC constraint.
- IP groups (`Microsoft.Network/ipGroups`) as source and destination: more readable at scale, one more resource.
- FQDN tag `WindowsUpdate` or business FQDN list in a `.bicepparam` file: good practice to separate rules and per-environment values.
- Explicit deny collection (priority 4000) to log forbidden flows by name: valid.

## Exercise 04.5 ⭐⭐ — Private and public DNS zones

### Solution
```bash
HUB_ID=$(az network vnet show -g "$RG_HUB" -n "vnet-${ST}-hub" --query id -o tsv)
APP_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-app" --query id -o tsv)
DATA_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-data" --query id -o tsv)

# 1. Private zone and links
az network private-dns zone create -g "$RG_HUB" -n arveo.internal --tags $TAGS -o none
az network private-dns link vnet create -g "$RG_HUB" -z arveo.internal \
  -n link-hub -v "$HUB_ID" --registration-enabled false --tags $TAGS -o none
az network private-dns link vnet create -g "$RG_HUB" -z arveo.internal \
  -n link-spoke-app -v "$APP_ID" --registration-enabled true --tags $TAGS -o none
az network private-dns link vnet create -g "$RG_HUB" -z arveo.internal \
  -n link-spoke-data -v "$DATA_ID" --registration-enabled true --tags $TAGS -o none

# 2. Manual record
az network private-dns record-set a add-record -g "$RG_HUB" -z arveo.internal \
  -n sql -a "10.${OCT}.8.10" -o none

# 3. Check
az network private-dns record-set list -g "$RG_HUB" -z arveo.internal \
  --query "[].{Name:name, IP:aRecords[0].ipv4Address, Auto:isAutoRegistered}" -o table
```
Expected output (step 3, auto-registration within 1 to 2 min):
```
Name               IP         Auto
-----------------  ---------  ------
@                             False
sql                10.7.8.10  False
vm-st07-test-data  10.7.8.10  True
vm-st07-test-web   10.7.4.10  True
```

Resolution from the web VM (step 4, `run_on` function from challenge 04.4):
```bash
run_on web "getent hosts sql.arveo.internal vm-${ST}-test-data.arveo.internal; \
curl -s -m 5 http://sql.arveo.internal:1433"
```
Expected output:
```
10.7.8.10       sql.arveo.internal
10.7.8.10       vm-st07-test-data.arveo.internal
vm-st07-test-data
```

Public zone (steps 5 and 6):
```bash
az network dns zone create -g "$RG_HUB" -n "arveo-${ST}.fr" --tags $TAGS -o none
FW_PIP=$(az network public-ip show -g "$RG_HUB" -n "pip-${ST}-fw" --query ipAddress -o tsv)
az network dns record-set a add-record -g "$RG_HUB" -z "arveo-${ST}.fr" \
  -n www -a "$FW_PIP" -o none
NS1=$(az network dns zone show -g "$RG_HUB" -n "arveo-${ST}.fr" \
  --query "nameServers[0]" -o tsv)
echo "$NS1 / $FW_PIP"
dig +short @"$NS1" "www.arveo-${ST}.fr"
dig "www.arveo-${ST}.fr" | grep -o 'status: [A-Z]*'
```
Expected output (servers and address specific to each zone):
```
ns1-XX.azure-dns.com. / <FIREWALL_PUBLIC_IP>
<FIREWALL_PUBLIC_IP>
status: NXDOMAIN
```

Expected explanation (step 7): the zone's Azure server is authoritative for `arveo-st07.fr` and answers. A regular resolver starts at the root, then the `.fr` servers; no delegation there points to Azure (domain neither bought nor delegated): the answer is `NXDOMAIN`. To publish for real, declare the four Azure NS servers at the domain registrar.

### Why
- Zone in the hub: shared resource, managed once, linked to every VNet; consistent with the hub-spoke model.
- Hub without auto-registration: no VM in M4; later, a VNet can auto-register in ONE zone only.
- `sql` registered by hand: service name, independent from the VM name; when the server is replaced, only the record changes.
- Spoke auto-registration: DNS inventory kept up to date with no action; the record disappears with the VM.
- `.internal`: top-level domain reserved for private use, never delegated on the Internet, unlike a made-up `.local` or `.com` name.
- Resolution through `168.63.129.16`: not affected by the `0.0.0.0/0` route to the firewall (platform address); no firewall rule needed for DNS.
- Test `curl http://sql.arveo.internal:1433` crosses the firewall: it proves the DNS, the challenge 04.4 network rule and the exercise 04.2 NSG at once.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `getent hosts` returns nothing | Link missing to the VM's VNet, or link still `InProgress` | `az network private-dns link vnet list ... -o table`; wait for `Completed` |
| VMs missing from the zone | Spoke links created with `--registration-enabled false` | `az network private-dns link vnet update ... --registration-enabled true` |
| `A virtual network can be linked to only one zone with registration` `[TO VERIFY]` wording | Spoke already linked with auto-registration to another zone | Disable auto-registration on the other link |
| `RequestDisallowedByPolicy` on the zone or a link | Missing tags (zones and links are taggable resources) | `--tags $TAGS` on every creation |
| `dig: command not found` | Tool missing from the day's Cloud Shell image | `nslookup www.arveo-<NN>.fr <SERVER>` |
| `dig @<SERVER>`: timeout | Outbound port 53 filtered from the trainee's network (Cloud Shell not affected) | Run the command in Cloud Shell |
| `curl http://sql.arveo.internal:1433`: `ECHEC` while resolution works | Challenge 04.4 network rule missing | Deploy `firewall-rules.bicep` or the catch-up script |

### Acceptable variants
- CNAME record `sql` → `vm-stNN-test-data.arveo.internal`: valid, follows the VM address automatically, but ties the service name to the VM name.
- Alias record (`--target-resource`) for `www` to the firewall public IP: recommended in production (updated if the IP changes), not supported in private zones.
- One private zone per spoke: possible, but multiplies links and breaks cross-resolution; avoid.

## Bonus

### 1. DNAT publishing
Add to `ruleCollections` of `firewall-rules.bicep`, before the other collections, and declare the existing public IP:
```bicep
resource pipFw 'Microsoft.Network/publicIPAddresses@2023-11-01' existing = {
  name: 'pip-${prefix}-fw'
}
```
```bicep
      {
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        name: 'rc-dnat-web'
        priority: 100
        action: {
          type: 'DNAT'
        }
        rules: [
          {
            ruleType: 'NatRule'
            name: 'web-http-8080'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              '*'
            ]
            destinationAddresses: [
              pipFw.properties.ipAddress
            ]
            destinationPorts: [
              '8080'
            ]
            translatedAddress: '10.${octet}.4.10'
            translatedPort: '80'
          }
        ]
      }
```
```bash
az deployment group create -g "$RG_HUB" -n firewall-rules \
  -f firewall-rules.bicep -p numero="$NN" --query properties.provisioningState -o tsv
curl -s -m 10 "http://${FW_PIP}:8080"
```
Expected output:
```
Succeeded
vm-st07-test-web
```
The web VM reply follows the `0.0.0.0/0` route to the firewall (symmetric routing); NSG `nsg-stNN-web` allows port 80 from any source. Remove the collection (redeploy without it) after the test: the public IP exposes the VM.

### 2. VirtualNetwork tag after the UDRs
```bash
test_flow "10.${OCT}.5.20" 1433
```
Expected output:
```
Deny securityRules/Deny-VNet-Inbound
```
Case b is now decided by `Deny-VNet-Inbound`: the `VirtualNetwork` tag includes UDR prefixes, here `0.0.0.0/0`, and therefore covers any address `[TO VERIFY]` behavior observed in the tenant. Consequence: `AllowVnetInBound` would also allow any traffic arriving through the firewall; hence the value of the explicit deny rule.

### 3. Intra-spoke traffic
```bash
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.${OCT}.5.20" \
  --query "{Hop:nextHopType, IP:nextHopIpAddress}" -o table
```
Expected output:
```
Hop        IP
---------  ----
VnetLocal
```
Prefix `10.<OCT>.4.0/22` (`VnetLocal`) is longer than `0.0.0.0/0`: traffic between `snet-web` and `snet-app` does NOT go through the firewall; only NSGs filter it. To force it through, add a route `10.<OCT>.5.0/24` → firewall in the `snet-web` table (and the reverse).

## QCM — Answers
1. **C** — 32 addresses minus 5 reserved by Azure (network, gateway, two DNS, broadcast) = 27.
2. **B** — `AzureFirewallSubnet` is mandatory (/26); `AzureFirewallManagementSubnet` is added for the Basic tier.
3. **B** — The rule with the lowest priority is evaluated first and the first match applies.
4. **A** — All NICs of an ASG must belong to the same virtual network.
5. **B** — Peering is not transitive: a UDR to a hub appliance (firewall) is required.
6. **B** — The longest prefix wins: `10.7.4.0/22` (VnetLocal) before `0.0.0.0/0`.
7. **C** — Azure Firewall processes DNAT rules, then network rules, then application rules.
8. **B** — Azure Firewall denies by default any flow without a matching rule.
9. **B** — A private zone is only resolved in the VNets linked to it.
10. **B** — Without BGP propagation, VPN routes do not reach the spokes: traffic stays forced to the firewall.
