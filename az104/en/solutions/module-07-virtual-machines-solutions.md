# Module 07 — Solutions

Examples given for trainee 07 (`NN=07`, `OCT=7`). All solutions assume the exercise variable block has been run in Cloud Shell (Bash): `NN`, `OCT`, `ST`, `RG_*`, `LOC`, `TAGS`, `DIAG_SA`, `vmrun` function. Lab scripts and Bicep files are shared with the French-speaking groups: their comments, messages and the web pages they produce are in French; resource names are kept as is.

## Exercise 07.1 ⭐ — Sizing the Arvéo workloads

### Solution
| # | Size | Disks | Pricing option |
|---|---|---|---|
| 1 Web portal | 2 × `Standard_B2s_v2` (2 vCPU, 8 GiB), zones 1 and 2 (training subscription: zone 2 only, `web02` without a zone) | Standard SSD | Pay-as-you-go; reservation worth considering after 3 months of measurements |
| 2 SQL Server ERP | `Standard_E8s_v5` (8 vCPU, 64 GiB) or `E8as_v5` | OS on Premium SSD; data and logs on Premium SSD v2 (or Premium, `ReadOnly` cache for data, `None` for logs) | 3-year reservation + Azure Hybrid Benefit (SQL licenses with SA) |
| 3 Route computation | `Standard_F16s_v2` (16 vCPU, 32 GiB) | Standard SSD (input data on a share or a storage account) | Spot VM, "deallocate" eviction, restarted by the scheduler |
| 4 File server | No VM: Azure Files + Azure File Sync (module 6) | Azure Files share (transaction optimized or hot tier) | Pay-as-you-go (6 months), no operating system to maintain |

Checks of steps 2 and 3:
```
Size          Zones
------------  -------
Standard_B2s_v2  1,2,3
Quota                     Used    Limit
------------------------  ------  -------
Total Regional vCPUs      24      100
Standard BSv2 Family vCPUs  24      100
```

### Why
- **Workload 1**: low average CPU with short peaks = typical B-series profile (credits accumulated at night, spent from 8 to 10 am). Two VMs in two zones = 99.99 % SLA with the Load Balancer (S7.3). A `D2s_v5` size is acceptable if the peaks get longer.
- **Workload 2**: 8 GiB per vCPU ratio = E family. 24/7 for 3 years = reservation (maximum discount on a fixed size); SQL licenses with SA = Azure Hybrid Benefit. Premium disks: single-VM SLA and latency suited to a database. The letter `s` is mandatory (Premium disks).
- **Workload 3**: pure compute (2 GiB per vCPU) = F family; a few hours per night and a restartable job = Spot (large discount, eviction acceptable).
- **Workload 4**: a VM serving SMB shares means an OS, patches, backups and a license; Azure Files does it as PaaS, and File Sync handles the transition with Lyon. Sizing starts with the question "is a VM needed at all?".
- **Quota**: 2 × B2s_v2 + 2 × B2s_v2 (API) = 8 vCPU per trainee in France Central; with 12 trainees, 96 vCPU (+ instances added by autoscale, up to 2 more each).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| ERP proposed as `D8s_v5` | Memory ratio ignored (only 32 GiB) | Reread the profile: 64 GB → E family |
| Size without `s` for the ERP | Premium disks not supported | Pick a size whose name contains `s` |
| Reservation for the nightly computation | 4 h out of 24: the reservation is paid 24/7 | Spot or pay-as-you-go |
| `list-skus` returns a line with restrictions | Size not offered to the subscription in the region | Pick another size or open a support request |

### Acceptable variants
- Workload 1: `Standard_B2als_v2` or `B2s_v2` (newer generation, similar price) `[TO VERIFY]` availability per zone.
- Workload 2: savings plan instead of a reservation if Arvéo plans to change size or region; SQL Server on a VM or Azure SQL Managed Instance (PaaS): an architecture choice outside the AZ-104 scope.
- Workload 3: pay-as-you-go if the job tolerates no interruption.

---

## Lab 07.2 ⭐ — First VM without a public IP, access through Bastion

