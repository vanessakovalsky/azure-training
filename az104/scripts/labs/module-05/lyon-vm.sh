#!/usr/bin/env bash
# lyon-vm.sh — serveur de fichiers du site de Lyon simulé (module 5, réutilisé au module 6)
#   vm-stNN-lyon-fs   Windows Server 2022   rg-stNN-lyon (West Europe)
#   carte nic-stNN-lyon-fs dans vnet-lyon/snet-stNN (groupe rg-formation-lyon), IP 10.200.NN.10
# Prérequis (formatrice) : sous-réseau snet-stNN créé et rôle Contributeur de réseau
# attribué au stagiaire sur ce sous-réseau (scripts/labs/module-05/lyon-site.sh prepare).
# Sans IP publique : tests par « az vm run-command » (M5), Azure File Sync au M6.
# Mot de passe administrateur généré une fois et conservé dans ~/.arveo/lyon-fs-admin.txt.
# Idempotent : carte et VM existantes conservées.
# Usage : ./lyon-vm.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
OCT=$((10#$NN))
ST="st${NN}"
RG="rg-${ST}-lyon"
RG_LYON="${RG_LYON:-rg-formation-lyon}"
LOC="westeurope"
SIZE="${VM_SIZE:-Standard_B2s_v2}"
IMAGE="${VM_IMAGE:-Win2022Datacenter}"
NIC="nic-${ST}-lyon-fs"
VM="vm-${ST}-lyon-fs"          # 15 caractères : limite du nom d'ordinateur Windows
IP="10.200.${OCT}.10"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")

SUBNET_ID=$(az network vnet subnet show -g "$RG_LYON" --vnet-name vnet-lyon \
  -n "snet-${ST}" --query id -o tsv 2>/dev/null) || true
if [[ -z "$SUBNET_ID" ]]; then
  echo "Sous-réseau snet-${ST} introuvable dans vnet-lyon (${RG_LYON}) : prévenir la formatrice" >&2
  exit 1
fi

PWFILE="$HOME/.arveo/lyon-fs-admin.txt"
mkdir -p "$(dirname "$PWFILE")"
if [[ ! -s "$PWFILE" ]]; then
  # Majuscule, minuscules, chiffre et caractère spécial garantis par le préfixe et le suffixe
  echo "Arv-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-16)-9z" > "$PWFILE"
  chmod 600 "$PWFILE"
fi

if az network nic show -g "$RG" -n "$NIC" -o none 2>/dev/null; then
  echo "Carte ${NIC} déjà présente : conservée"
else
  az network nic create -g "$RG" -n "$NIC" -l "$LOC" \
    --subnet "$SUBNET_ID" --private-ip-address "$IP" \
    --tags "${TAGS[@]}" -o none
  echo "Carte ${NIC} créée (${IP})"
fi

if az vm show -g "$RG" -n "$VM" -o none 2>/dev/null; then
  echo "VM ${VM} déjà présente : conservée (état : $(az vm get-instance-view -g "$RG" -n "$VM" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus | [0]" -o tsv))"
else
  az vm create -g "$RG" -n "$VM" -l "$LOC" \
    --image "$IMAGE" --size "$SIZE" \
    --nics "$NIC" \
    --admin-username arveoadmin --admin-password "$(cat "$PWFILE")" \
    --storage-sku StandardSSD_LRS \
    --tags "${TAGS[@]}" --no-wait
  echo "VM ${VM} : création lancée en arrière-plan (5 à 10 min)"
fi

echo "Mot de passe administrateur (arveoadmin) : ${PWFILE}"
echo "Suivi : az vm list -g ${RG} -d --query \"[].{Nom:name, Etat:powerState, IP:privateIps}\" -o table"
