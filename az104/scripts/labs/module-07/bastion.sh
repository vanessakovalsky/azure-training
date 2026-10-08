#!/usr/bin/env bash
# bastion.sh — Azure Bastion du hub Arvéo (module 7), lancé à 13:30 le jour 3
# Provisionnement : 5 à 10 min, d'où un lancement en arrière-plan avant l'exposé S7.1.
# Crée dans rg-stNN-hub :
#   - pip-stNN-bastion : IP publique Standard, statique, zones 1 2 3
#   - bas-stNN-hub     : Bastion SKU Basic dans AzureBastionSubnet (10.NN.1.0/26, créé au M4)
# Idempotent : objets existants conservés. Usage : ./bastion.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
RG="rg-${ST}-hub"
LOC="francecentral"
VNET="vnet-${ST}-hub"
PIP="pip-${ST}-bastion"
BAS="bas-${ST}-hub"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")

# Commandes « az network bastion » : extension installée à la volée
az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true

echo "== Sous-réseau AzureBastionSubnet de ${VNET}"
if ! az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n AzureBastionSubnet \
    --query addressPrefix -o tsv 2>/dev/null; then
  OCT=$((10#$NN))
  echo "   absent : az network vnet subnet create -g ${RG} --vnet-name ${VNET} -n AzureBastionSubnet --address-prefixes 10.${OCT}.1.0/26" >&2
  exit 1
fi

echo "== IP publique ${PIP}"
if az network public-ip show -g "$RG" -n "$PIP" -o none 2>/dev/null; then
  echo "   déjà présente : conservée"
else
  az network public-ip create -g "$RG" -n "$PIP" -l "$LOC" \
    --sku Standard --allocation-method Static --zone 1 2 3 \
    --tags "${TAGS[@]}" -o none
  echo "   créée"
fi

echo "== Bastion ${BAS} (SKU Basic)"
if az network bastion show -g "$RG" -n "$BAS" -o none 2>/dev/null; then
  echo "   déjà présent : état $(az network bastion show -g "$RG" -n "$BAS" \
    --query provisioningState -o tsv)"
else
  az network bastion create -g "$RG" -n "$BAS" -l "$LOC" \
    --vnet-name "$VNET" --public-ip-address "$PIP" --sku Basic \
    --tags "${TAGS[@]}" --no-wait
  echo "   déploiement lancé en arrière-plan (5 à 10 min)"
fi

echo "Suivi : az network bastion show -g ${RG} -n ${BAS} --query provisioningState -o tsv"