### Solution
The assignment commands are complete. Summary, in order:
```bash
./scripts/labs/module-07/bastion.sh "$NN"
az network public-ip create -g "$RG_SPOKE" -n "pip-${ST}-natgw" -l "$LOC" \
  --sku Standard --allocation-method Static --tags $TAGS -o none
az network nat gateway create -g "$RG_SPOKE" -n "ng-${ST}-app" -l "$LOC" \
  --public-ip-addresses "pip-${ST}-natgw" --idle-timeout 4 --tags $TAGS -o none
for SNET in snet-web snet-app; do
  az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
    -n "$SNET" --nat-gateway "ng-${ST}-app" -o none
done
mkdir -p ~/.arveo
[[ -s ~/.arveo/web-admin.txt ]] || ( umask 077; echo "Arv-$(openssl rand -hex 8)-Z9" > ~/.arveo/web-admin.txt )
ADMIN_PW=$(cat ~/.arveo/web-admin.txt)
SNET_WEB=$(az network vnet subnet show -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" \
  -n snet-web --query id -o tsv)
az network nic create -g "$RG_APP" -n "nic-${ST}-web01" -l "$LOC" --subnet "$SNET_WEB" \
  --private-ip-address "10.${OCT}.4.11" --tags $TAGS -o none
az vm create -g "$RG_APP" -n "vm-${ST}-web01" -l "$LOC" --zone 2 --nics "nic-${ST}-web01" \
  --image Ubuntu2404 --size Standard_B2s_v2 \
  --os-disk-name "osdisk-${ST}-web01" --storage-sku StandardSSD_LRS \
  --admin-username arveoadmin --authentication-type password --admin-password "$ADMIN_PW" \
  --custom-data scripts/labs/module-07/cloud-init-web.yaml \
  --boot-diagnostics-storage "$DIAG_SA" --tags $TAGS -o table
vmrun web01 "cloud-init status --wait >/dev/null; curl -s localhost; curl -s --max-time 5 https://api.ipify.org; echo"
az disk create -g "$RG_APP" -n "disk-${ST}-web01-data" -l "$LOC" --zone 2 \
  --size-gb 32 --sku StandardSSD_LRS --tags $TAGS -o none
az vm disk attach -g "$RG_APP" --vm-name "vm-${ST}-web01" \
  --name "disk-${ST}-web01-data" --lun 0 --caching ReadOnly -o none
vmrun web01 "$(cat scripts/labs/module-07/init-data-disk.sh)"
```
Criteria check:
```bash
az vm show -g "$RG_APP" -n "vm-${ST}-web01" -d --query "[zones[0], publicIps, privateIps]" -o tsv
vmrun web01 "findmnt -no SOURCE,TARGET /srv/arveo"
```
Expected output:
```
1		10.7.4.11
/dev/sdc1 /srv/arveo
```
Step 8, resources expected in `rg-st07-app`: `nic-st07-web01`, `vm-st07-web01`, `osdisk-st07-web01`, `disk-st07-web01-data`. No `publicIPAddresses`, no `networkSecurityGroups`.

### Why
- **NAT gateway first**: the spokes were created in 2026, their subnets are private by default (no implicit outbound access), and the firewall was deleted at the end of D2. Without egress, cloud-init cannot install nginx (`apt` fails silently, no page).
- **NIC created before the VM**: name following the convention (`nic-st07-web01` instead of `vm-st07-web01VMNic`), fixed IP known in advance (Load Balancer pool, documentation), and `az vm create --nics` then creates neither a public IP nor an NSG.
- **Password in `~/.arveo`**: never in the Git repository or in the history of a versioned file; the same password is used by the Bicep file (07.3) and the VMSS (07.5). In production: SSH key or Entra ID sign-in, secret in Key Vault.
- **Disk explicitly created in zone 2**: an LRS disk is zonal; attaching it to a VM in another zone is rejected. Creating the disk separately makes the constraint visible.
- **Mount by label with `nofail`**: the `/dev/sdX` order can change at reboot; `nofail` avoids a blocked boot if the disk is detached (restore in M9).
- **Bastion in the hub**: a single administration entry point for every peered spoke, logged, with no port 22 open to the Internet.
- **Boot diagnostics to `starveost<NN>diag`**: foundation account (module 3) intended for this use; screenshot and serial log available even when the VM no longer answers on the network (boot stuck, wrong `fstab`), and prerequisite of the serial console. Variant: managed storage (no account to manage).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Step 5: empty page, no answer from `api.ipify.org` | NAT gateway missing or not associated with `snet-web` at boot time | Associate the gateway, then `vmrun web01 "cloud-init clean --logs && cloud-init init && cloud-init modules --mode final"` `[TO VERIFY]`, or recreate the VM |
| `az vm create`: `InvalidParameter ... adminPassword` | Empty password (`ADMIN_PW` not defined in a new session) | Rerun `ADMIN_PW=$(cat ~/.arveo/web-admin.txt)` |
| `RequestDisallowedByPolicy` on the OS disk | M2 mandatory tag missing on an implicit resource `[TO VERIFY]` with the actual M2 definition | Check `--tags $TAGS`; tag the disk after creation if the policy is in audit mode |
| `az vm disk attach`: disk in another zone | `az disk create` without `--zone 2` | Delete the disk, recreate it with `--zone 2` |
| `init-data-disk.sh`: "Aucun disque de données au LUN 0" | Disk attached to another LUN, or command run before the attach completed | `az vm show ... --query "storageProfile.dataDisks[].lun"`; rerun |
| Bastion button greyed out or "deployment in progress" | Bastion still `Updating` | Wait for `Succeeded` (`az network bastion show ... --query provisioningState`) |
| Bastion: authentication failure | Password copied with a space or a line break | `cat ~/.arveo/web-admin.txt` in Cloud Shell, copy without the line break |
| `--boot-diagnostics-storage`: account not found | Empty `DIAG_SA` (variable block not rerun, M3 account missing) | `echo $DIAG_SA`; module 3 catch-up, or omit the option then `az vm boot-diagnostics enable` (managed storage) |
| `SkuNotAvailable` / quota reached | Size unavailable in the zone or BSv2 family vCPU quota reached | Check `list-skus` and `list-usage` (exercise 07.1); tell the trainer |

---

## Exercise 07.3 ⭐⭐ — Second web server in Bicep

