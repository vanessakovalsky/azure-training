#!/usr/bin/env bash
# Rattrapage module 05 — connectivité inter-sites Arvéo (rg-stNN-hub, rg-stNN-spoke, rg-stNN-lyon)
# 1. État du module 4 (pare-feu absent → rattrapage M4, transit désactivé au préalable)
# 2. Attente de la passerelle vpngw-stNN-hub en Succeeded (jusqu'à 50 min si elle vient d'être lancée)
# 3. Serveur de Lyon vm-stNN-lyon-fs (scripts/labs/module-05/lyon-vm.sh, idempotent)
# 4. Transit, spoke PRA, tunnel, routage GatewaySubnet, règles Lyon : main.bicep
# 5. Synchronisation des peerings et contrôle du tunnel
# Prérequis : côté Lyon préparé par la formatrice (lyon-site.sh prepare, puis connect).
# Clé partagée : variable PSK, sinon saisie masquée.
# Usage : ./deploy.sh <NN>      ou      PSK='<CLE>' ./deploy.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
HUB="rg-${ST}-hub"
SPOKE="rg-${ST}-spoke"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "${PSK:-}" ]]; then
  read -r -s -p "Clé partagée du tunnel (transmise par la formatrice) : " PSK
  echo
fi
[[ -n "$PSK" ]] || { echo "Clé partagée vide" >&2; exit 1; }

set_remote_gateways() {   # set_remote_gateways <true|false> : liens spoke → hub existants
  local spoke
  for spoke in app data pra; do
    if az network vnet peering show -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
        -n "peer-spoke-${spoke}-to-hub" -o none 2>/dev/null; then
      az network vnet peering update -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
        -n "peer-spoke-${spoke}-to-hub" --set useRemoteGateways="$1" -o none
    fi
  done
}

echo "== Étape 1/5 : état du module 4"
if az network firewall show -g "$HUB" -n "afw-${ST}-hub" -o none 2>/dev/null \
  || az resource show -g "$HUB" -n "afw-${ST}-hub" \
       --resource-type Microsoft.Network/azureFirewalls -o none 2>/dev/null; then
  echo "   pare-feu présent : rattrapage M4 inutile"
else
  echo "   pare-feu absent : rattrapage du module 4 (10 à 20 min)"
  set_remote_gateways false   # le rattrapage M4 redéclare les liens du hub sans transit
  "${DIR}/../../m4/catch-up/module-04/deploy.sh" "$NN"
fi

echo "== Étape 2/5 : passerelle vpngw-${ST}-hub"
for _ in $(seq 1 100); do
  STATE=$(az network vnet-gateway show -g "$HUB" -n "vpngw-${ST}-hub" \
    --query provisioningState -o tsv 2>/dev/null || echo "Absente")
  [[ "$STATE" == "Succeeded" ]] && break
  [[ "$STATE" == "Failed" || "$STATE" == "Absente" ]] && {
    echo "   passerelle ${STATE} : relancer scripts/m5/prereq-vpn-gateways.sh ${NN}" >&2; exit 1; }
  echo "   ${STATE}... nouvelle vérification dans 30 s"
  sleep 30
done
[[ "$STATE" == "Succeeded" ]] || { echo "   délai dépassé (50 min)" >&2; exit 1; }
echo "   Succeeded"

echo "== Étape 3/5 : serveur de Lyon"
"${DIR}/../../labs/module-05/lyon-vm.sh" "$NN"

echo "== Étape 4/5 : transit, spoke PRA, tunnel, routage et règles (main.bicep)"
DEPLOY_PRA=true
if az network vnet show -g "$SPOKE" -n "vnet-${ST}-spoke-pra" -o none 2>/dev/null; then
  DEPLOY_PRA=false
  OCT=$((10#$NN))
  az network vnet update -g "$SPOKE" -n "vnet-${ST}-spoke-pra" \
    --address-prefixes "10.${OCT}.12.0/23" "10.${OCT}.14.0/23" -o none
  echo "   vnet-${ST}-spoke-pra déjà présent : conservé, espace d'adressage complété"
fi
az deployment group create \
  --resource-group "$HUB" \
  --name "rattrapage-m05" \
  --template-file "${DIR}/main.bicep" \
  --parameters numero="$NN" deployPraVnet="$DEPLOY_PRA" psk="$PSK" \
  --query "properties.outputs.{IP_Lyon:lyonGatewayIp.value, IP_privee_FW:firewallPrivateIp.value}" \
  -o table

echo "== Étape 5/5 : synchronisation des peerings et contrôle du tunnel"
for LINK in $(az network vnet peering list -g "$HUB" --vnet-name "vnet-${ST}-hub" \
    --query "[?peeringSyncLevel!='FullyInSync'].name" -o tsv); do
  az network vnet peering sync -g "$HUB" --vnet-name "vnet-${ST}-hub" -n "$LINK" -o none
  echo "   ${LINK} synchronisé"
done
az network vnet peering list -g "$HUB" --vnet-name "vnet-${ST}-hub" \
  --query "[].{Lien:name, Etat:peeringState, Sync:peeringSyncLevel, Transit:allowGatewayTransit}" \
  -o table
for _ in $(seq 1 10); do
  CN=$(az network vpn-connection show -g "$HUB" -n "cn-${ST}-hub-to-lyon" \
    --query connectionStatus -o tsv)
  [[ "$CN" == "Connected" ]] && break
  sleep 30
done
echo "Tunnel cn-${ST}-hub-to-lyon : ${CN}"
[[ "$CN" == "Connected" ]] || echo "   côté Lyon absent ou clé différente : prévenir la formatrice" >&2
