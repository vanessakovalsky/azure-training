#!/usr/bin/env bash
# module-07-vm.sh — à lancer en FIN DE JOUR 3 (après le module 7)
# Supprime le coût horaire de Bastion : bas-stNN-hub et pip-stNN-bastion (5 à 10 min).
# Désactive la mise à l'échelle automatique (sinon elle redémarre 2 instances), puis désalloue
# les instances de vmss-stNN-api et les VMs web : calcul non facturé, disques conservés.
# Conservés : VMs (désallouées), disques, Load Balancers, passerelle NAT, NSG, extensions,
# espace de travail et règle de collecte (modules 8 à 10).
# Redémarrage le jour 4 : az vm start -g rg-stNN-app -n vm-stNN-web01 (idem web02),
#   puis az monitor autoscale update -g rg-stNN-app -n as-stNN-api --enabled true
# Recréation de Bastion si besoin : scripts/labs/module-07/bastion.sh <NN>
# Usage : ./module-07-vm.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
HUB="rg-${ST}-hub"
APP="rg-${ST}-app"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true

echo "== Suppression de Bastion et de son IP publique (5 à 10 min)"
if az network bastion show -g "$HUB" -n "bas-${ST}-hub" -o none 2>/dev/null; then
  az network bastion delete -g "$HUB" -n "bas-${ST}-hub"
  echo "   bas-${ST}-hub supprimé"
fi
az network public-ip delete -g "$HUB" -n "pip-${ST}-bastion" 2>/dev/null \
  && echo "   pip-${ST}-bastion supprimée" || true

echo "== Mise à l'échelle automatique désactivée"
if az monitor autoscale show -g "$APP" -n "as-${ST}-api" -o none 2>/dev/null; then
  az monitor autoscale update -g "$APP" -n "as-${ST}-api" --enabled false -o none
  echo "   as-${ST}-api : désactivée"
fi

echo "== Désallocation des VMs (VMSS Flexible : chaque instance est une VM du groupe)"
VMS=$(az vm list -g "$APP" --query "[].name" -o tsv)
for VM in $VMS; do
  az vm deallocate -g "$APP" -n "$VM" --no-wait
  echo "   ${VM} : désallocation lancée"
done

az vm list -g "$APP" -d --query "[].{Nom:name, Zone:zones[0], Etat:powerState}" -o table