### Solution
Full file `scripts/labs/module-07/vm-web.bicep` (comments in French):
```bicep
// vm-web.bicep — solution de l'exercice 07.3 : VM web du portail client Arvéo
// Déployé dans rg-stNN-app. Le sous-réseau snet-web est lu dans rg-stNN-spoke.
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Nom court de la VM (ex. web02)')
param nomCourt string

@description('Zone de disponibilité')
@allowed([
  '1'
  '2'
  '3'
])
param zone string

@description('Dernier octet de l\'IP privée dans snet-web (ex. 12 pour 10.NN.4.12)')
@minValue(4)
@maxValue(254)
param hostOctet int

@description('Mot de passe administrateur (fichier ~/.arveo/web-admin.txt)')
@secure()
param adminPassword string

@description('Compte de stockage des diagnostics de démarrage (module 3) ; vide = stockage managé')
param diagStorageName string = 'starveost${numero}diag'

param location string = resourceGroup().location
param vmSize string = 'Standard_B2s_v2'
param adminUsername string = 'arveoadmin'

var prefix = 'st${numero}'
var octet = int(numero)
var vmName = 'vm-${prefix}-${nomCourt}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource snetWeb 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  scope: resourceGroup('rg-${prefix}-spoke')
  name: 'vnet-${prefix}-spoke-app/snet-web'
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${prefix}-${nomCourt}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: snetWeb.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.${octet}.4.${hostOctet}'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: tags
  zones: empty(zone) ? [] : [
    zone
  ]
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${prefix}-${nomCourt}'
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: empty(diagStorageName) ? null : 'https://${diagStorageName}.blob.${environment().suffixes.storage}/'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(loadTextContent('cloud-init-web.yaml'))
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
  }
}

output vmName string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
```
Build, preview and deployment:
```bash
cp scripts/labs/module-07/vm-web-squelette.bicep scripts/labs/module-07/vm-web.bicep
# (complete the TODOs)
az bicep build --file scripts/labs/module-07/vm-web.bicep
az deployment group what-if -g "$RG_APP" --template-file scripts/labs/module-07/vm-web.bicep \
  --parameters numero="$NN" nomCourt=web02 zone='' hostOctet=12 \
               adminPassword="$(cat ~/.arveo/web-admin.txt)"
az deployment group create -g "$RG_APP" -n vm-web02 \
  --template-file scripts/labs/module-07/vm-web.bicep \
  --parameters numero="$NN" nomCourt=web02 zone='' hostOctet=12 \
               adminPassword="$(cat ~/.arveo/web-admin.txt)" \
  --query "properties.outputs.{VM:vmName.value, IP:privateIp.value}" -o table
vmrun web02 "cloud-init status --wait >/dev/null; curl -s localhost"
```
Expected output:
```
VM             IP
-------------  ---------
vm-st07-web02  10.7.4.12
<h1>Arveo - portail client v1</h1><p>Serveur : vm-st07-web02 - zone aucune</p>
```
Step 5:
- Same parameters: `what-if` announces no creation or deletion; a few properties may appear as `Modify` or `Ignore` (values added by the platform, secure password) `[TO VERIFY]` depending on the API version.
- `zone=3`: `what-if` announces a change of `zones`; the deployment fails: zone 3 is refused for the subscription (`NotAvailableForSubscription`) and, in any case, a VM's zone cannot be changed (`PropertyChangeNotAllowed`-type message `[TO VERIFY]` exact wording).

### Why
- **a.** The OS disk is created implicitly by the VM, in the same zone (zonal child resource). A data disk created separately must declare its zone itself.
- **b.** The zone is part of the VM's physical identity: it is set at creation. To move a VM: recreate it in the new zone from a snapshot of its disks (or from a backup, module 9), or use Azure's regional-to-zonal move `[TO VERIFY]` availability. In an HA architecture, nothing is moved: an instance is added in the other zone and the old one is removed.
- **c.** No. `customData` only runs at first boot, and changing it on an existing VM is rejected by the API. A configuration that must evolve goes through an extension (lab 07.6) or a configuration management tool.
- Parameterized model (short name, zone, octet): the same file creates `web03`, `web04` with no duplication; the module catch-up (`scripts/catch-up/module-07/vm-web.bicep`) is its complete version (Load Balancer pool, managed identity, data disk).

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `BCP035 ... missing required properties: "createOption"` | TODO 3 incomplete | Add `createOption: 'FromImage'` |
| `zones` rejected (`BCP037`) | Property placed inside `properties` | Move it to the top level of the resource |
| `loadTextContent`: file not found | `vm-web.bicep` copied outside `scripts/labs/module-07/` | Path relative to the Bicep file: keep both files in the same folder |
| Deployment: `PrivateIPAddressInUse` | `hostOctet=11` (IP of `web01`) | `hostOctet=12` |
| `what-if` asks for `adminPassword` | Secure parameter without a value | `adminPassword="$(cat ~/.arveo/web-admin.txt)"` |
| Page shows "zone aucune" (no zone) | `zones` forgotten: regional (non-zonal) VM | Delete the VM and recreate it with `zones` (zone cannot be changed) |
| Deployment: storage account `starveost<NN>diag` not found | Module 3 account created with a suffix | Add `diagStorageName="$DIAG_SA"` to the parameters |

### Acceptable variants
- `customData` parameter passed as a string from the CLI (no `loadTextContent`): works, but the Bicep file is no longer self-contained.
- SSH key (`linuxConfiguration.ssh.publicKeys`) instead of the password: best practice in production; Bastion access then uses the private key (local file) or a key stored in Key Vault.
- Subnet referenced with `resourceId('rg-...-spoke', 'Microsoft.Network/virtualNetworks/subnets', ...)` instead of an `existing` resource: equivalent.

---

## Lab 07.4 ⭐⭐ — Public Load Balancer and cross-zone failover

