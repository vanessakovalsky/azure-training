# Cheat sheet — Microsoft Azure administration (AZ-104)

Azure CLI commands used during the training, by domain. Variables: `RG` resource group, `LOC` region, `<...>` to replace.

`Command = az <group> <subgroup> <action> --parameters -o table|tsv|json --query "<JMESPath>"`

---

## Session and context
```bash
az login --tenant <ID_OU_DOMAINE>              # sign in (browser); --use-device-code without a browser
az account show -o table                       # current subscription
az account set --subscription <ID>             # switch subscription
az config set core.output=table                # default output format
az <commande> --help                           # help for a command
```
> ⚠️ **Pitfall**: CLI token expires after 90 days of inactivity → `az login`.

## Queries and formats
```bash
az vm list --query "[].{Name:name, RG:resourceGroup}" -o table      # projection
az vm list --query "[?location=='francecentral'].name" -o tsv      # filter
az vm show -g "$RG" -n <VM> --query id -o tsv                      # single value (for a variable)
```
> 💡 `-o tsv` for variables, `-o table` to read, `-o json` to see everything.

---

## Identity (Entra ID) and RBAC
```bash
az ad user create --display-name "<NAME>" --user-principal-name <UPN> --password '<PASSWORD>' --force-change-password-next-sign-in true
az ad group create --display-name <GROUP> --mail-nickname <ALIAS>
az ad group member add --group <GROUP> --member-id <OBJECT_ID>
az role assignment create --assignee-object-id <ID> --assignee-principal-type Group \
  --role Reader --scope "$(az group show -n "$RG" --query id -o tsv)"
az role assignment list -g "$RG" -o table                            # who has what on this group
az role definition list --name "Reader" -o json                      # role content
```
> ℹ️ Delegated administrator (administrative unit): create IN the AU through Graph (`az rest --method post --url https://graph.microsoft.com/v1.0/directory/administrativeUnits/<ID>/members`).

## Governance
```bash
az group create -n "$RG" -l "$LOC" --tags Projet=<P> Environnement=<E>
az tag update --resource-id <ID> --operation Merge --tags Cle=Valeur   # adds without overwriting
az policy definition list --query "[?displayName=='Allowed locations'].name" -o tsv
az policy assignment create -n <NAME> --policy <ID_DEF> --scope <SCOPE> \
  --params '{"listOfAllowedLocations":{"value":["francecentral"]}}'
az policy assignment list -g "$RG" -o table
az policy state trigger-scan -g "$RG" ; az policy state summarize -g "$RG"
az lock create -n <NAME> -g "$RG" --lock-type CanNotDelete
```
> ⚠️ **Pitfall**: two "Allowed locations" assignments combine (intersection): a single wrong value blocks everything.

## Deployment (ARM / Bicep)
```bash
az bicep build -f main.bicep                                         # build, detect errors
az deployment group what-if -g "$RG" -f main.bicep -p cle=valeur      # preview
az deployment group create  -g "$RG" -f main.bicep -p cle=valeur      # deploy (idempotent)
az deployment operation group list -g "$RG" -n <DEPLOYMENT> \
  --query "[?properties.provisioningState=='Failed'].properties.statusMessage"   # cause of a failure
az group export -n "$RG" > export.json ; az bicep decompile -f export.json        # export, convert
```

---

## Networking
```bash
az network vnet create -g "$RG" -n <VNET> -l "$LOC" --address-prefixes 10.0.0.0/16 \
  --subnet-name <SNET> --subnet-prefixes 10.0.1.0/24
az network nsg rule create -g "$RG" --nsg-name <NSG> -n Allow-HTTP --priority 100 \
  --direction Inbound --access Allow --protocol Tcp --destination-port-ranges 80 443
az network vnet subnet update -g "$RG" --vnet-name <VNET> -n <SNET> --nsg <NSG> --route-table <RT>
az network route-table route create -g "$RG" --route-table-name <RT> -n to-firewall \
  --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address <IP_FW>
az network vnet peering create -g "$RG" --vnet-name <A> -n a-to-b --remote-vnet <ID_B> \
  --allow-vnet-access --allow-forwarded-traffic          # + --allow-gateway-transit (hub) / --use-remote-gateways (spoke)
az network nic list-effective-nsg -g "$RG" -n <NIC>       # effective rules (VM running)
az network nic show-effective-route-table -g "$RG" -n <NIC> -o table
```
> ⚠️ **Pitfall**: `az network vnet create` on an existing VNet rewrites its subnets; create subnets with `az network vnet subnet create`.

## Connectivity (VPN)
```bash
az network vnet-gateway create -g "$RG" -n <GW> --vnet <VNET> --public-ip-addresses <PIP> \
  --gateway-type Vpn --vpn-type RouteBased --sku VpnGw1AZ --no-wait      # 30 to 45 min
az network local-gateway create -g "$RG" -n <LNG> --gateway-ip-address <REMOTE_IP> \
  --local-address-prefixes 10.200.0.0/24
az network vpn-connection create -g "$RG" -n <CN> --vnet-gateway1 <GW> --local-gateway2 <LNG> \
  --shared-key '<KEY>'
az network vpn-connection show -g "$RG" -n <CN> --query connectionStatus -o tsv   # Unknown → Connected
```
> ℹ️ `Unknown` for 1 to 3 min after creation: normal. Persistent `NotConnected`: shared key.

---

