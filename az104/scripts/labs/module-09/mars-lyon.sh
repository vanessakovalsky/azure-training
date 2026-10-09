#!/usr/bin/env bash
# mars-lyon.sh — agent MARS sur le serveur de Lyon simulé (module 9, lab 09.1 étape 6)
#   1. Démarrage de vm-stNN-lyon-fs (désallouée en fin de matinée du J3)
#   2. Phrase secrète MARS générée une fois : ~/.arveo/mars-passphrase.txt (Cloud Shell,
#      JAMAIS sur le serveur protégé : sans elle, aucune restauration possible)
#   3. Commande d'exécution managée « mars-install », ASYNCHRONE (10 à 15 min) : mars-install.ps1
#      (exports F:\Compta, agent MARS, modules Az, inscription auprès de rsv-stNN-arveo)
# Prérequis : coffre rsv-stNN-arveo (lancer-sauvegarde.sh), identité managée du serveur (module 6)
# avec le rôle « Backup Contributor » sur le coffre, sortie Internet (formatrice : lyon-nat.sh).
# Idempotent. Option --wait : attend la fin (rattrapage).
# Usage : ./mars-lyon.sh <NN> [--wait]      Suivi : ./mars-lyon.sh <NN> --status
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
MODE="${2:-}"
ST="st${NN}"
RG="rg-${ST}-lyon"
RG_SHARED="rg-${ST}-shared"
LOC="francecentral"
VM="vm-${ST}-lyon-fs"
VAULT="rsv-${ST}-arveo"
RC="mars-install"
PP_FILE="${HOME}/.arveo/mars-passphrase.txt"
DIR="$(cd "$(dirname "$0")" && pwd)"

state() {
  az vm run-command show -g "$RG" --vm-name "$VM" -n "$RC" --instance-view \
    --query instanceView.executionState -o tsv 2>/dev/null || echo "Absente"
}

if [[ "$MODE" == "--status" ]]; then
  az vm run-command show -g "$RG" --vm-name "$VM" -n "$RC" --instance-view \
    --query "instanceView.{Etat:executionState, Debut:startTime, Fin:endTime}" -o table 2>/dev/null \
    || { echo "Commande ${RC} absente : lancer ./mars-lyon.sh ${NN}"; exit 0; }
  az vm run-command show -g "$RG" --vm-name "$VM" -n "$RC" --instance-view \
    --query "[instanceView.output, instanceView.error]" -o tsv 2>/dev/null || true
  exit 0
fi

az vm show -g "$RG" -n "$VM" -o none 2>/dev/null \
  || { echo "${VM} introuvable : ./scripts/labs/module-05/lyon-vm.sh ${NN} puis module 6" >&2; exit 1; }
az backup vault show -g "$RG_SHARED" -n "$VAULT" -o none 2>/dev/null \
  || { echo "${VAULT} introuvable : ./scripts/labs/module-09/lancer-sauvegarde.sh ${NN}" >&2; exit 1; }

echo "== Serveur ${VM}"
az vm start -g "$RG" -n "$VM" -o none
PRINCIPAL=$(az vm show -g "$RG" -n "$VM" --query identity.principalId -o tsv)
[[ -n "$PRINCIPAL" ]] \
  || { echo "   aucune identité managée : az vm identity assign -g ${RG} -n ${VM}" >&2; exit 1; }
echo "   en fonctionnement"

echo "== Phrase secrète MARS"
mkdir -p "$(dirname "$PP_FILE")"
if [[ -s "$PP_FILE" ]]; then
  echo "   conservée : ${PP_FILE}"
else
  ( umask 077; openssl rand -hex 16 > "$PP_FILE" )
  echo "   générée : ${PP_FILE} ($(tr -d '\n' < "$PP_FILE" | wc -c) caractères)"
fi

echo "== Installation et inscription de l'agent MARS (commande d'exécution managée ${RC})"
STATE=$(state)
if [[ "$STATE" == "Succeeded" || "$STATE" == "Running" ]]; then
  echo "   ${RC} déjà ${STATE} : conservée"
else
  [[ "$STATE" == "Absente" ]] || az vm run-command delete -g "$RG" --vm-name "$VM" -n "$RC" --yes -o none
  az vm run-command create -g "$RG" --vm-name "$VM" -n "$RC" -l "$LOC" \
    --script @"${DIR}/mars-install.ps1" \
    --parameters "SubscriptionId=$(az account show --query id -o tsv)" \
                 "ResourceGroup=${RG_SHARED}" "VaultName=${VAULT}" \
    --protected-parameters "Passphrase=$(tr -d '\n' < "$PP_FILE")" \
    --async-execution true --timeout-in-seconds 3600 -o none
  echo "   ${RC} lancée en arrière-plan (10 à 15 min)"
fi

if [[ "$MODE" == "--wait" ]]; then
  for _ in $(seq 1 60); do
    STATE=$(state)
    [[ "$STATE" == "Succeeded" || "$STATE" == "Failed" || "$STATE" == "TimedOut" ]] && break
    sleep 30
  done
  echo "   ${RC} : ${STATE}"
  [[ "$STATE" == "Succeeded" ]] || { echo "   voir : ./mars-lyon.sh ${NN} --status" >&2; exit 1; }
fi

echo "Suivi : ./scripts/labs/module-09/mars-lyon.sh ${NN} --status"
