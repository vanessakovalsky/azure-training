#!/usr/bin/env bash
# Rattrapage module 10 — supervision Arvéo (rg-stNN-shared, rg-stNN-app, NetworkWatcherRG)
# 1. Prérequis : espace de travail (M3), VMs web et Load Balancer (M7)
# 2. Préparation de 13:30 (labs/module-10/preparer-supervision.sh) : VMs démarrées, extension
#    Network Watcher, diagnostic du coffre et du NSG, journal de flux fl-stNN-spoke-app
# 3. Groupe d'actions, alertes, fonction KQL, diagnostic du Load Balancer : main.bicep
# 4. Contrôles
# Durée : 10 à 15 min. Idempotent.
# Usage : ./deploy.sh <NN> <COURRIEL>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
COURRIEL="${2:?Adresse de messagerie requise (notifications des alertes)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
[[ "$COURRIEL" == *@*.* ]] || { echo "Adresse invalide : $COURRIEL" >&2; exit 1; }
ST="st${NN}"
SHARED="rg-${ST}-shared"
APP="rg-${ST}-app"
DIR="$(cd "$(dirname "$0")" && pwd)"
LABS="${DIR}/../../labs/module-10"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true
exists() { az "$@" -o none 2>/dev/null; }

echo "== Étape 1/4 : prérequis"
exists monitor log-analytics workspace show -g "$SHARED" -n "log-${ST}-shared" \
  || { echo "   log-${ST}-shared absent : ./scripts/catch-up/module-03/deploy.sh ${NN}" >&2; exit 1; }
exists network lb show -g "$APP" -n "lbe-${ST}-web" \
  || { echo "   lbe-${ST}-web absent : ./scripts/catch-up/module-07/deploy.sh ${NN}" >&2; exit 1; }
echo "   espace de travail et Load Balancer présents"

echo "== Étape 2/4 : préparation de la supervision"
"${LABS}/preparer-supervision.sh" "$NN"

echo "== Étape 3/4 : groupe d'actions, alertes, fonction KQL (main.bicep)"
az deployment group create -g "$SHARED" -n rattrapage-m10 \
  --template-file "${DIR}/main.bicep" \
  --parameters numero="$NN" courriel="$COURRIEL" \
  --query "properties.outputs.alertes.value" -o tsv

echo "== Étape 4/4 : contrôles"
az monitor metrics alert list -g "$SHARED" -o table \
  --query "[].{Regle:name, Gravite:severity, Active:enabled, Fenetre:windowSize}"
az monitor activity-log alert list -g "$SHARED" -o table --query "[].{Regle:name, Active:enabled}"
az monitor scheduled-query list -g "$SHARED" -o table \
  --query "[].{Regle:name, Gravite:severity, Frequence:evaluationFrequency}"
az monitor log-analytics workspace saved-search list -g "$SHARED" --workspace-name "log-${ST}-shared" \
  -o table --query "[?category=='Arveo'].{Requete:displayName, Fonction:functionAlias}"
echo "Courriel de confirmation du groupe d'actions envoyé à ${COURRIEL}."
echo "Traffic analytics : premières lignes NTANetAnalytics 20 à 30 min après la création du journal de flux."
