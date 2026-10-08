#!/usr/bin/env bash
# Rattrapage module 07 — machines virtuelles Arvéo (rg-stNN-hub, rg-stNN-spoke, rg-stNN-app, rg-stNN-shared)
# 1. Contrôle des prérequis (hub et spoke app du M4, pare-feu supprimé en fin de J2)
# 2. Azure Bastion du hub (scripts/labs/module-07/bastion.sh, en arrière-plan)
# 3. Passerelle NAT ng-stNN-app associée à snet-web et snet-app
# 4. Mot de passe, espace de travail log-stNN-shared et compte de diagnostic (module 3)
# 5. VMs web, Load Balancers, VMSS, extensions, règle de collecte : main.bicep
# 6. NSG de snet-app, VMs existantes rattachées au pool, disque de données de web01
# 7. Contrôles : portail v2 et API à travers lbe-stNN-web
# Durée : 10 à 20 min. Idempotent : les VMs et le VMSS existants sont conservés.
# Usage : ./deploy.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
OCT=$((10#$NN))
ST="st${NN}"
HUB="rg-${ST}-hub"
SPOKE="rg-${ST}-spoke"
APP="rg-${ST}-app"
SHARED="rg-${ST}-shared"
LOC="francecentral"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")
DIR="$(cd "$(dirname "$0")" && pwd)"
LABS="${DIR}/../../labs/module-07"
PW_FILE="${HOME}/.arveo/web-admin.txt"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true

exists() { az "$@" -o none 2>/dev/null; }

echo "== Étape 1/7 : prérequis"
exists network vnet show -g "$HUB" -n "vnet-${ST}-hub" \
  || { echo "   vnet-${ST}-hub absent : rattrapages M4 et M5, puis nettoyage du J2 (module-05-vpn.sh, module-04-firewall.sh)" >&2
       exit 1; }
exists network vnet show -g "$SPOKE" -n "vnet-${ST}-spoke-app" \
  || { echo "   spoke app absent : rattrapage M4 puis ./scripts/cleanup/module-04-firewall.sh ${NN}" >&2
       exit 1; }
RT_WEB=$(az network vnet subnet show -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-app" -n snet-web \
  --query "routeTable.id" -o tsv)
if [[ -n "$RT_WEB" ]]; then
  echo "   ATTENTION : table de routes encore associée à snet-web (${RT_WEB##*/})." >&2
  echo "   Réponses du Load Balancer public envoyées au pare-feu : ./scripts/cleanup/module-04-firewall.sh ${NN}" >&2
fi
echo "   hub et spoke app présents"

echo "== Étape 2/7 : Azure Bastion"
"${LABS}/bastion.sh" "$NN"

echo "== Étape 3/7 : passerelle NAT ng-${ST}-app"
if ! exists network public-ip show -g "$SPOKE" -n "pip-${ST}-natgw"; then
  az network public-ip create -g "$SPOKE" -n "pip-${ST}-natgw" -l "$LOC" \
    --sku Standard --allocation-method Static --tags "${TAGS[@]}" -o none
fi
if ! exists network nat gateway show -g "$SPOKE" -n "ng-${ST}-app"; then
  az network nat gateway create -g "$SPOKE" -n "ng-${ST}-app" -l "$LOC" \
    --public-ip-addresses "pip-${ST}-natgw" --idle-timeout 4 --tags "${TAGS[@]}" -o none
fi
for SNET in snet-web snet-app; do
  az network vnet subnet update -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-app" -n "$SNET" \
    --nat-gateway "ng-${ST}-app" -o none
  echo "   ${SNET} : sortie par ng-${ST}-app"
done

echo "== Étape 4/7 : mot de passe et espace de travail"
mkdir -p "$(dirname "$PW_FILE")"
if [[ ! -s "$PW_FILE" ]]; then
  ( umask 077; echo "Arv-$(openssl rand -hex 8)-Z9" > "$PW_FILE" )
  echo "   mot de passe généré : ${PW_FILE}"
fi
ADMIN_PW=$(cat "$PW_FILE")
if ! exists monitor log-analytics workspace show -g "$SHARED" -n "log-${ST}-shared"; then
  echo "   log-${ST}-shared absent (module 3) : création"
  az monitor log-analytics workspace create -g "$SHARED" -n "log-${ST}-shared" -l "$LOC" \
    --sku PerGB2018 --retention-time 30 --tags "${TAGS[@]}" -o none
fi
echo "   log-${ST}-shared présent"
DIAG_SA=$(az storage account list -g "$SHARED" \
  --query "[?starts_with(name, 'starveost${NN}diag')].name | [0]" -o tsv)
echo "   diagnostics de démarrage : ${DIAG_SA:-stockage managé (starveost${NN}diag absent)}"

echo "== Étape 5/7 : VMs, Load Balancers, VMSS, extensions (main.bicep)"
D_WEB01=true; D_WEB02=true; D_VMSS=true
exists vm show -g "$APP" -n "vm-${ST}-web01" && D_WEB01=false
exists vm show -g "$APP" -n "vm-${ST}-web02" && D_WEB02=false
exists vmss show -g "$APP" -n "vmss-${ST}-api" && D_VMSS=false
echo "   création : web01=${D_WEB01} web02=${D_WEB02} vmss=${D_VMSS}"
for VM in web01 web02; do   # identité requise par l'agent Azure Monitor sur les VMs existantes
  exists vm show -g "$APP" -n "vm-${ST}-${VM}" \
    && az vm identity assign -g "$APP" -n "vm-${ST}-${VM}" -o none
done
az deployment group create \
  --resource-group "$APP" \
  --name "rattrapage-m07" \
  --template-file "${DIR}/main.bicep" \
  --parameters numero="$NN" adminPassword="$ADMIN_PW" \
               deployWeb01="$D_WEB01" deployWeb02="$D_WEB02" deployVmss="$D_VMSS" \
               diagStorageName="${DIAG_SA}" \
  --query "properties.outputs.{IP_LB_web:lbPublicIp.value, IP_API:apiFrontendIp.value}" \
  -o table

echo "== Étape 6/7 : NSG de snet-app, pool bp-web, disque de données"
if exists network nsg show -g "$APP" -n "nsg-${ST}-app"; then
  az network vnet subnet update -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-app" -n snet-app \
    --nsg "$(az network nsg show -g "$APP" -n "nsg-${ST}-app" --query id -o tsv)" -o none
  echo "   snet-app : nsg-${ST}-app associé"
fi
for VM in web01 web02; do   # VMs créées pendant les labs : carte rattachée au pool si besoin
  NIC_ID=$(az vm show -g "$APP" -n "vm-${ST}-${VM}" \
    --query "networkProfile.networkInterfaces[0].id" -o tsv)
  POOLS=$(az network nic show --ids "$NIC_ID" \
    --query "ipConfigurations[0].loadBalancerBackendAddressPools[].id" -o tsv)
  if [[ "$POOLS" != *"/lbe-${ST}-web/backendAddressPools/bp-web"* ]]; then
    IPCFG=$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[0].name" -o tsv)
    az network nic ip-config address-pool add -g "$APP" --nic-name "${NIC_ID##*/}" \
      --ip-config-name "$IPCFG" --lb-name "lbe-${ST}-web" --address-pool bp-web -o none
    echo "   vm-${ST}-${VM} : ajoutée à bp-web"
  fi
done
az vm run-command invoke -g "$APP" -n "vm-${ST}-web01" --command-id RunShellScript \
  --scripts @"${LABS}/init-data-disk.sh" --query "value[0].message" -o tsv \
  | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'

echo "== Étape 7/7 : contrôles"
LB_IP=$(az network public-ip show -g "$APP" -n "pip-${ST}-lbe-web" --query ipAddress -o tsv)
sleep 20   # sondes de santé
for _ in 1 2 3 4; do curl -s --max-time 5 "http://${LB_IP}/" || echo "ECHEC portail"; done
curl -s --max-time 5 "http://${LB_IP}/api/" || echo "ECHEC API"
echo
az network bastion show -g "$HUB" -n "bas-${ST}-hub" \
  --query "{Bastion:name, Etat:provisioningState}" -o table
echo "Mot de passe arveoadmin : ${PW_FILE} ; espace de travail : log-${ST}-shared (${SHARED})"
echo "Données Heartbeat visibles 5 à 10 min après l'installation de l'agent (lab 07.7)."
echo "Plage de l'API : 10.${OCT}.5.100:8080 (lbi-${ST}-api)"
