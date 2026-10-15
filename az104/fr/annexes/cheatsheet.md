# Aide-mémoire — Administration Microsoft Azure (AZ-104)

Commandes Azure CLI utilisées pendant la formation, par domaine. Variables : `RG` groupe de ressources, `LOC` région, `<...>` à remplacer.

`Commande = az <groupe> <sous-groupe> <action> --paramètres -o table|tsv|json --query "<JMESPath>"`

---

## Session et contexte
```bash
az login --tenant <ID_OU_DOMAINE>              # connexion (navigateur) ; --use-device-code sans navigateur
az account show -o table                       # abonnement courant
az account set --subscription <ID>             # changer d'abonnement
az config set core.output=table                # format de sortie par défaut
az <commande> --help                           # aide d'une commande
```
> ⚠️ **Piège** : jeton CLI expiré après 90 jours d'inactivité → `az login`.

## Requêtes et formats
```bash
az vm list --query "[].{Nom:name, RG:resourceGroup}" -o table      # projection
az vm list --query "[?location=='francecentral'].name" -o tsv      # filtre
az vm show -g "$RG" -n <VM> --query id -o tsv                      # valeur seule (pour une variable)
```
> 💡 `-o tsv` pour les variables, `-o table` pour lire, `-o json` pour tout voir.

---

## Identités (Entra ID) et RBAC
```bash
az ad user create --display-name "<NOM>" --user-principal-name <UPN> --password '<MDP>' --force-change-password-next-sign-in true
az ad group create --display-name <GROUPE> --mail-nickname <ALIAS>
az ad group member add --group <GROUPE> --member-id <OBJECT_ID>
az role assignment create --assignee-object-id <ID> --assignee-principal-type Group \
  --role Reader --scope "$(az group show -n "$RG" --query id -o tsv)"
az role assignment list -g "$RG" -o table                            # qui a quoi sur ce groupe
az role definition list --name "Reader" -o json                      # contenu d'un rôle
```
> ℹ️ Administrateur délégué (unité administrative) : création DANS l'AU par Graph (`az rest --method post --url https://graph.microsoft.com/v1.0/directory/administrativeUnits/<ID>/members`).

## Gouvernance
```bash
az group create -n "$RG" -l "$LOC" --tags Projet=<P> Environnement=<E>
az tag update --resource-id <ID> --operation Merge --tags Cle=Valeur   # ajoute sans écraser
az policy definition list --query "[?displayName=='Allowed locations'].name" -o tsv
az policy assignment create -n <NOM> --policy <ID_DEF> --scope <SCOPE> \
  --params '{"listOfAllowedLocations":{"value":["francecentral"]}}'
az policy assignment list -g "$RG" -o table
az policy state trigger-scan -g "$RG" ; az policy state summarize -g "$RG"
az lock create -n <NOM> -g "$RG" --lock-type CanNotDelete
```
> ⚠️ **Piège** : deux affectations « Allowed locations » se cumulent (intersection) : une seule mauvaise valeur bloque tout.

## Déploiement (ARM / Bicep)
```bash
az bicep build -f main.bicep                                         # compiler, détecter les erreurs
az deployment group what-if -g "$RG" -f main.bicep -p cle=valeur      # prévisualiser
az deployment group create  -g "$RG" -f main.bicep -p cle=valeur      # déployer (idempotent)
az deployment operation group list -g "$RG" -n <DEPLOIEMENT> \
  --query "[?properties.provisioningState=='Failed'].properties.statusMessage"   # cause d'un échec
az group export -n "$RG" > export.json ; az bicep decompile -f export.json        # exporter, convertir
```

---