### Solution
```bash
az network public-ip create -g "$RG_APP" -n "pip-${ST}-lbe-web" -l "$LOC" --sku Standard \
  --allocation-method Static --zone 1 2 3 --tags $TAGS -o none
az network lb create -g "$RG_APP" -n "lbe-${ST}-web" -l "$LOC" --sku Standard \
  --public-ip-address "pip-${ST}-lbe-web" --frontend-ip-name fe-web \
  --backend-pool-name bp-web --tags $TAGS -o none
az network lb probe create -g "$RG_APP" --lb-name "lbe-${ST}-web" -n hp-http \
  --protocol Http --port 80 --path / --interval 5 -o none
az network lb rule create -g "$RG_APP" --lb-name "lbe-${ST}-web" -n rule-http \
  --protocol Tcp --frontend-port 80 --backend-port 80 --frontend-ip-name fe-web \
  --backend-pool-name bp-web --probe-name hp-http --idle-timeout 4 \
  --disable-outbound-snat true -o none
for VM in web01 web02; do
  az network nic ip-config address-pool add -g "$RG_APP" --nic-name "nic-${ST}-${VM}" \
    --ip-config-name ipconfig1 --lb-name "lbe-${ST}-web" --address-pool bp-web -o none
done
LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
for i in $(seq 10); do curl -s --max-time 5 "http://${LB_IP}/"; echo; done \
  | grep -o 'vm-st[0-9]*-web0[12] - zone [0-9]' | sort | uniq -c
```
Expected output (distribution varies):
```
      6 vm-st07-web01 - zone 2
      4 vm-st07-web02 - zone aucune
```
Simulated failure:
```bash
vmrun web01 "systemctl stop nginx"
sleep 15
for i in $(seq 10); do curl -s --max-time 5 "http://${LB_IP}/"; echo; done \
  | grep -o 'vm-st[0-9]*-web0[12] - zone [0-9]' | sort | uniq -c
LB_ID=$(az network lb show -g "$RG_APP" -n "lbe-${ST}-web" --query id -o tsv)
az monitor metrics list --resource "$LB_ID" --metric DipAvailability --interval PT1M \
  --aggregation Average --offset 10m --query "value[0].timeseries[0].data[-3:].average" -o tsv
vmrun web01 "systemctl start nginx"
```
Expected output:
```
     10 vm-st07-web02 - zone aucune
100
75
50
```
(The metric, averaged over the whole pool, drops from 100 to 50; intermediate values and delay vary.)

### Why
- **a.** A Standard load-balancing rule can also provide outbound SNAT for the pool VMs (discouraged method: limited SNAT ports). Here the NAT gateway, associated with `snet-web`, handles ALL the subnet's egress and takes precedence over the Load Balancer; disabling the rule's SNAT makes this choice explicit.
- **b.** `Allow-HTTP-HTTPS-Inbound` (priority 100, source `*`, ports 80 and 443) of `nsg-st<NN>-web` (module 4). A Standard Load Balancer is secure by default: without an NSG allowing the flow, public inbound connections to the pool are denied. The probe goes through the default rule `AllowAzureLoadBalancerInBound`.
- **c.** A test VM does not serve the portal (different page): it would return inconsistent responses. It is also deallocated: the probe would mark it as failed. A pool only holds identical instances of the same service.
- Distribution is not strict round robin: 5-tuple hash, each `curl` uses a new source port, hence a distribution close to 50/50 over many requests.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `curl` with no answer (timeout) | Empty pool, failed probe, or route table still associated with `snet-web` (replies sent to the deleted firewall) | Check the pool; `az network vnet subnet show ... -n snet-web --query routeTable`; dissociate (`module-04-firewall.sh`) |
| Only one VM answers, even without failure | nginx stopped or cloud-init not finished on the other VM | `vmrun web02 "systemctl is-active nginx; curl -s localhost"` |
| `address-pool add`: IP configuration not found | VM created without a named NIC (`vm-st07-web01VMNic`, configuration `ipconfigvm-st07-web01`) | `az vm show ... --query networkProfile.networkInterfaces[0].id` then `az network nic show ... --query "ipConfigurations[].name"` |
| Zone error when creating the public IP | `--zone` omitted then added (zone cannot be changed) | Delete the IP (not yet associated) and recreate it |
| Responses still spread during the failure | Probe not failed yet (interval) | Wait 15 s more |

### Acceptable variants
- Azure portal (Load Balancer → Create): identical, provided both NICs are ticked in the pool and "None" is chosen for outbound connectivity.
- IP-address-based pool (`az network lb address-pool create --backend-address`) instead of NICs: valid for a Standard Load Balancer `[TO VERIFY]` restrictions (no outbound SNAT, same VNet).
- Bicep: `scripts/catch-up/module-07/lb-web.bicep` + `lbBackendPoolIds` parameter of `vm-web.bicep`.

---

## Challenge 07.5 ⭐⭐⭐ — Parcel-tracking API on a VMSS

