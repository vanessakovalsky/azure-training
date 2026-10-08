#!/usr/bin/env bash
# prereq-vpn-gateways.sh — pré-déploiement des passerelles VPN (lancé à 09:00, jour 2)
# Provisionnement d'une passerelle VPN : 30 à 45 min, d'où un lancement avant le module 4.
#
# Usage :
#   ./prereq-vpn-gateways.sh <NN>    stagiaire : hub vnet-stNN-hub (tous les sous-réseaux du hub)
#                                    + passerelle vpngw-stNN-hub (rg-stNN-hub, France Central)
#   ./prereq-vpn-gateways.sh lyon    formatrice : vnet-lyon + passerelle vpngw-lyon partagée
#                                    (West Europe, groupe $RG_LYON, défaut rg-formation-lyon)
#
# Idempotent : chaque objet existant est conservé tel quel (aucun PUT sur un VNet existant,
# qui supprimerait les sous-réseaux absents de la commande).
set -euo pipefail

MODE="${1:?Argument requis : numéro de stagiaire sur deux chiffres (ex. 07) ou lyon}"

if [[ "$MODE" == "lyon" ]]; then
  RG="${RG_LYON:-rg-formation-lyon}"
  LOC="westeurope"
  OWNER="formatrice"
  VNET="vnet-lyon"
  VNET_PREFIX="10.200.0.0/16"
  GW_SUBNET_PREFIX="10.200.255.0/27"
  PIP="pip-lyon-vpngw"
  GW="vpngw-lyon"
  EXTRA_SUBNETS=()
elif [[ "$MODE" =~ ^[0-9]{2}$ ]]; then
  NN="$MODE"
  OCT=$((10#$NN))            # 07 -> 7 : pas de zéro en tête dans une adresse IP
  ST="st${NN}"
  RG="rg-${ST}-hub"
  LOC="francecentral"
  OWNER="$ST"
  VNET="vnet-${ST}-hub"
  VNET_PREFIX="10.${OCT}.0.0/22"
  GW_SUBNET_PREFIX="10.${OCT}.0.0/27"
  PIP="pip-${ST}-vpngw"
  GW="vpngw-${ST}-hub"
  # Sous-réseaux du hub créés dès maintenant : aucune modification du VNet
  # pendant le provisionnement de la passerelle.
  EXTRA_SUBNETS=(
    "AzureFirewallSubnet 10.${OCT}.0.64/26"
    "AzureFirewallManagementSubnet 10.${OCT}.0.128/26"
    "AzureBastionSubnet 10.${OCT}.1.0/26"
    "snet-shared 10.${OCT}.2.0/24"
  )
else
  echo "Argument invalide : '$MODE' (attendu : deux chiffres, ex. 07, ou lyon)" >&2
  exit 1
fi

TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${OWNER}")

echo "== Réseau ${VNET} (${VNET_PREFIX}) dans ${RG}"
if az network vnet show -g "$RG" -n "$VNET" -o none 2>/dev/null; then
  echo "   déjà présent : conservé"
else
  az network vnet create -g "$RG" -n "$VNET" -l "$LOC" \
    --address-prefixes "$VNET_PREFIX" \
    --subnet-name GatewaySubnet --subnet-prefixes "$GW_SUBNET_PREFIX" \
    --tags "${TAGS[@]}" -o none
  echo "   créé avec GatewaySubnet ${GW_SUBNET_PREFIX}"
fi

for entry in "${EXTRA_SUBNETS[@]}"; do
  read -r name prefix <<< "$entry"
  if az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$name" -o none 2>/dev/null; then
    echo "   sous-réseau ${name} déjà présent"
  else
    az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$name" \
      --address-prefixes "$prefix" -o none
    echo "   sous-réseau ${name} ${prefix} créé"
  fi
done

echo "== IP publique ${PIP} (Standard, zones 1 2 3)"
if az network public-ip show -g "$RG" -n "$PIP" -o none 2>/dev/null; then
  echo "   déjà présente : conservée"
else
  az network public-ip create -g "$RG" -n "$PIP" -l "$LOC" \
    --sku Standard --allocation-method Static --zone 1 2 3 \
    --tags "${TAGS[@]}" -o none
fi

echo "== Passerelle ${GW} (VpnGw1AZ, route-based)"
if az network vnet-gateway show -g "$RG" -n "$GW" -o none 2>/dev/null; then
  echo "   déjà présente : état $(az network vnet-gateway show -g "$RG" -n "$GW" \
    --query provisioningState -o tsv)"
else
  az network vnet-gateway create -g "$RG" -n "$GW" -l "$LOC" \
    --vnet "$VNET" --public-ip-addresses "$PIP" \
    --gateway-type Vpn --vpn-type RouteBased --sku VpnGw1AZ \
    --tags "${TAGS[@]}" --no-wait
  echo "   déploiement lancé en arrière-plan (30 à 45 min)"
fi

echo "Suivi : az network vnet-gateway show -g ${RG} -n ${GW} --query provisioningState -o tsv"