## Réseau
```bash
az network vnet create -g "$RG" -n <VNET> -l "$LOC" --address-prefixes 10.0.0.0/16 \
  --subnet-name <SNET> --subnet-prefixes 10.0.1.0/24
az network nsg rule create -g "$RG" --nsg-name <NSG> -n Allow-HTTP --priority 100 \
  --direction Inbound --access Allow --protocol Tcp --destination-port-ranges 80 443
az network vnet subnet update -g "$RG" --vnet-name <VNET> -n <SNET> --nsg <NSG> --route-table <RT>
az network route-table route create -g "$RG" --route-table-name <RT> -n vers-pare-feu \
  --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address <IP_FW>
az network vnet peering create -g "$RG" --vnet-name <A> -n a-vers-b --remote-vnet <ID_B> \
  --allow-vnet-access --allow-forwarded-traffic          # + --allow-gateway-transit (hub) / --use-remote-gateways (spoke)
az network nic list-effective-nsg -g "$RG" -n <NIC>       # règles effectives (VM démarrée)
az network nic show-effective-route-table -g "$RG" -n <NIC> -o table
```
> ⚠️ **Piège** : `az network vnet create` sur un VNet existant réécrit ses sous-réseaux ; créer les sous-réseaux avec `az network vnet subnet create`.

## Connectivité (VPN)
```bash
az network vnet-gateway create -g "$RG" -n <GW> --vnet <VNET> --public-ip-addresses <PIP> \
  --gateway-type Vpn --vpn-type RouteBased --sku VpnGw1AZ --no-wait      # 30 à 45 min
az network local-gateway create -g "$RG" -n <LNG> --gateway-ip-address <IP_DISTANTE> \
  --local-address-prefixes 10.200.0.0/24
az network vpn-connection create -g "$RG" -n <CN> --vnet-gateway1 <GW> --local-gateway2 <LNG> \
  --shared-key '<CLE>'
az network vpn-connection show -g "$RG" -n <CN> --query connectionStatus -o tsv   # Unknown → Connected
```
> ℹ️ `Unknown` pendant 1 à 3 min après la création : normal. `NotConnected` durable : clé partagée.

---

## Stockage
```bash
az storage account create -g "$RG" -n <COMPTE> -l "$LOC" --sku Standard_RAGRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false
az storage account show -n <COMPTE> --expand geoReplicationStats --query geoReplicationStats
az storage container create --account-name <COMPTE> -n <CONT> --auth-mode login
az storage blob upload --account-name <COMPTE> -c <CONT> -n <NOM> -f <FICHIER> --auth-mode login
az storage container generate-sas --account-name <COMPTE> -n <CONT> --permissions r \
  --expiry <AAAA-MM-JJTHH:MMZ> --https-only --as-user --auth-mode login -o tsv
az storage account management-policy create --account-name <COMPTE> -g "$RG" --policy @lifecycle.json
az storage account update -g "$RG" -n <COMPTE> --public-network-access Disabled
azcopy copy '<SOURCE>' '<DESTINATION_SAS>' --recursive
```
> ⚠️ **Piège** : conversion LRS → RA-GRS : `LastSyncTimeUnavailable` pendant la copie initiale (25 à 30 min mesurés). Choisir la redondance dès la création.
> ⚠️ **Piège** : clé partagée désactivée → `--auth-mode login` partout + rôle de données (`Storage Blob Data …`).

---

## Machines virtuelles
```bash
az vm list-skus -l "$LOC" --size Standard_B2s_v2 --resource-type virtualMachines \
  --query "[].{Taille:name, Zones:join(',',locationInfo[0].zones), Restrictions:join(',',restrictions[].restrictionInfo.zones[])}" -o table
az vm list-usage -l "$LOC" -o table                          # quotas vCPU par famille
az vm create -g "$RG" -n <VM> --image Ubuntu2404 --size Standard_B2s_v2 --zone 2 \
  --nics <NIC> --admin-username <ADMIN> --custom-data cloud-init.yaml
az vm deallocate -g "$RG" -n <VM> --no-wait                  # arrêt SANS facturation du calcul
az vm start -g "$RG" -n <VM> --no-wait
az vm run-command invoke -g "$RG" -n <VM> --command-id RunShellScript --scripts "hostname"
az vm run-command invoke -g "$RG" -n <VM> --command-id RunPowerShellScript --scripts "Get-ChildItem F:\\"
az vm extension set -g "$RG" --vm-name <VM> -n CustomScript --publisher Microsoft.Azure.Extensions \
  --protected-settings '{"script":"<BASE64>"}'
```
> ⚠️ **Piège** : `az vm stop` = VM arrêtée mais **facturée** ; `deallocate` libère le calcul.
> ⚠️ **Piège** : les VMs désallouées comptent dans le quota vCPU ; restrictions de zones propres à chaque abonnement.