### Solution
Bicep file (identical to `scripts/catch-up/module-07/vmss-api.bicep`, comments in French):
```bicep
// vmss-api.bicep — rattrapage M7 et solution du défi 07.5 : API de suivi des colis
// Déployé dans rg-stNN-app :
//   - nsg-stNN-app : filtrage de snet-app (association au sous-réseau par CLI, cf. deploy.sh) ;
//   - lbi-stNN-api : Load Balancer interne Standard, frontal 10.NN.5.100 zone-redondant, TCP 8080 ;
//   - vmss-stNN-api : groupe identique (VMSS) Flexible, sans zone (abonnement limité à la zone 2), 2 instances ;
//   - as-stNN-api : mise à l'échelle automatique 2 à 4 instances sur le CPU moyen.
// Le sous-réseau snet-app (rg-stNN-spoke) n'est PAS redéclaré : un PUT de sous-réseau
// réécrirait toutes ses propriétés (passerelle NAT, NSG, table de routes).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Mot de passe administrateur (fichier ~/.arveo/web-admin.txt)')
@secure()
param adminPassword string

param location string = resourceGroup().location
param vmSize string = 'Standard_B2s_v2'
param adminUsername string = 'arveoadmin'

@minValue(1)
param minInstances int = 2

@minValue(1)
param maxInstances int = 4

var prefix = 'st${numero}'
var octet = int(numero)
var lbName = 'lbi-${prefix}-api'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource snetApp 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  scope: resourceGroup('rg-${prefix}-spoke')
  name: 'vnet-${prefix}-spoke-app/snet-app'
}

// ---------- Filtrage de snet-app ----------
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${prefix}-app'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-API-From-Web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.${octet}.4.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8080'
        }
      }
      {
        name: 'Allow-SSH-From-Bastion'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.${octet}.1.0/26'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------- Équilibreur interne ----------
resource ilb 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: lbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-api'
        zones: [
          '1'
          '2'
          '3'
        ]
        properties: {
          subnet: {
            id: snetApp.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.${octet}.5.100'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'bp-api'
      }
    ]
    probes: [
      {
        name: 'hp-api'
        properties: {
          protocol: 'Http'
          port: 8080
          requestPath: '/'
          intervalInSeconds: 5
          numberOfProbes: 1
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-api'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-api')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-api')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'hp-api')
          }
          protocol: 'Tcp'
          frontendPort: 8080
          backendPort: 8080
          idleTimeoutInMinutes: 4
          enableFloatingIP: false
        }
      }
    ]
  }
}

// ---------- Groupe identique Flexible ----------
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-03-01' = {
  name: 'vmss-${prefix}-api'
  location: location
  tags: tags
  // sans zone : abonnement de formation limité à la zone 2
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: minInstances
  }
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'api${numero}'
        adminUsername: adminUsername
        adminPassword: adminPassword
        customData: base64(loadTextContent('../../labs/module-07/cloud-init-api.yaml'))
        linuxConfiguration: {
          disablePasswordAuthentication: false
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: 'ubuntu-24_04-lts'
          sku: 'server'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          deleteOption: 'Delete'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
        }
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true // stockage managé : aucun compte à gérer pour des instances éphémères
        }
      }
      networkProfile: {
        networkApiVersion: '2020-11-01'
        networkInterfaceConfigurations: [
          {
            name: 'nic-${prefix}-api'
            properties: {
              primary: true
              deleteOption: 'Delete'
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: snetApp.id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-api')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    ilb
  ]
}

// ---------- Mise à l'échelle automatique ----------
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: 'as-${prefix}-api'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'profil-cpu'
        capacity: {
          minimum: string(minInstances)
          maximum: string(maxInstances)
          default: string(minInstances)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

output nsgId string = nsgApp.id
output apiFrontendIp string = '10.${octet}.5.100'
```
Deployment, subnet associations and tests:
```bash
az deployment group what-if -g "$RG_APP" --template-file scripts/catch-up/module-07/vmss-api.bicep \
  --parameters numero="$NN" adminPassword="$(cat ~/.arveo/web-admin.txt)"
az deployment group create -g "$RG_APP" -n vmss-api \
  --template-file scripts/catch-up/module-07/vmss-api.bicep \
  --parameters numero="$NN" adminPassword="$(cat ~/.arveo/web-admin.txt)" -o none
az network vnet subnet update -g "$RG_SPOKE" --vnet-name "vnet-${ST}-spoke-app" -n snet-app \
  --nsg "$(az network nsg show -g "$RG_APP" -n "nsg-${ST}-app" --query id -o tsv)" -o none
# a. six calls from web01 (instances ready 3 to 5 min after deployment)
vmrun web01 "for i in 1 2 3 4 5 6; do curl -s --max-time 3 http://10.${OCT}.5.100:8080/; done"
# b. instance zones
az vm list -g "$RG_APP" --query "[?virtualMachineScaleSet].{Instance:name, Zone:zones[0]}" -o table
# c. SSH from web01 to an instance
API1=$(az vm list -g "$RG_APP" -d --query "[?virtualMachineScaleSet] | [0].privateIps" -o tsv)
vmrun web01 "timeout 3 bash -c '</dev/tcp/${API1}/22' && echo OUVERT || echo FERME"
# d. autoscale profile
az monitor autoscale show -g "$RG_APP" -n "as-${ST}-api" \
  --query "profiles[0].{Min:capacity.minimum, Max:capacity.maximum, Rules:length(rules)}" -o table
```
Expected output (instance names vary; `FERME` = closed, `OUVERT` = open):
```
{"service":"api-suivi-colis","instance":"api07ab12cd","zone":"1"}
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
{"service":"api-suivi-colis","instance":"api07ab12cd","zone":"1"}
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
{"service":"api-suivi-colis","instance":"api07ab12cd","zone":"1"}
Instance                  Zone
------------------------  ------
vmss-st07-api_1a2b3c4d    1
vmss-st07-api_5e6f7a8b    2
FERME
Min    Max    Rules
-----  -----  -------
2      4      2
```
The NAT gateway stays associated with `snet-app` (lab 07.2): the `subnet update --nsg` command only changes the NSG.