## Storage
```bash
az storage account create -g "$RG" -n <ACCOUNT> -l "$LOC" --sku Standard_RAGRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false
az storage account show -n <ACCOUNT> --expand geoReplicationStats --query geoReplicationStats
az storage container create --account-name <ACCOUNT> -n <CONT> --auth-mode login
az storage blob upload --account-name <ACCOUNT> -c <CONT> -n <NAME> -f <FILE> --auth-mode login
az storage container generate-sas --account-name <ACCOUNT> -n <CONT> --permissions r \
  --expiry <YYYY-MM-DDTHH:MMZ> --https-only --as-user --auth-mode login -o tsv
az storage account management-policy create --account-name <ACCOUNT> -g "$RG" --policy @lifecycle.json
az storage account update -g "$RG" -n <ACCOUNT> --public-network-access Disabled
azcopy copy '<SOURCE>' '<DESTINATION_SAS>' --recursive
```
> ⚠️ **Pitfall**: LRS → RA-GRS conversion: `LastSyncTimeUnavailable` during the initial copy (25 to 30 min measured). Choose redundancy at creation.
> ⚠️ **Pitfall**: shared key disabled → `--auth-mode login` everywhere + a data role (`Storage Blob Data …`).

---

## Virtual machines
```bash
az vm list-skus -l "$LOC" --size Standard_B2s_v2 --resource-type virtualMachines \
  --query "[].{Size:name, Zones:join(',',locationInfo[0].zones), Restrictions:join(',',restrictions[].restrictionInfo.zones[])}" -o table
az vm list-usage -l "$LOC" -o table                          # vCPU quotas per family
az vm create -g "$RG" -n <VM> --image Ubuntu2404 --size Standard_B2s_v2 --zone 2 \
  --nics <NIC> --admin-username <ADMIN> --custom-data cloud-init.yaml
az vm deallocate -g "$RG" -n <VM> --no-wait                  # stop WITHOUT compute billing
az vm start -g "$RG" -n <VM> --no-wait
az vm run-command invoke -g "$RG" -n <VM> --command-id RunShellScript --scripts "hostname"
az vm run-command invoke -g "$RG" -n <VM> --command-id RunPowerShellScript --scripts "Get-ChildItem F:\\"
az vm extension set -g "$RG" --vm-name <VM> -n CustomScript --publisher Microsoft.Azure.Extensions \
  --protected-settings '{"script":"<BASE64>"}'
```
> ⚠️ **Pitfall**: `az vm stop` = VM stopped but **billed**; `deallocate` releases compute.
> ⚠️ **Pitfall**: deallocated VMs count against the vCPU quota; zone restrictions are specific to each subscription.

## PaaS and containers
```bash
az appservice plan create -g "$RG" -n <PLAN> --sku S1 --is-linux
az webapp create -g "$RG" -p <PLAN> -n <APP> --runtime "NODE:20-lts"
az webapp deploy -g "$RG" -n <APP> --src-path app.zip --type zip [--slot staging]
az webapp deployment slot swap -g "$RG" -n <APP> --slot staging --target-slot production
az acr build -r <REGISTRY> -t <IMAGE>:<TAG> .                 # build in Azure (ACR Tasks)
az container create -g "$RG" -n <ACI> --image <REGISTRY>.azurecr.io/<IMAGE>:<TAG> \
  --acr-identity <IDENTITY_ID> --assign-identity <IDENTITY_ID> --ports 8080
```

---

## Backup
```bash
az backup vault create -g "$RG" -n <VAULT> -l "$LOC"
az backup protection enable-for-vm -g "$RG" -v <VAULT> --vm <ID_VM> --policy-name <POLICY>
az backup protection backup-now -g "$RG" -v <VAULT> --container-name <VM> --item-name <VM> \
  --backup-management-type AzureIaasVM --workload-type VM --retain-until <DD-MM-YYYY>
az backup job list -g "$RG" -v <VAULT> -o table
az backup recoverypoint list -g "$RG" -v <VAULT> --container-name <VM> --item-name <VM> \
  --backup-management-type AzureIaasVM --workload-type VM -o table
```
> ⚠️ **Pitfall**: `properties.containerName` (short form) is rejected by `backup-now` → friendly names + `--workload-type`, or full names taken from the `id`.

## Monitoring
```bash
az monitor diagnostic-settings create -n <NAME> --resource <ID> --workspace <WORKSPACE_ID> \
  --logs '[{"categoryGroup":"allLogs","enabled":true}]'
az monitor action-group create -g "$RG" -n <AG> --action email operations <ADDRESS>
az monitor metrics alert create -g "$RG" -n <RULE> --scopes <ID_VM> \
  --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m --action <ID_AG>
az monitor log-analytics query -w <WORKSPACE_CUSTOMER_ID> --analytics-query "Heartbeat | take 5" -o table
az network watcher show-next-hop -g "$RG" --vm <VM> --source-ip <IP_SRC> --dest-ip <IP_DEST>
az network watcher test-ip-flow -g "$RG" --vm <VM> --direction Inbound --protocol TCP \
  --local <IP_VM>:22 --remote <IP_SRC>:50000
```
```kusto
Heartbeat | summarize Last = max(TimeGenerated) by Computer
Perf | where CounterName == "% Processor Time" | summarize avg(CounterValue) by bin(TimeGenerated, 5m), Computer
Syslog | where Facility == "auth" and SyslogMessage has "Failed password" | summarize count() by Computer
```

---

## Cleanup
```bash
az resource list -g "$RG" -o table                          # inventory before deletion
az group delete -n "$RG" --yes --no-wait                     # delete a whole group
az network bastion delete -g "$RG" -n <BASTION> --yes        # confirmation required without --yes
```
> 💡 End of day: `deallocate` VMs, delete Bastion, firewall, VPN gateways (hourly cost).
