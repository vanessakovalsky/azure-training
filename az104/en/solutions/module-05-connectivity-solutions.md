# Module 05 — Solutions

Examples given for trainee 07 (`NN=07`, `OCT=7`). All solutions assume the exercise variable block has been run in Cloud Shell (Bash), `tester` and `lyon` functions included.

## Lab 05.1 ⭐⭐ — Gateway transit and global peering

### Solution
```bash
# 1. Gateway and initial state of the hub links
az network vnet-gateway show -g "$RG_HUB" -n "vpngw-${ST}-hub" --query provisioningState -o tsv
az network vnet peering list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  --query "[].{Name:name, State:peeringState, Access:allowVirtualNetworkAccess, Forwarded:allowForwardedTraffic, Transit:allowGatewayTransit, Remote:useRemoteGateways}" \
  -o table
```
Expected output:
```
Succeeded
Name                    State      Access    Forwarded    Transit    Remote
----------------------  ---------  --------  -----------  ---------  --------
peer-hub-to-spoke-app   Connected  True      True         False      False
peer-hub-to-spoke-data  Connected  True      True         False      False
```

```bash
# 2. Gateway transit: hub links, THEN spoke links
for spoke in app data; do
  az network vnet peering update -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
    -n "peer-hub-to-spoke-${spoke}" --set allowGatewayTransit=true -o none
done
for spoke in app data; do
  az network vnet peering update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
    -n "peer-spoke-${spoke}-to-hub" --set useRemoteGateways=true -o none
done

# 3. DR spoke in North Europe
az network vnet create -g "$RG_SPOKE" -n "vnet-${ST}-spoke-pra" -l northeurope \
  --address-prefixes "10.${OCT}.12.0/23" \
  --subnet-name snet-pra --subnet-prefixes "10.${OCT}.12.0/24" \
  --tags $TAGS -o none

# 4. Hub ↔ DR global peering
HUB_ID=$(az network vnet show -g "$RG_HUB" -n "vnet-${ST}-hub" --query id -o tsv)
PRA_ID=$(az network vnet show -g "$RG_SPOKE" -n "vnet-${ST}-spoke-pra" --query id -o tsv)
az network vnet peering create -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-pra --remote-vnet "$PRA_ID" \
  --allow-vnet-access --allow-forwarded-traffic --allow-gateway-transit \
  --query peeringState -o tsv
az network vnet peering create -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-pra" \
  -n peer-spoke-pra-to-hub --remote-vnet "$HUB_ID" \
  --allow-vnet-access --allow-forwarded-traffic --use-remote-gateways \
  --query peeringState -o tsv
```
Expected output (step 4):
```
Initiated
Connected
```

```bash
# 5. Link check
az network vnet peering list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  --query "[].{Name:name, State:peeringState, Sync:peeringSyncLevel, Transit:allowGatewayTransit}" \
  -o table
for spoke in app data pra; do
  az network vnet peering show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
    -n "peer-spoke-${spoke}-to-hub" --query "[name, useRemoteGateways]" -o tsv
done
```
Expected output:
```
Name                    State      Sync         Transit
----------------------  ---------  -----------  ---------
peer-hub-to-spoke-app   Connected  FullyInSync  True
peer-hub-to-spoke-data  Connected  FullyInSync  True
peer-hub-to-spoke-pra   Connected  FullyInSync  True
peer-spoke-app-to-hub   True
peer-spoke-data-to-hub  True
peer-spoke-pra-to-hub   True
```

```bash
# 6. Additional range and synchronization
az network vnet update -g "$RG_SPOKE" -n "vnet-${ST}-spoke-pra" \
  --address-prefixes "10.${OCT}.12.0/23" "10.${OCT}.14.0/23" -o none
az network vnet peering list -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  --query "[].{Name:name, Sync:peeringSyncLevel}" -o table
az network vnet peering show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-pra" \
  -n peer-spoke-pra-to-hub --query peeringSyncLevel -o tsv
az network vnet peering sync -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-pra -o none
az network vnet peering show -g "$RG_HUB" --vnet-name "vnet-${ST}-hub" \
  -n peer-hub-to-spoke-pra \
  --query "[peeringSyncLevel, join(' ', remoteAddressSpace.addressPrefixes)]" -o tsv
```
Expected output (labels of the out-of-sync states `[TO VERIFY]` on the current API):
```
Name                    Sync
----------------------  --------------
peer-hub-to-spoke-app   FullyInSync
peer-hub-to-spoke-data  FullyInSync
peer-hub-to-spoke-pra   LocalNotInSync
RemoteNotInSync
FullyInSync	10.7.12.0/23 10.7.14.0/23
```