### Why
- **a.** Flexible: instances = standard VMs (management, extensions, backup like any VM), spread across both zones and fault domains, the mode recommended by Microsoft for new deployments. Uniform remains relevant for very homogeneous fleets at very large scale.
- **b.** Loss of one instance: the probe removes it, the remaining instance serves alone; autoscale recreates an instance to get back to the minimum of 2. With a minimum of 1, a night-time scale-in would leave a single instance: losing it would cut the API until it is recreated. On a subscription without restrictions, a VMSS in zones 1, 2 and 3 also survives the loss of a whole zone (spread instances, zone-redundant frontend).
- **c.** A subnet declared in Bicep is sent as a whole (PUT): any property missing from the file (NAT gateway, route table, delegation) is removed. The subnet belongs to the network (module 4, `rg-st<NN>-spoke`); the application team only adds targeted associations.
- **Zone-redundant internal Load Balancer**: its frontend IP survives the loss of a zone; static IP `10.<OCT>.5.100` so that portal v2 (lab 07.6) references it in a stable way.
- **NSG**: `Deny-VNet-Inbound` (4000) blocks all other internal traffic, including other trainees and `web01` on port 22; the probe (`168.63.129.16`) is not part of the `VirtualNetwork` tag, the `Allow-AzureLoadBalancer` rule makes it explicit.
- **Slower scale-in rule** (10 min, 25 % threshold) than the scale-out rule (5 min, 70 %): avoids oscillation.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `curl` to `10.<OCT>.5.100:8080` with no answer | Instances still being configured (cloud-init) | Wait 3 to 5 min; `az vm run-command invoke -g ... -n <INSTANCE> --command-id RunShellScript --scripts "curl -s localhost:8080"` |
| Still no answer after 5 min | NSG without the probe allowed, or NAT gateway missing on `snet-app` (nginx not installed) | Check `nsg-st<NN>-app` and the `natGateway` of `snet-app` |
| `platformFaultDomainCount` rejected | Value > 1 with zones in Flexible mode | `platformFaultDomainCount: 1` (spreading by zone) |
| The `snet-app` `PUT` removed the NAT gateway | Subnet redeclared in the Bicep file | Re-associate with `az network vnet subnet update --nat-gateway`; remove the subnet from the file |
| Autoscale: invalid `metricResourceUri` | Malformed VMSS ID or resource in another group | Use `vmss.id` |
| Only one instance answers | Load Balancer hash over 6 calls | Rerun 10 to 20 calls; check the health of both instances |

### Acceptable variants
- CLI: `az network lb create --subnet <SNET_APP_ID> --private-ip-address 10.<OCT>.5.100 --frontend-ip-zone 1 2 3` `[TO VERIFY]` frontend zone option, then `az vmss create --orchestration-mode Flexible --zones 1 2 3 --platform-fault-domain-count 1 --instance-count 2 --lb lbi-st<NN>-api --backend-pool-name bp-api --subnet <SNET_APP_ID> --public-ip-address "" --nsg "" --custom-data scripts/labs/module-07/cloud-init-api.yaml`, then `az monitor autoscale create` (S7.3).
- TCP 8080 probe instead of HTTP: accepted, but less faithful (nginx can listen while the application does not respond).
- Probe NSG rule omitted: works thanks to the default rule `AllowAzureLoadBalancerInBound` (65001), as long as no custom rule hides it.

---

## Lab 07.6 ⭐⭐ — Portal v2 through the Custom Script extension

### Solution
```bash
SCRIPT_B64=$(sed "s/__OCT__/${OCT}/g" scripts/labs/module-07/portail-v2.sh | base64 -w0)
for VM in web01 web02; do
  az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-${VM}" \
    --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
    --protected-settings "{\"script\": \"${SCRIPT_B64}\"}" -o none
  az vm extension list -g "$RG_APP" --vm-name "vm-${ST}-${VM}" \
    --query "[].{VM:'${VM}', Name:name, State:provisioningState}" -o tsv
done
LB_IP=$(az network public-ip show -g "$RG_APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
curl -s "http://${LB_IP}/"; curl -s "http://${LB_IP}/api/"
```
Expected output:
```
web01	CustomScript	Succeeded
web02	CustomScript	Succeeded
<h1>Arveo - portail client v2</h1><p>Serveur : vm-st07-web02 - zone aucune</p>
{"service":"api-suivi-colis","instance":"api07ef34gh","zone":"2"}
```
Reapplication (step 4):
```bash
az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-web01" \
  --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
  --protected-settings "{\"script\": \"${SCRIPT_B64}\"}" -o none
vmrun web01 "grep -c 'Portail v2 deploye' /var/lib/waagent/custom-script/download/*/stdout"
az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-web01" \
  --publisher Microsoft.Azure.Extensions --name CustomScript --version 2.1 \
  --protected-settings "{\"script\": \"${SCRIPT_B64}\"}" --force-update -o none
vmrun web01 "grep -c 'Portail v2 deploye' /var/lib/waagent/custom-script/download/*/stdout; tail -n 3 /var/log/azure/custom-script/handler.log"
```
Expected result: a single `download/0/stdout` folder after the plain reapply (unchanged configuration, no run), then an extra folder (`download/1/`) after `--force-update` `[TO VERIFY]` folder numbering depending on the extension version; the handler log mentions a new execution sequence.

