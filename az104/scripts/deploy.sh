#!/usr/bin/env bash
# Rattrapage module 03 — socle partagé Arvéo dans rg-stNN-shared
# Crée ou réaligne : log-stNN-shared, starveostNNdiag[<SUFFIXE>], id-stNN-deploy
# Usage : ./deploy.sh <NN> [<SUFFIXE_STOCKAGE>]
#   <NN>                numéro de stagiaire sur deux chiffres (ex. 07)
#   <SUFFIXE_STOCKAGE>  facultatif, 2 à 4 minuscules ou chiffres si le nom est déjà pris
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
SUFFIXE="${2:-}"
RG="rg-st${NN}-shared"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Rattrapage M03 : groupe ${RG}"
az deployment group create \
  --resource-group "$RG" \
  --name "rattrapage-m03" \
  --template-file "${DIR}/main.bicep" \
  --parameters numero="$NN" storageName="starveost${NN}diag${SUFFIXE}" \
  --query "properties.outputs" -o json

az resource list --resource-group "$RG" --query "[].name" -o tsv
