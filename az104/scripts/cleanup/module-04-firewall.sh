#!/usr/bin/env bash
# module-04-firewall.sh — à lancer en FIN DE JOUR 2 (après le module 5)
# Supprime le coût horaire du pare-feu : afw-stNN-hub, pip-stNN-fw, pip-stNN-fw-mgmt.
# Dissocie les tables de routes des spokes (sinon 0.0.0.0/0 pointe vers une IP inexistante).
# Conservés : stratégie afwp-stNN-hub et ses règles, tables de routes, NSG, VNets, DNS.
# Les VMs de test sont arrêtées (deallocate), pas supprimées.
# Recréation (jour concerné) : scripts/catch-up/module-04/deploy.sh <NN>
# Usage : ./module-04-firewall.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
HUB="rg-${ST}-hub"
SPOKE="rg-${ST}-spoke"

echo "== Dissociation des tables de routes"
for pair in "vnet-${ST}-spoke-app snet-web" "vnet-${ST}-spoke-app snet-app" \
            "vnet-${ST}-spoke-data snet-data"; do
  read -r vnet subnet <<< "$pair"
  az network vnet subnet update -g "$SPOKE" --vnet-name "$vnet" -n "$subnet" \
    --remove routeTable -o none   # [À VÉRIFIER] syntaxe selon la version d'Azure CLI
  echo "   ${vnet}/${subnet} : table de routes retirée"
done

echo "== Suppression du pare-feu et de ses IP publiques (5 à 10 min)"
az network firewall delete -g "$HUB" -n "afw-${ST}-hub" 2>/dev/null \
  || az resource delete -g "$HUB" -n "afw-${ST}-hub" \
       --resource-type Microsoft.Network/azureFirewalls
az network public-ip delete -g "$HUB" -n "pip-${ST}-fw"
az network public-ip delete -g "$HUB" -n "pip-${ST}-fw-mgmt"

echo "== Arrêt des VMs de test"
az vm deallocate -g "$SPOKE" -n "vm-${ST}-test-web" --no-wait
az vm deallocate -g "$SPOKE" -n "vm-${ST}-test-data" --no-wait

az resource list -g "$HUB" --query "[].{Nom:name, Type:type}" -o table