### Why
- **a.** Protected settings are encrypted all the way to the VM and are never returned by the API (`az vm extension show` does not display them); a script may contain internal addresses, secrets or tokens. Public settings are readable by any reader of the resource (Reader role).
- **b.** A VM accepts only ONE Custom Script extension: the second configuration replaces the first one (same `CustomScript` resource), which is not run again. Several steps = a single orchestration script, or Run Command (several named commands possible).
- **c.** No: the extension is set on `web01` and `web02` only. For a VMSS, the extension is declared in the MODEL (`virtualMachineProfile.extensionProfile`): every new instance receives it at creation.
- **The script waits for cloud-init**: applied right after creation (catch-up, Bicep), the script would run during cloud-init, which would then rewrite the v1 page.
- **Idempotent script**: files fully rewritten, `nginx -t` before `reload`; a rerun breaks nothing.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Extension `Failed`, `nginx: configuration file ... test failed` | `__OCT__` not replaced or `$uri` interpreted | Check the `sed`; do not change the script's `\$` |
| `/api/` returns `502 Bad Gateway` | API missing or unreachable (challenge 07.5 not done, `snet-app` NSG) | M7 catch-up, or `vmrun web01 "curl -s http://10.<OCT>.5.100:8080/"` |
| `/api/` returns `504` after 3 s | API instances stopped or failed probe | `az vm list -g rg-st<NN>-app -d --query "[?virtualMachineScaleSet].powerState"` |
| `Operation 'PUT' is not allowed ... another operation in progress` | Two simultaneous extension operations on the same VM | Wait for the first one to finish; one extension at a time |
| `--protected-settings`: invalid JSON | Badly escaped quotes | Keep `"{\"script\": \"${SCRIPT_B64}\"}"` |
| Page still v1 on one VM | Extension applied on a single VM | Repeat on the other VM (the loop of the solution) |

### Acceptable variants
- `fileUris` pointing to the script stored in the module 6 storage account (SAS or managed identity) + `commandToExecute`: useful for large scripts; requires network access to the account (module 6 private endpoint).
- Managed Run Command (`az vm run-command create`): several named scripts per VM, output log in a blob; suited to one-off operations.
- Bicep: `virtualMachines/extensions` resource (catch-up `main.bicep`, `replace()` of `__OCT__`).

---

## Lab 07.7 ⭐⭐ — Azure Monitor agent and data collection rule

### Solution
```bash
az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" \
  --query "{Region:location, Tier:sku.name, Retention:retentionInDays, ID:customerId}" -o table
for VM in web01 web02; do
  az vm identity assign -g "$RG_APP" -n "vm-${ST}-${VM}" -o none
  az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-${VM}" \
    --publisher Microsoft.Azure.Monitor --name AzureMonitorLinuxAgent \
    --enable-auto-upgrade true -o none
done
az deployment group create -g "$RG_APP" -n dcr-arveo \
  --template-file scripts/labs/module-07/dcr-arveo-linux.bicep \
  --parameters numero="$NN" -o none
VM_ID=$(az vm show -g "$RG_APP" -n "vm-${ST}-web01" --query id -o tsv)
az monitor data-collection rule association list --resource "$VM_ID" \
  --query "[].{Association:name, Rule:dataCollectionRuleId}" -o tsv | sed 's#/subscriptions/.*/##'
vmrun web01 "logger -p auth.warning 'Arveo test AMA ${ST}'"
WS=$(az monitor log-analytics workspace show -g "$RG_SHARED" -n "log-${ST}-shared" \
  --query customerId -o tsv)
az monitor log-analytics query -w "$WS" -o table --analytics-query \
  "Heartbeat | where TimeGenerated > ago(15m) | summarize Last=max(TimeGenerated) by Computer"
az monitor log-analytics query -w "$WS" -o table --analytics-query \
  "Syslog | where SyslogMessage has 'Arveo test AMA' | project TimeGenerated, Computer, Facility, SeverityLevel"
```
Expected output (after 5 to 10 min, GUID and timestamps vary, technical columns omitted):
```
Region         Tier       Retention    ID
-------------  ---------  -----------  ------------------------------------
francecentral  PerGB2018  30           1b2c3d4e-0000-0000-0000-000000000000
dcra-vm-st07-web01	dcr-st07-linux
Computer       Last
-------------  ----------------------------
vm-st07-web01  2026-10-07T15:58:12.0000000Z
vm-st07-web02  2026-10-07T15:58:09.0000000Z
TimeGenerated                 Computer       Facility    SeverityLevel
----------------------------  -------------  ----------  ---------------
2026-10-07T15:57:40.0000000Z  vm-st07-web01  auth        warning
```

### Why
- **a.** The agent authenticates with Azure Monitor (download of the DCR configuration, data upload) using the VM's managed identity: no workspace key to distribute, unlike the former Log Analytics agent.
- **b.** Create a second, Windows-type data collection rule (event logs, Windows counters) to the same workspace and associate it with the Windows VM, on which `AzureMonitorWindowsAgent` is installed. Rules are independent and cumulative.
- **c.** Data collection rule `dcr-st<NN>-linux` (`facilityNames`): change the Bicep file and redeploy; agents pick up the new configuration without reinstallation.
- **Foundation workspace (`log-st<NN>-shared`, module 3)**: cross-cutting resource shared by every workload (network, VMs, PaaS); one workspace per application would multiply cross-workspace queries and permissions to manage in module 10.
- **Automatic agent upgrade**: fixes applied by Azure, no pinned version to maintain.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `ResourceNotFound` on the workspace when deploying the DCR | `log-st<NN>-shared` missing (module 3 not done) | `./scripts/catch-up/module-03/deploy.sh <NN>` then redeploy the DCR |
| AMA extension `Failed` | No Internet egress (NAT gateway missing) or no managed identity | Check the `natGateway` of `snet-web`; `az vm identity assign` then reapply the extension |
| `Heartbeat` empty after 15 min | Rule not associated, or agent installed before the identity | Check the associations; restart the agent: `vmrun web01 "systemctl restart azuremonitoragent"` |
| `association list`: unknown command | CLI extension `monitor-control-service` missing | `az config set extension.use_dynamic_install=yes_without_prompt` (variable block) |
| `log-analytics query`: `PathNotFoundError` or workspace not found | Workspace name passed instead of the customer ID | Use `customerId` (GUID) |
| DCR deployment: `InvalidPayload` on the counters | Linux counter names different from the expected ones | Compare with a rule created through the portal (counters `[À VÉRIFIER]` in the file) |
| Syslog missing, `Heartbeat` present | Level too low (`auth.info`) or facility not collected | `logger -p auth.warning`; check `facilityNames` |

