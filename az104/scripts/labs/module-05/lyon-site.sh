#!/usr/bin/env bash
# lyon-site.sh — côté « site de Lyon » du module 5 (FORMATRICE uniquement)
# Le site de Lyon simulé est partagé : vnet-lyon (10.200.0.0/16, West Europe) et sa passerelle
# vpngw-lyon dans le groupe $RG_LYON (défaut rg-formation-lyon). Les stagiaires n'y ont que
# la lecture, plus le rôle Contributeur de réseau sur LEUR sous-réseau snet-stNN.
#
# Usage :
#   DOMAINE=<DOMAINE> ./lyon-site.sh prepare [NN ...]
#       J-1 : vnet-lyon + GatewaySubnet, sous-réseaux snet-stNN 10.200.NN.0/24, rôle Contributeur
#       de réseau du compte stNN@<DOMAINE> sur son sous-réseau. À lancer AVANT
#       « prereq-vpn-gateways.sh lyon » (VNet non modifiable pendant le déploiement de la passerelle).
#   ./lyon-site.sh connect [NN ...]
#       J2 avant 13:30 : pour chaque stagiaire, passerelle de réseau local lng-lyon-stNN
#       (IP de pip-stNN-vpngw, plage 10.NN.0.0/20) et connexion cn-lyon-to-stNN.
#       Clé partagée : variable PSK (clé commune) ou, à défaut, une clé aléatoire par stagiaire,
#       conservée dans ~/.arveo/psk-lyon.txt (réutilisée si le script est relancé).
#   ./lyon-site.sh status
#       État de toutes les connexions côté Lyon.
#   ./lyon-site.sh cleanup
#       Fin de J2 : connexions, passerelles de réseau local, vpngw-lyon et son IP supprimées.
#       vnet-lyon, sous-réseaux et VMs des stagiaires conservés (M6).
# Sans liste de numéros : tous les stagiaires possédant un groupe rg-stNN-hub.
set -euo pipefail

ACTION="${1:?Action requise : prepare, connect, status ou cleanup}"
shift || true
RG_LYON="${RG_LYON:-rg-formation-lyon}"
LOC="westeurope"
PSK_FILE="$HOME/.arveo/psk-lyon.txt"
TAGS=(Projet=Arveo Environnement=Formation Proprietaire=formatrice)

