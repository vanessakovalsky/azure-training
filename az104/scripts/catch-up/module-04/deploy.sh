#!/usr/bin/env bash
# Rattrapage module 04 — réseau hub-spoke Arvéo (rg-stNN-hub + rg-stNN-spoke)
# 1. Hub et passerelle VPN : scripts/prereq-vpn-gateways.sh (idempotent)
# 2. Pare-feu, règles, spokes, NSG/ASG, UDR, peerings, VMs de test, zones DNS : main.bicep
# Durée : 10 à 20 min (pare-feu). La passerelle VPN poursuit son déploiement en arrière-plan.
# Usage : ./deploy.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== Étape 1/2 : hub et passerelle VPN"
"${DIR}/../../prereq-vpn-gateways.sh" "$NN"

# Clé SSH : utilisée seulement à la création des VMs de test (accès par run-command)
[[ -f "$HOME/.ssh/id_rsa.pub" ]] || ssh-keygen -t rsa -b 4096 -N "" -f "$HOME/.ssh/id_rsa" -q

DEPLOY_VMS=true
if az vm show -g "rg-${ST}-spoke" -n "vm-${ST}-test-web" -o none 2>/dev/null \
  && az vm show -g "rg-${ST}-spoke" -n "vm-${ST}-test-data" -o none 2>/dev/null; then
  DEPLOY_VMS=false
  echo "VMs de test déjà présentes : conservées"
fi

echo "== Étape 2/2 : pare-feu, spokes, routage, DNS (main.bicep)"
az deployment group create \
  --resource-group "rg-${ST}-hub" \
  --name "rattrapage-m04" \
  --template-file "${DIR}/main.bicep" \
  --parameters numero="$NN" deployTestVms="$DEPLOY_VMS" \
    sshPublicKey="$(cat "$HOME/.ssh/id_rsa.pub")" \
  --query "properties.outputs.{IP_privee_FW:firewallPrivateIp.value, IP_publique_FW:firewallPublicIp.value}" \
  -o table

echo "== Contrôle"
az network vnet list --query "[?starts_with(name, 'vnet-${ST}-')].{Nom:name, Plage:addressSpace.addressPrefixes[0]}" -o table
