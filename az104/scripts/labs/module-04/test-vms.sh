#!/usr/bin/env bash
# test-vms.sh — VMs de test du module 4 dans rg-stNN-spoke
#   vm-stNN-test-web   snet-web  (vnet-stNN-spoke-app)   10.NN.4.10
#   vm-stNN-test-data  snet-data (vnet-stNN-spoke-data)  10.NN.8.10
# Sans IP publique ni NSG de carte : le filtrage est porté par les sous-réseaux (S4.2).
# Tests de flux par « az vm run-command invoke » (aucun accès entrant nécessaire).
# Usage : ./test-vms.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
OCT=$((10#$NN))
ST="st${NN}"
RG="rg-${ST}-spoke"
LOC="francecentral"
if   [[ -n "${VM_SIZE:-}" ]]; then SIZE="$VM_SIZE"
elif (( 10#$NN <= 5 ));        then SIZE="Standard_F1als_v7"
else                                SIZE="Standard_F1alds_v7"
fi
DIR="$(cd "$(dirname "$0")" && pwd)"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")

create_vm() {
  local role="$1" vnet="$2" subnet="$3" ip="$4"
  local nic="nic-${ST}-test-${role}" vm="vm-${ST}-test-${role}"

  if ! az network nic show -g "$RG" -n "$nic" -o none 2>/dev/null; then
    az network nic create -g "$RG" -n "$nic" -l "$LOC" \
      --vnet-name "$vnet" --subnet "$subnet" --private-ip-address "$ip" \
      --tags "${TAGS[@]}" -o none
    echo "Carte ${nic} créée (${ip})"
  fi

  if az vm show -g "$RG" -n "$vm" -o none 2>/dev/null; then
    echo "VM ${vm} déjà présente : conservée"
  else
    az vm create -g "$RG" -n "$vm" -l "$LOC" \
      --image Ubuntu2404 --size "$SIZE" \
      --nics "$nic" \
      --admin-username arveoadmin --generate-ssh-keys \
      --custom-data "${DIR}/cloud-init-test.yaml" \
      --storage-sku Standard_LRS \
      --tags "${TAGS[@]}" --no-wait
    echo "VM ${vm} : création lancée en arrière-plan (2 à 4 min)"
  fi
}

create_vm web  "vnet-${ST}-spoke-app"  snet-web  "10.${OCT}.4.10"
create_vm data "vnet-${ST}-spoke-data" snet-data "10.${OCT}.8.10"

echo "Suivi : az vm list -g ${RG} -d --query \"[].{Nom:name, Etat:powerState, IP:privateIps}\" -o table"