stagiaires() {
  if (( $# > 0 )); then
    printf '%s\n' "$@"
  else
    az group list --query "[?starts_with(name, 'rg-st') && ends_with(name, '-hub')].name" -o tsv \
      | sed -E 's/^rg-st([0-9]{2})-hub$/\1/' | sort
  fi
}

psk_for() {   # psk_for <NN> : clé commune ($PSK) ou clé propre au stagiaire, créée au besoin
  local nn="$1" key
  if [[ -n "${PSK:-}" ]]; then
    echo "$PSK"
    return
  fi
  mkdir -p "$(dirname "$PSK_FILE")"
  touch "$PSK_FILE" && chmod 600 "$PSK_FILE"
  key=$(awk -v s="st${nn}" '$1 == s {print $2}' "$PSK_FILE")
  if [[ -z "$key" ]]; then
    key=$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-32)
    echo "st${nn} ${key}" >> "$PSK_FILE"
  fi
  echo "$key"
}

case "$ACTION" in
  prepare)
    : "${DOMAINE:?Variable DOMAINE requise (ex. arveoformation.onmicrosoft.com)}"
    if ! az network vnet show -g "$RG_LYON" -n vnet-lyon -o none 2>/dev/null; then
      az network vnet create -g "$RG_LYON" -n vnet-lyon -l "$LOC" \
        --address-prefixes 10.200.0.0/16 \
        --subnet-name GatewaySubnet --subnet-prefixes 10.200.255.0/27 \
        --tags "${TAGS[@]}" -o none
      echo "vnet-lyon créé (10.200.0.0/16, GatewaySubnet 10.200.255.0/27)"
    fi
    for NN in $(stagiaires "$@"); do
      OCT=$((10#$NN)); ST="st${NN}"
      if ! az network vnet subnet show -g "$RG_LYON" --vnet-name vnet-lyon -n "snet-${ST}" \
          -o none 2>/dev/null; then
        az network vnet subnet create -g "$RG_LYON" --vnet-name vnet-lyon -n "snet-${ST}" \
          --address-prefixes "10.200.${OCT}.0/24" -o none
      fi
      SUBNET_ID=$(az network vnet subnet show -g "$RG_LYON" --vnet-name vnet-lyon \
        -n "snet-${ST}" --query id -o tsv)
      az role assignment create --assignee "${ST}@${DOMAINE}" --role "Network Contributor" \
        --scope "$SUBNET_ID" -o none
      echo "snet-${ST} 10.200.${OCT}.0/24 : prêt, Contributeur de réseau pour ${ST}@${DOMAINE}"
    done
    ;;

  connect)
    STATE=$(az network vnet-gateway show -g "$RG_LYON" -n vpngw-lyon \
      --query provisioningState -o tsv 2>/dev/null || echo "Absente")
    [[ "$STATE" == "Succeeded" ]] || { echo "vpngw-lyon : ${STATE} (attendre Succeeded)" >&2; exit 1; }
    for NN in $(stagiaires "$@"); do
      OCT=$((10#$NN)); ST="st${NN}"
      PIP=$(az network public-ip show -g "rg-${ST}-hub" -n "pip-${ST}-vpngw" \
        --query ipAddress -o tsv 2>/dev/null || true)
      if [[ -z "$PIP" ]]; then
        echo "${ST} : pip-${ST}-vpngw sans adresse (passerelle absente) : ignoré" >&2
        continue
      fi
      if ! az network local-gateway show -g "$RG_LYON" -n "lng-lyon-${ST}" -o none 2>/dev/null; then
        az network local-gateway create -g "$RG_LYON" -n "lng-lyon-${ST}" -l "$LOC" \
          --gateway-ip-address "$PIP" --local-address-prefixes "10.${OCT}.0.0/20" \
          --tags "${TAGS[@]}" -o none
      fi
      if az network vpn-connection show -g "$RG_LYON" -n "cn-lyon-to-${ST}" -o none 2>/dev/null; then
        echo "${ST} : connexion cn-lyon-to-${ST} déjà présente"
      else
        az network vpn-connection create -g "$RG_LYON" -n "cn-lyon-to-${ST}" \
          --vnet-gateway1 vpngw-lyon --local-gateway2 "lng-lyon-${ST}" \
          --shared-key "$(psk_for "$NN")" --tags "${TAGS[@]}" -o none
        echo "${ST} : lng-lyon-${ST} (${PIP}, 10.${OCT}.0.0/20) + cn-lyon-to-${ST} créées"
      fi
    done
    if [[ -z "${PSK:-}" ]]; then
      echo "== Clés à transmettre (une par stagiaire) : ${PSK_FILE}"
      cat "$PSK_FILE"
    else
      echo "== Clé commune à transmettre : variable PSK"
    fi
    ;;

  status)
    az network vpn-connection list -g "$RG_LYON" \
      --query "[].{Connexion:name, Etat:connectionStatus, Provisionnement:provisioningState}" \
      -o table
    ;;

  cleanup)
    for CN in $(az network vpn-connection list -g "$RG_LYON" --query "[].name" -o tsv); do
      az network vpn-connection delete -g "$RG_LYON" -n "$CN"
      echo "Connexion ${CN} supprimée"
    done
    for LNG in $(az network local-gateway list -g "$RG_LYON" --query "[].name" -o tsv); do
      az network local-gateway delete -g "$RG_LYON" -n "$LNG"
      echo "Passerelle locale ${LNG} supprimée"
    done
    if az network vnet-gateway show -g "$RG_LYON" -n vpngw-lyon -o none 2>/dev/null; then
      echo "Suppression de vpngw-lyon (10 à 20 min)"
      az network vnet-gateway delete -g "$RG_LYON" -n vpngw-lyon
    fi
    az network public-ip delete -g "$RG_LYON" -n pip-lyon-vpngw 2>/dev/null || true
    az resource list -g "$RG_LYON" --query "[].{Nom:name, Type:type}" -o table
    ;;

  *)
    echo "Action inconnue : ${ACTION} (prepare, connect, status ou cleanup)" >&2
    exit 1
    ;;
esac