```bash
# 7. Next hop to the DR spoke
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.${OCT}.12.4" \
  --query "{Hop:nextHopType, IP:nextHopIpAddress}" -o table
```
Expected output:
```
Hop               IP
----------------  ---------
VirtualAppliance  10.7.0.68
```

Expected answers (step 8):
- a. `useRemoteGateways` requires the opposite link to already allow transit (`allowGatewayTransit`) and a provisioned gateway in the remote VNet; in the reverse order, the platform rejects the spoke link update.
- b. No: the app spoke is peered with the hub only, peering is not transitive. Step 7 shows that the packet goes to the firewall (M4 `0.0.0.0/0` UDR); it will only pass if a firewall rule allows it, which is not the case (implicit deny).
- c. Thanks to gateway transit: the DR → hub link uses the hub gateway (`useRemoteGateways`), including over global peering; a gateway in the spoke would actually be incompatible with this option.

### Why
- Transit rather than one gateway per spoke: a single gateway billed and a single tunnel per remote site; the spoke ranges are known by the hub gateway.
- Options changed on existing links (`update`): no peering interruption, no recreation, the `Connected` state is kept.
- `--set` (generic update): acts directly on the ARM property (`allowGatewayTransit`, `useRemoteGateways`), same name as in Bicep.
- DR spoke in North Europe: paired region of France Central for a DR plan, allowed by the M2 region policy; range `10.<OCT>.12.0/23` inside the trainee's `10.<OCT>.0.0/20` block, already advertised to Lyon by the trainer (no change on the Lyon side).
- Range added as `/23` then `/23`: `10.<OCT>.12.0/22` from the start would have overlapped the second range; the list passed to `vnet update` is COMPLETE (existing ranges + new one).
- Synchronization on the hub link: this link keeps a copy of the remote address space (`remoteAddressSpace`); until it is updated, the new range is not routed from the hub.
- DR spoke without a route table: no VM to protect for now; symmetry with the firewall is covered in bonus 2 (table in the VNet's region).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Link update rejected: `AnotherOperationInProgress` or gateway `Updating` | Gateway still provisioning, or two updates launched in parallel | Wait for `Succeeded`, rerun the updates one at a time |
| `useRemoteGateways` rejected (`RemotePeeringDoesNotAllowGatewayTransit` `[TO VERIFY]` wording) | Hub link without `allowGatewayTransit`, or spoke link updated first | Update `peer-hub-to-spoke-*` first |
| `RequestDisallowedByPolicy` on `vnet-stNN-spoke-pra` | Tags forgotten, or North Europe missing from the M2 region policy | `--tags $TAGS`; otherwise tell the trainer |
| `peering create`: `VnetAddressSpacesOverlap` | Wrong `OCT`, DR range identical to another VNet | `echo $OCT`, recreate the VNet with `10.${OCT}.12.0/23` |
| `vnet update`: `NetcfgSubnetRangesOverlap` / `AddressPrefixesOverlap` | `/22` typed instead of `/23`, or old range left out of the list | Complete list: `10.<OCT>.12.0/23 10.<OCT>.14.0/23` |
| `az network vnet peering sync` unknown | Azure CLI too old (up-to-date Cloud Shell not affected) | `az upgrade`, or update the hub link in the portal ("Sync") |
| `show-next-hop`: `NetworkWatcherNotFound` | No Network Watcher in the VM's region | Trainer: `az network watcher configure -g NetworkWatcherRG -l <REGION> --enabled true` |

### Acceptable variants
- Peerings and options in Bicep (`allowGatewayTransit` and `useRemoteGateways` properties of `virtualNetworkPeerings` resources): recommended in production; this is the approach of the catch-up `scripts/catch-up/module-05/`.
- DR spoke created in a dedicated North Europe group: cleaner for a real DR plan (separate lifecycle); not provided by the shared-tenant isolation (six groups per trainee).
- Portal: the peering blade creates both links and sets the options on both sides at once; acceptable, not reproducible.

## Lab 05.2 ⭐⭐ — Site-to-site VPN tunnel to Lyon

### Solution
```bash
# 1. Lyon server (14:30)
./scripts/labs/module-05/lyon-vm.sh "$NN"

# 2. Public IPs and Lyon side (read-only)
LYON_IP=$(az network public-ip show -g "$RG_LYON" -n pip-lyon-vpngw --query ipAddress -o tsv)
HUB_PIP=$(az network public-ip show -g "$RG_HUB" -n "pip-${ST}-vpngw" --query ipAddress -o tsv)
echo "Lyon: ${LYON_IP} / Hub: ${HUB_PIP}"
az network local-gateway show -g "$RG_LYON" -n "lng-lyon-${ST}" \
  --query "{IP:gatewayIpAddress, Ranges:join(' ', localNetworkAddressSpace.addressPrefixes)}" \
  -o table
```
Expected output (addresses specific to each session):
```
Lyon: <LYON_IP> / Hub: <HUB_IP>
IP          Ranges
----------  -----------
<HUB_IP>    10.7.0.0/20
```
The `/20` (`10.7.0.0` to `10.7.15.255`) covers in a single range the hub (`/22`), the app and data spokes (`/22` each) and the DR spoke (`10.7.12.0/23` and `10.7.14.0/23`): no change on the Lyon side when Arvéo adds a network inside this block.

```bash
# 3. Local network gateway: the Lyon site as seen from the hub
az network local-gateway create -g "$RG_HUB" -n "lng-${ST}-lyon" -l "$LOC" \
  --gateway-ip-address "$LYON_IP" --local-address-prefixes "10.200.${OCT}.0/24" \
  --tags $TAGS -o none

# 4. IPsec connection (key typed without echo, kept out of the history)
read -r -s -p "Shared key: " PSK; echo
az network vpn-connection create -g "$RG_HUB" -n "cn-${ST}-hub-to-lyon" \
  --vnet-gateway1 "vpngw-${ST}-hub" --local-gateway2 "lng-${ST}-lyon" \
  --shared-key "$PSK" --tags $TAGS -o none

# 5. Tunnel establishment
for _ in $(seq 1 10); do
  STATE=$(az network vpn-connection show -g "$RG_HUB" -n "cn-${ST}-hub-to-lyon" \
    --query connectionStatus -o tsv)
  echo "$STATE"
  [[ "$STATE" == "Connected" ]] && break
  sleep 30
done
az network vpn-connection show -g "$RG_HUB" -n "cn-${ST}-hub-to-lyon" \
  --query "[connectionStatus, ingressBytesTransferred, egressBytesTransferred]" -o tsv
```
Expected output (number of `Connecting` lines and counters vary):
```
Connecting
Connected
Connected	2104	3388
```

```bash
# 6. Routes learned by the Lyon server
az network nic show-effective-route-table -g "$RG_LYON_ST" -n "nic-${ST}-lyon-fs" \
  --query "value[?nextHopType=='VirtualNetworkGateway'].{Prefix:addressPrefix[0], Hop:nextHopType}" \
  -o table
```
Expected output (one line per trainee connected on the Lyon side):
```
Prefix       Hop
-----------  ---------------------
10.7.0.0/20  VirtualNetworkGateway
10.8.0.0/20  VirtualNetworkGateway
```

```bash
# 7. Lyon → app spoke web server test
lyon "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://10.${OCT}.4.10).Content.Trim() } catch { 'ECHEC' }"

# 8. Next hops, outbound and return
az network watcher show-next-hop -g "$RG_LYON_ST" --vm "vm-${ST}-lyon-fs" \
  --source-ip "10.200.${OCT}.10" --dest-ip "10.${OCT}.4.10" --query nextHopType -o tsv
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-web" \
  --source-ip "10.${OCT}.4.10" --dest-ip "10.200.${OCT}.10" \
  --query "{Hop:nextHopType, IP:nextHopIpAddress}" -o table
```
Expected output:
```
ECHEC
VirtualNetworkGateway
Hop               IP
----------------  ---------
VirtualAppliance  10.7.0.68
```

Expected explanation (step 9):
- Outbound: `vm-st07-lyon-fs` → `vpngw-lyon` → tunnel → `vpngw-st07-hub`. Without a route table on `GatewaySubnet`, the gateway follows the `VNetPeering` system route to `10.7.4.0/22`: the packet reaches the web VM DIRECTLY, without crossing the firewall; `nsg-st07-web` allows it (port 80, any source).
- Return: the reply from `10.7.4.10` to `10.200.7.10` follows `rt-st07-spoke-app` (`0.0.0.0/0` → `10.7.0.68`) and reaches the firewall.
- Drop: the firewall receives a reply (SYN-ACK) for a connection it never saw; its connection tracking drops it. Moreover, no rule allows Lyon. Fix: challenge 05.3.

### Why
- Lyon server launched before the lecture: the 5 to 10 min Windows VM creation is absorbed by the theory.
- Local network gateway = description of THE OTHER end: public IP of its VPN device and ranges reachable behind it; on the Lyon side, the trainer symmetrically describes the trainee's hub.
- Range `10.200.<OCT>.0/24` and not `10.200.0.0/16`: only the trainee's subnet is advertised; the other trainees' servers are not routed to their hub.
- IPsec connection with IKEv2 (default) and default policy on both sides: negotiation succeeds without any cryptographic setting.
- Shared key: identical on both sides, typed with `read -s`; in production, randomly generated and stored in Azure Key Vault.
- `Connected` only when both connections exist and the keys match; byte counters prove that packets actually cross the tunnel (IKE probes included).
- Effective routes on the Lyon side: the Lyon gateway injects the ranges of each local network gateway (`10.<OCT>.0.0/20` per trainee) into every NIC of `vnet-lyon`.
- `show-next-hop` in both directions: the fastest tool to prove routing asymmetry, without generating traffic.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `lyon-vm.sh`: `snet-stNN introuvable` | Subnet not prepared by the trainer | Trainer: `lyon-site.sh prepare <NN>` |
| `lyon-vm.sh`: `AuthorizationFailed` on `subnets/join/action` | Network Contributor role missing on `snet-stNN` | Trainer: role assignment (same command); propagation up to 5 min |
| `RequestDisallowedByPolicy` on the NIC or the VM | `francecentral` missing from the `rg-stNN-lyon` region policy, or OS disk without tags | Trainer: M2 policy (see guide) |
| `SkuNotAvailable` for the Lyon VM | Size unavailable or vCPU quota reached in France Central | `VM_SIZE=Standard_D2as_v6 ./scripts/labs/module-05/lyon-vm.sh $NN` or `VM_SIZE=Standard_D2s_v6 …` depending on availability |
| Connection `NotConnected` after 5 min | Different key, wrong IP in `lng-stNN-lyon`, or `cn-lyon-to-stNN` missing | Compare `LYON_IP` and `gatewayIpAddress`; `lyon-site.sh status` (trainer); recreate the connection with the right key |
| Connection `Connected`, no Lyon routes in step 6 | Lyon VM stopped or still being created | `az vm list -g rg-stNN-lyon -d -o table`; wait for `VM running` |
| `lyon`: `Conflict` or very long run | `run-command` already running on the VM, or Windows agent not ready yet (first boot) | Wait 2 to 3 min, run a single command at a time |
| Step 7 succeeds (response `vm-stNN-test-web`) | `rt-stNN-spoke-app` missing on `snet-web` (incomplete M4 catch-up): direct path both ways | Re-associate the route table; challenge 05.3 assumes the M4 routing |

## Challenge 05.3 ⭐⭐⭐ — Lyon ↔ Arvéo hybrid flows as IaC

### Solution
File `lyon-connectivity.bicep` (identical to `scripts/catch-up/module-05/lyon-connectivity.bicep`, whose comments are in French; resource, collection and rule names are kept as is):
```bicep
// lyon-connectivity.bicep — Lyon ↔ Arvéo spokes hybrid flows (challenge 05.3 solution)
// Deployed into rg-stNN-hub. Prerequisite: end state of module 4 (firewall, policy, NSG/ASG).
//   - rt-stNN-gateway associated with GatewaySubnet: spokes → firewall (symmetric routing)
//   - rule collection group rcg-lyon in afwp-stNN-hub: Lyon → web (80, 443), Lyon → data (1433)
//   - rule Allow-SQL-From-Lyon in nsg-stNN-data (module lyon-nsg-rule.bicep, rg-stNN-spoke)
// Deployment: az deployment group create -g rg-stNN-hub -f lyon-connectivity.bicep -p numero=NN
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région du hub')
@allowed([ 'francecentral', 'westeurope' ])
param location string = 'francecentral'

var prefix = 'st${numero}'
var octet = int(numero)
var lyonSubnet = '10.200.${octet}.0/24'
var spokes = [
  {
    name: 'spoke-app-via-fw'
    prefix: '10.${octet}.4.0/22'
  }
  {
    name: 'spoke-data-via-fw'
    prefix: '10.${octet}.8.0/22'
  }
]
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: 'vnet-${prefix}-hub'
}

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' existing = {
  name: 'afw-${prefix}-hub'
}

resource policy 'Microsoft.Network/firewallPolicies@2023-11-01' existing = {
  name: 'afwp-${prefix}-hub'
}

var firewallPrivateIp = firewall.properties.ipConfigurations[0].properties.privateIPAddress

// ---------- Routing: GatewaySubnet → firewall ----------
resource rtGateway 'Microsoft.Network/routeTables@2023-11-01' = {
  name: 'rt-${prefix}-gateway'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false // mandatory on GatewaySubnet
    routes: [for spoke in spokes: {
      name: spoke.name
      properties: {
        addressPrefix: spoke.prefix
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: firewallPrivateIp
      }
    }]
  }
}

// Existing subnet redeclared as is, plus the route table
resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: hubVnet
  name: 'GatewaySubnet'
  properties: {
    addressPrefix: '10.${octet}.0.0/27'
    routeTable: {
      id: rtGateway.id
    }
  }
}

// ---------- Filtering: firewall ----------
resource rcgLyon 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  parent: policy
  name: 'rcg-lyon'
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'rc-lyon-autoriser'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-web'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.4.0/24'
            ]
            destinationPorts: [
              '80'
              '443'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-data-sql'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.8.0/24'
            ]
            destinationPorts: [
              '1433'
            ]
          }
        ]
      }
    ]
  }
}

// ---------- Filtering: data spoke NSG ----------
module nsgRule 'lyon-nsg-rule.bicep' = {
  name: 'lyon-nsg-rule'
  scope: resourceGroup('rg-${prefix}-spoke')
  params: {
    numero: numero
  }
}

output firewallPrivateIp string = firewallPrivateIp
output gatewaySubnetRouteTable string = gatewaySubnet.properties.routeTable.id
```

Module `lyon-nsg-rule.bicep` (same folder):
```bicep
// lyon-nsg-rule.bicep — module of lyon-connectivity.bicep, deployed into rg-stNN-spoke
// Adds Allow-SQL-From-Lyon (priority 110) to the existing NSG nsg-stNN-data.
// Warning: the module 4 catch-up redeclares nsg-stNN-data with inline rules
// and deletes this rule; run the module 5 catch-up afterwards.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

var prefix = 'st${numero}'
var octet = int(numero)

resource nsgData 'Microsoft.Network/networkSecurityGroups@2023-11-01' existing = {
  name: 'nsg-${prefix}-data'
}

resource asgData 'Microsoft.Network/applicationSecurityGroups@2023-11-01' existing = {
  name: 'asg-${prefix}-data'
}

resource allowSqlFromLyon 'Microsoft.Network/networkSecurityGroups/securityRules@2023-11-01' = {
  parent: nsgData
  name: 'Allow-SQL-From-Lyon'
  properties: {
    priority: 110
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: '10.200.${octet}.0/24'
    sourcePortRange: '*'
    destinationApplicationSecurityGroups: [
      {
        id: asgData.id
      }
    ]
    destinationPortRange: '1433'
  }
}
```

Check, preview, deploy:
```bash
az bicep build --file lyon-connectivity.bicep --stdout > /dev/null && echo "Syntax OK"
az deployment group what-if -g "$RG_HUB" -f lyon-connectivity.bicep -p numero="$NN"
az deployment group create -g "$RG_HUB" -n lyon-connectivity \
  -f lyon-connectivity.bicep -p numero="$NN" \
  --query properties.provisioningState -o tsv
```
Expected `what-if` output (end, property details omitted):
```
  + Microsoft.Network/firewallPolicies/afwp-st07-hub/ruleCollectionGroups/rcg-lyon [2023-11-01]
  + Microsoft.Network/routeTables/rt-st07-gateway [2023-11-01]
  ~ Microsoft.Network/virtualNetworks/vnet-st07-hub/subnets/GatewaySubnet [2023-11-01]
  + Microsoft.Network/networkSecurityGroups/nsg-st07-data/securityRules/Allow-SQL-From-Lyon [2023-11-01]

Resource changes: 3 to create, 1 to modify.
```
Then `Succeeded` after 3 to 8 min (update of the firewall attached to the policy).

Matrix tests:
```bash
WEB="http://10.${OCT}.4.10"; SQL="http://10.${OCT}.8.10:1433"; D80="http://10.${OCT}.8.10"
for url in "$WEB" "$SQL" "$D80"; do   # tests a, b, c
  lyon "try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 $url).Content.Trim() } catch { 'ECHEC' }"
done
tester web "timeout 5 bash -c '</dev/tcp/10.200.${OCT}.10/3389' && echo OUVERT || echo ECHEC"   # d
az network watcher show-next-hop -g "$RG_LYON_ST" --vm "vm-${ST}-lyon-fs" \
  --source-ip "10.200.${OCT}.10" --dest-ip "10.${OCT}.8.10" --query nextHopType -o tsv   # e
az network watcher show-next-hop -g "$RG_SPOKE" --vm "vm-${ST}-test-data" \
  --source-ip "10.${OCT}.8.10" --dest-ip "10.200.${OCT}.10" \
  --query "[nextHopType, nextHopIpAddress]" -o tsv                                       # e
```
Expected output (30 to 60 s per test run on a VM; `ECHEC` = failure, `OUVERT` = open):
```
vm-st07-test-web
vm-st07-test-data
ECHEC
ECHEC
VirtualNetworkGateway
VirtualAppliance	10.7.0.68
```
Test e on the Lyon side returns `VirtualNetworkGateway`: the firewall detour is decided in `GatewaySubnet`, invisible from the Lyon VM; the proof is the success of tests a and b with a return through `VirtualAppliance`, and the firewall logs (M10).

Expected answers (step 4):
- a. The source seen by `vm-st07-test-data` remains `10.200.7.10` (no SNAT to a private destination). `Allow-SQL-From-Web` only accepts `10.7.4.0/24`; the `VirtualNetwork` tag covers the VPN site ranges (spoke using `useRemoteGateways`) and, with the `0.0.0.0/0` UDR, any address: `Deny-VNet-Inbound` (priority 4000) denies the flow. An explicit NSG rule for Lyon, with a higher priority, is required.
- b. `0.0.0.0/0` is not supported on `GatewaySubnet` (gateway creation or operation blocked). A route to the hub `10.7.0.0/22` would include `AzureFirewallSubnet` and `GatewaySubnet` themselves: loop to the firewall; and the hub hosts no workload to protect.
- c. Without propagation, `GatewaySubnet` no longer receives the routes of the gateway itself: tunnel traffic is no longer forwarded correctly, a configuration not supported by Microsoft; VPN connectivity is broken.

### Why
- Routes per spoke (`/22`) rather than per subnet: any new subnet in a spoke is covered without changing the table.
- Firewall IP read from `afw-stNN-hub` (`existing`): the file stays correct if the firewall is recreated with another address (catch-up).
- `GatewaySubnet` redeclared with its exact range: a `subnets` resource is a full replacement; a different range would be rejected (subnet used by the gateway).
- Group `rcg-lyon` separate from `rcg-arveo`: its own lifecycle (deleted in one go at the end of the Lyon migration), priority 300 after the internal rules.
- Network rules (not application rules): TCP flows to private addresses, no FQDN; the implicit deny covers "any other port" (test c) and "spokes → Lyon" (test d).
- NSG rule through a module: the NSG lives in `rg-stNN-spoke`, a Bicep resource targets a single group per deployment; destination as ASG `asg-stNN-data`, source as an IP range (Lyon NICs are outside the ASG's VNet).
- NSG priority 110: next to `Allow-SQL-From-Web` (100), before `Deny-VNet-Inbound` (4000).
- No rule for the return flows: firewall and NSG are stateful.
- Test d on port 3389: port open by default on the Azure Windows Server image, so a failure does not come from the Lyon VM but from the firewall (no spokes → Lyon rule) `[TO VERIFY]` Windows firewall rule on the current image.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `BCP120` / value not computable at the start of the deployment | Firewall IP used in a resource name or a loop | Use it only in `properties` (as `nextHopIpAddress`) |
| `InUseSubnetCannotBeUpdated` / `GatewaySubnet` rejected | Range other than `10.<OCT>.0.0/27` in the redeclaration | Copy the exact range from the gateway script |
| `RouteTableCannotDisableBgpPropagationOnGatewaySubnet` `[TO VERIFY]` wording | `disableBgpRoutePropagation: true` on the `GatewaySubnet` table | `false` (default value) |
| Deployment `Conflict` / `AnotherOperationInProgress` | Firewall or hub VNet still updating | Wait 2 to 5 min, rerun |
| Test a: `ECHEC` | Table not associated with `GatewaySubnet`, or rule `lyon-vers-web` missing | `az network vnet subnet show ... -n GatewaySubnet --query routeTable.id`; `rule-collection-group show ... -n rcg-lyon` |
| Test b: `ECHEC`, test a succeeds | NSG rule missing or misplaced (outbound, priority > 4000, wrong source) | `az network nsg rule list -g $RG_SPOKE --nsg-name nsg-$ST-data -o table` |
| Test c: response `vm-stNN-test-data` | Port `*` or `80` added to the Lyon → data rule | Restrict to `1433` |
| Test d: `OUVERT` | Network rule too broad (spokes as source, `10.200.0.0/16` as destination) | Remove the rule; no spokes → Lyon flow in the matrix |
| `what-if`: `~` on `GatewaySubnet` on every run | Default properties added by the platform (`privateEndpointNetworkPolicies`) | Acceptable noise if no route or rule changes |

### Acceptable variants
- Single routes per spoke `10.<OCT>.4.0/22` + `10.<OCT>.8.0/22` replaced by one route per subnet: finer, to maintain for every new subnet.
- IP groups (`Microsoft.Network/ipGroups`) for Lyon and the spokes: readable at scale, one more resource.
- NSG rule and route table with Azure CLI, firewall rules in Bicep: technically correct, outside the "replayable from a single file" constraint.
- Explicit deny collection (Lyon → `10.<OCT>.0.0/20`, priority 4000) to log denied flows by name: valid.

## Case study 05.4 — Choosing hybrid connectivity

### Solution
| Need | Solution | Arguments | Risk or limit |
|---|---|---|---|
| 1. Lyon migration, hybrid ERP | ExpressRoute (1 Gbps circuit, private peering) + existing S2S VPN as backup | Predictable latency and SLA required by the vendor; 40 TB ≈ 90 h of transfer at a saturated 1 Gbps, compatible with 3 months | Provider ordering lead time (weeks): order now, migrate the first batches over VPN or with Azure Data Box |
| 2. 14 branches + 60 mobile users | Virtual WAN Standard: S2S VPN for branches, point-to-site (Entra ID authentication) for mobile users, Lyon connected to the virtual hub | 15+ sites, branch ↔ branch ↔ Lyon transit without UDR, simplified operations | Redesign of the current hub-spoke (virtual hub + routing intent), hourly cost of the hub and scale units |
| 3. After Lyon | No hybrid link any more: applications published on the Internet (App Service, Application Gateway with WAF), Entra ID conditional access; point-to-site for administrators only | Minimal network cost, no on-site equipment, security carried by identity | Internet dependency; public exposure to protect (WAF, MFA, logging) |

Calculation for need 1: `40 × 10¹² bytes × 8 / 10⁹ bit/s ≈ 320,000 s ≈ 89 h`, to be weighted by the real link efficiency (often 70 to 80 %).

### Acceptable variants
- Need 2: hub VPN gateway scaled up (VpnGw2AZ, 30 S2S tunnels, point-to-site) with BGP for branch ↔ branch transit: valid for 14 branches, less scalable; the answer must mention the tunnel count limit.
- Need 1: S2S VPN alone on VpnGw2AZ or VpnGw3AZ if the vendor accepts a non-guaranteed latency: cheaper, to be backed by a latency measurement.

## Bonus

### 1. DNS resolution from Lyon
```bash
lyon 'try { (Resolve-DnsName sql.arveo.internal -ErrorAction Stop).IPAddress } catch { $_.Exception.Message }'
```
Expected output:
```
sql.arveo.internal : DNS name does not exist
```
The Lyon server queries the resolver of its own VNet; private zone `arveo.internal` is linked only to the Arvéo VNets (M4). In a real datacenter, the Lyon DNS cannot reach `168.63.129.16` anyway. Target architecture: DNS Private Resolver in the hub (inbound endpoint in a dedicated, delegated subnet), conditional forwarder `arveo.internal` on the Lyon DNS pointing to the inbound endpoint IP, UDP/TCP 53 flow Lyon → endpoint allowed through the tunnel (and the firewall if a route sends it there).

### 2. DR reachable from Lyon
Additions to `lyon-connectivity.bicep`:
```bicep
// in var spokes
  {
    name: 'spoke-pra-via-fw'
    prefix: '10.${octet}.12.0/22'
  }
```
```bicep
// in the rules of rc-lyon-autoriser
          {
            ruleType: 'NetworkRule'
            name: 'lyon-vers-pra-https'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              lyonSubnet
            ]
            destinationAddresses: [
              '10.${octet}.12.0/24'
            ]
            destinationPorts: [
              '443'
            ]
          }
```
```bash
az deployment group create -g "$RG_HUB" -n lyon-connectivity \
  -f lyon-connectivity.bicep -p numero="$NN" --query properties.provisioningState -o tsv
az network watcher show-next-hop -g "$RG_LYON_ST" --vm "vm-${ST}-lyon-fs" \
  --source-ip "10.200.${OCT}.10" --dest-ip "10.${OCT}.12.4" --query nextHopType -o tsv
```
Expected output:
```
Succeeded
VirtualNetworkGateway
```
On the DR side, the return path must also cross the firewall: route table `rt-stNN-spoke-pra` (`0.0.0.0/0` → `10.<OCT>.0.68`, propagation disabled) created in **West Europe**, since a route table can only be associated with subnets in its own region, then associated with `snet-pra`. The France Central firewall remains the next hop across the global peering.

### 3. Effective IPsec policy
```bash
az network vpn-connection ipsec-policy list -g "$RG_HUB" \
  --connection-name "cn-${ST}-hub-to-lyon" -o json
```
Expected output:
```
[]
```
Empty list = no custom policy: the gateway proposes and accepts its default list of combinations (IKEv2). A custom policy on a single connection restricts that gateway to ONE combination (encryption, integrity, DH group, PFS, lifetimes); if the opposite gateway does not propose it, phase 1 or 2 fails and the connection stays `NotConnected`. Rule of thumb: same policy, applied on both sides.

## QCM — Answers
1. **C** — `allowGatewayTransit` on the hub link lends its gateway to the peered VNets.
2. **A** — `useRemoteGateways` requires the remote link to allow gateway transit.
3. **B** — The local network gateway describes the remote site: its public IP and its ranges.
4. **A** — `lng-st07-lyon` holds the IP of `vpngw-lyon` and range `10.200.7.0/24`.
5. **B** — Without a matching connection on the other side, the tunnel is not established.
6. **B** — Without a UDR on `GatewaySubnet`, outbound bypasses the firewall and the return crosses it: dropped.
7. **B** — A `0.0.0.0/0` route is not supported on `GatewaySubnet`.
8. **B** — Global peering connects different regions over the Microsoft backbone, with no gateway.
9. **C** — ExpressRoute provides a private link through a provider, with an SLA.
10. **B** — The Standard tier adds VNet ↔ VNet transit, point-to-site, ExpressRoute and hub to hub.
