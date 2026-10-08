#!/usr/bin/env bash
# lyon-nat.sh — accès Internet sortant du site de Lyon simulé (FORMATRICE uniquement)
# Le serveur vm-stNN-lyon-fs n'a pas d'IP publique. Au module 6, il doit joindre Internet
# (téléchargement de l'agent Azure File Sync, modules PowerShell, service de synchronisation
# en HTTPS 443) ; au module 9, l'agent MARS. L'accès sortant implicite des VMs est en cours
# de retrait [À VÉRIFIER] statut des sous-réseaux de vnet-lyon : une passerelle NAT partagée
# rend l'accès sortant explicite et identique pour tous.
#   natgw-lyon + pip-lyon-natgw (West Europe), associée à tous les sous-réseaux snet-stNN
#
# Usage :
#   ./lyon-nat.sh create     J3 08:30 : passerelle NAT créée et associée (idempotent)
#   ./lyon-nat.sh status     sous-réseaux associés et IP publique de sortie
#   ./lyon-nat.sh cleanup    fin de J4 (après le module 9) : dissociation puis suppression
set -euo pipefail

ACTION="${1:?Action requise : create, status ou cleanup}"
RG_LYON="${RG_LYON:-rg-formation-lyon}"
LOC="westeurope"
NAT="natgw-lyon"
PIP="pip-lyon-natgw"
TAGS=(Projet=Arveo Environnement=Formation Proprietaire=formatrice)

subnets() {   # sous-réseaux des stagiaires dans vnet-lyon
  az network vnet subnet list -g "$RG_LYON" --vnet-name vnet-lyon \
    --query "[?starts_with(name, 'snet-st')].name" -o tsv
}

case "$ACTION" in
  create)
    if ! az network public-ip show -g "$RG_LYON" -n "$PIP" -o none 2>/dev/null; then
      az network public-ip create -g "$RG_LYON" -n "$PIP" -l "$LOC" \
        --sku Standard --allocation-method Static --tags "${TAGS[@]}" -o none
      echo "IP publique ${PIP} créée"
    fi
    if ! az network nat gateway show -g "$RG_LYON" -n "$NAT" -o none 2>/dev/null; then
      az network nat gateway create -g "$RG_LYON" -n "$NAT" -l "$LOC" \
        --public-ip-addresses "$PIP" --idle-timeout 10 --tags "${TAGS[@]}" -o none
      echo "Passerelle NAT ${NAT} créée"
    fi
    for SN in $(subnets); do
      az network vnet subnet update -g "$RG_LYON" --vnet-name vnet-lyon -n "$SN" \
        --nat-gateway "$NAT" -o none
      echo "${SN} : sortie Internet par ${NAT}"
    done
    echo "IP de sortie du site de Lyon : $(az network public-ip show -g "$RG_LYON" -n "$PIP" \
      --query ipAddress -o tsv)"
    ;;

  status)
    az network vnet subnet list -g "$RG_LYON" --vnet-name vnet-lyon \
      --query "[?starts_with(name, 'snet-st')].{SousReseau:name, NAT:natGateway.id}" -o table \
      | sed 's#/subscriptions/.*/natGateways/##'
    az network public-ip show -g "$RG_LYON" -n "$PIP" --query ipAddress -o tsv 2>/dev/null \
      || echo "Aucune passerelle NAT"
    ;;

  cleanup)
    for SN in $(subnets); do
      az network vnet subnet update -g "$RG_LYON" --vnet-name vnet-lyon -n "$SN" \
        --remove natGateway -o none 2>/dev/null || true   # [À VÉRIFIER] syntaxe selon la version d'Azure CLI
      echo "${SN} : passerelle NAT retirée"
    done
    az network nat gateway delete -g "$RG_LYON" -n "$NAT" 2>/dev/null || true
    az network public-ip delete -g "$RG_LYON" -n "$PIP" 2>/dev/null || true
    az resource list -g "$RG_LYON" --query "[].{Nom:name, Type:type}" -o table
    ;;

  *)
    echo "Action inconnue : ${ACTION} (create, status ou cleanup)" >&2
    exit 1
    ;;
esac