### Acceptable variants
- Portal: VM → **Monitoring** → **Insights** → **Enable**: installs the agent and creates a `MSVMI-*` rule (VM Insights data, `InsightsMetrics`, `VMProcess` tables); complementary to the Syslog rule.
- Azure Policy (initiative "Enable Azure Monitor for VMs"): agent installation and rule association on every new VM, at management group scale; possible demo in module 10.

---

## Bonus

1. **Public name of the portal**:
   ```bash
   OLD=$(az network dns record-set a show -g "$RG_HUB" -z "arveo-${ST}.fr" -n www \
     --query "ARecords[0].ipv4Address" -o tsv)
   az network dns record-set a remove-record -g "$RG_HUB" -z "arveo-${ST}.fr" -n www \
     -a "$OLD" --keep-empty-record-set -o none
   az network dns record-set a add-record -g "$RG_HUB" -z "arveo-${ST}.fr" -n www -a "$LB_IP" -o none
   NS=$(az network dns zone show -g "$RG_HUB" -n "arveo-${ST}.fr" --query "nameServers[0]" -o tsv)
   nslookup "www.arveo-${ST}.fr" "$NS"
   curl -s -H "Host: www.arveo-${ST}.fr" "http://${LB_IP}/"
   ```
   Expected result: `nslookup` returns the IP of `pip-st<NN>-lbe-web`; since the zone is not delegated (fictitious domain), public resolution only works by querying the Azure name server directly.
2. **Entra ID sign-in**:
   ```bash
   az vm extension set -g "$RG_APP" --vm-name "vm-${ST}-web02" \
     --publisher Microsoft.Azure.ActiveDirectory --name AADSSHLoginForLinux -o none
   az role assignment create --assignee "$(az ad signed-in-user show --query id -o tsv)" \
     --role "Virtual Machine Administrator Login" \
     --scope "$(az group show -n "$RG_APP" --query id -o tsv)" -o none
   ```
   Bastion connection with "Microsoft Entra ID" `[TO VERIFY]` support depending on the Bastion SKU; otherwise, `az ssh vm` from a workstation with network access. Traceability: the named user (`st<NN>@<DOMAIN>`) appears in `/var/log/auth.log` and in the Entra ID sign-in logs, instead of the shared `arveoadmin` account. Revoking access = removing the role, without touching the VM.
3. **Availability set**:
   ```bash
   az vm availability-set create -g "$RG_APP" -n "avail-${ST}-web" \
     --platform-fault-domain-count 2 --platform-update-domain-count 5 -o none
   az vm create -g "$RG_APP" -n "vm-${ST}-test-as" --availability-set "avail-${ST}-web" --zone 2 \
     --image Ubuntu2404 --size Standard_B2s_v2 --public-ip-address "" --nsg "" \
     --subnet "$SNET_WEB" --admin-username arveoadmin --generate-ssh-keys -o none
   az vm availability-set delete -g "$RG_APP" -n "avail-${ST}-web"
   ```
   Expected result: the VM creation fails (zone and availability set are mutually exclusive, message `[TO VERIFY]` exact wording); no VM created, only the set to delete.
4. **Autoscale under load**: the VMSS `Percentage CPU` metric is an AVERAGE over all instances. With 2 `B2s_v2` instances (1 vCPU), one instance at 100 % and the other at 5 % give 52.5 % < 70 %: no scale-out. All instances must be loaded (or the threshold lowered). The history (`Autoscale scale up` in the activity log) appears after the 5 min window and the processing delay of the autoscale engine.

## QCM — Answers
1. **B** — `s` = size supporting Premium SSD disks; `a` = AMD, `d` = temporary disk, `p` = ARM.
2. **B** — `deallocate` releases the hardware: compute is no longer billed; `stop` shuts the OS down but keeps the allocation (billed).
3. **C** — the temporary disk is local to the host and lost on deallocation, resize or host failure.
4. **A** — since March 31, 2026, new VNets have private subnets: an explicit egress method is required (NAT gateway, firewall, LB, public IP).
5. **B** — Basic (and above) reaches VMs in peered VNets; Developer is limited to the VNet where it is enabled.
6. **C** — two VMs in two zones: 99.99 %; availability set: 99.95 %; single Premium/Ultra VM: 99.9 %.
7. **B** — membership of an availability set is only defined at creation; the VM must be recreated.
8. **A** — the NAT gateway provides the subnet's egress; disabling the rule's SNAT avoids a second egress method and LB SNAT port exhaustion.
9. **B** — without a configuration change, the extension is not run again; `--force-update` (or a different timestamp) forces a new run.
10. **B** — AMA agent (extension) + data collection rule + association of the rule with the VM; MMA has been retired since August 31, 2024.
