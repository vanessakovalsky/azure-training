#!/usr/bin/env bash
# module-05-vpn.sh — à lancer en FIN DE JOUR 2 (avec cleanup/module-04-firewall.sh)
# Supprime le coût horaire de la passerelle VPN du stagiaire :
#   connexion cn-stNN-hub-to-lyon, passerelle locale lng-stNN-lyon,
#   passerelle vpngw-stNN-hub (10 à 20 min) puis son IP pip-stNN-vpngw.
# Désactive d'abord le transit de passerelle (liens spoke → hub, puis hub → spokes) :
# les peerings reviennent à l'état du module 4.
# Conservés : VNets, peerings, GatewaySubnet et rt-stNN-gateway, spoke PRA, règles Lyon.
# vm-stNN-lyon-fs est arrêtée (deallocate) : réutilisée au module 6.
# Côté Lyon (formatrice) : scripts/labs/module-05/lyon-site.sh cleanup
# Idempotent : relançable si la session Cloud Shell s'est fermée pendant la suppression.
# Recréation : scripts/prereq-vpn-gateways.sh <NN>, puis scripts/catch-up/module-05/deploy.sh <NN>
# Usage : ./module-05-vpn.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
HUB="rg-${ST}-hub"
SPOKE="rg-${ST}-spoke"

echo "== Connexion et passerelle locale"
az network vpn-connection delete -g "$HUB" -n "cn-${ST}-hub-to-lyon" 2>/dev/null || true
az network local-gateway delete -g "$HUB" -n "lng-${ST}-lyon" 2>/dev/null || true

echo "== Transit de passerelle désactivé"
for spoke in app data pra; do
  if az network vnet peering show -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
      -n "peer-spoke-${spoke}-to-hub" -o none 2>/dev/null; then
    az network vnet peering update -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-${spoke}" \
      -n "peer-spoke-${spoke}-to-hub" --set useRemoteGateways=false -o none
    echo "   peer-spoke-${spoke}-to-hub : useRemoteGateways=false"
  fi
done
for link in $(az network vnet peering list -g "$HUB" --vnet-name "vnet-${ST}-hub" \
    --query "[?allowGatewayTransit].name" -o tsv); do
  az network vnet peering update -g "$HUB" --vnet-name "vnet-${ST}-hub" \
    -n "$link" --set allowGatewayTransit=false -o none
  echo "   ${link} : allowGatewayTransit=false"
done

echo "== Arrêt du serveur de Lyon"
az vm deallocate -g "rg-${ST}-lyon" -n "vm-${ST}-lyon-fs" --no-wait 2>/dev/null || true

echo "== Passerelle VPN (10 à 20 min)"
if az network vnet-gateway show -g "$HUB" -n "vpngw-${ST}-hub" -o none 2>/dev/null; then
  az network vnet-gateway delete -g "$HUB" -n "vpngw-${ST}-hub"
fi
az network public-ip delete -g "$HUB" -n "pip-${ST}-vpngw" 2>/dev/null || true

az resource list -g "$HUB" --query "[].{Nom:name, Type:type}" -o table