## PaaS et conteneurs
```bash
az appservice plan create -g "$RG" -n <PLAN> --sku S1 --is-linux
az webapp create -g "$RG" -p <PLAN> -n <APP> --runtime "NODE:20-lts"
az webapp deploy -g "$RG" -n <APP> --src-path app.zip --type zip [--slot staging]
az webapp deployment slot swap -g "$RG" -n <APP> --slot staging --target-slot production
az acr build -r <REGISTRE> -t <IMAGE>:<TAG> .                 # construction dans Azure (ACR Tasks)
az container create -g "$RG" -n <ACI> --image <REGISTRE>.azurecr.io/<IMAGE>:<TAG> \
  --acr-identity <ID_IDENTITE> --assign-identity <ID_IDENTITE> --ports 8080
```

---

## Sauvegarde
```bash
az backup vault create -g "$RG" -n <COFFRE> -l "$LOC"
az backup protection enable-for-vm -g "$RG" -v <COFFRE> --vm <ID_VM> --policy-name <STRATEGIE>
az backup protection backup-now -g "$RG" -v <COFFRE> --container-name <VM> --item-name <VM> \
  --backup-management-type AzureIaasVM --workload-type VM --retain-until <JJ-MM-AAAA>
az backup job list -g "$RG" -v <COFFRE> -o table
az backup recoverypoint list -g "$RG" -v <COFFRE> --container-name <VM> --item-name <VM> \
  --backup-management-type AzureIaasVM --workload-type VM -o table
```
> ⚠️ **Piège** : `properties.containerName` (forme courte) refusé par `backup-now` → noms d'affichage + `--workload-type`, ou noms complets extraits de l'`id`.

## Surveillance
```bash
az monitor diagnostic-settings create -n <NOM> --resource <ID> --workspace <ID_ESPACE> \
  --logs '[{"categoryGroup":"allLogs","enabled":true}]'
az monitor action-group create -g "$RG" -n <AG> --action email exploitation <ADRESSE>
az monitor metrics alert create -g "$RG" -n <REGLE> --scopes <ID_VM> \
  --condition "avg Percentage CPU > 80" --window-size 5m --evaluation-frequency 1m --action <ID_AG>
az monitor log-analytics query -w <ID_CLIENT_ESPACE> --analytics-query "Heartbeat | take 5" -o table
az network watcher show-next-hop -g "$RG" --vm <VM> --source-ip <IP_SRC> --dest-ip <IP_DEST>
az network watcher test-ip-flow -g "$RG" --vm <VM> --direction Inbound --protocol TCP \
  --local <IP_VM>:22 --remote <IP_SRC>:50000
```
```kusto
Heartbeat | summarize Dernier = max(TimeGenerated) by Computer
Perf | where CounterName == "% Processor Time" | summarize avg(CounterValue) by bin(TimeGenerated, 5m), Computer
Syslog | where Facility == "auth" and SyslogMessage has "Failed password" | summarize count() by Computer
```

---

## Nettoyage
```bash
az resource list -g "$RG" -o table                          # inventaire avant suppression
az group delete -n "$RG" --yes --no-wait                     # suppression complète d'un groupe
az network bastion delete -g "$RG" -n <BASTION> --yes        # confirmation requise sans --yes
```
> 💡 Fin de journée : `deallocate` des VMs, suppression de Bastion, pare-feu, passerelles VPN (coût horaire).
