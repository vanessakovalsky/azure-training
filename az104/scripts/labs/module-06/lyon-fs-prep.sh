#!/usr/bin/env bash
# lyon-fs-prep.sh — serveur de fichiers de Lyon prêt pour Azure File Sync (module 6, J3 09:00)
#   1. Démarrage de vm-stNN-lyon-fs (arrêtée en fin de J2) et de vm-stNN-test-data (défi 06.4)
#   2. Disque de données disk-stNN-lyon-fs-data (32 Go, StandardSSD_LRS, tags) attaché en LUN 0
#      (hiérarchisation cloud impossible sur le volume système)
#   3. Identité managée affectée par le système (inscription du serveur sans mot de passe)
#   4. Commande d'exécution managée « prep-afs », ASYNCHRONE (10 à 15 min) : lyon-fs-prep.ps1
#      (volume F:, contenu du partage, agent Azure File Sync, modules Az)
# Prérequis : vm-stNN-lyon-fs (module 5, lyon-vm.sh) ; sortie Internet (formatrice : lyon-nat.sh).
# Idempotent. Option --wait : attend la fin de la préparation (rattrapage).
# Usage : ./lyon-fs-prep.sh <NN> [--wait]      Suivi : ./lyon-fs-prep.sh <NN> --status
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
MODE="${2:-}"
ST="st${NN}"
RG="rg-${ST}-lyon"
LOC="francecentral"
VM="vm-${ST}-lyon-fs"
DISK="disk-${ST}-lyon-fs-data"
RC="prep-afs"
DIR="$(cd "$(dirname "$0")" && pwd)"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")

status() {   # état de la commande d'exécution managée
  az vm run-command show -g "$RG" --vm-name "$VM" -n "$RC" --instance-view \
    --query "instanceView.{Etat:executionState, Debut:startTime, Fin:endTime}" -o table 2>/dev/null \
    || echo "Commande ${RC} absente : lancer ./lyon-fs-prep.sh ${NN}"
}

if [[ "$MODE" == "--status" ]]; then
  status
  az vm run-command show -g "$RG" --vm-name "$VM" -n "$RC" --instance-view \
    --query "instanceView.output" -o tsv 2>/dev/null || true
  exit 0
fi

az vm show -g "$RG" -n "$VM" -o none 2>/dev/null \
  || { echo "${VM} introuvable : ./scripts/labs/module-05/lyon-vm.sh ${NN}" >&2; exit 1; }

echo "== Démarrage des VMs"
az vm start -g "rg-${ST}-spoke" -n "vm-${ST}-test-data" --no-wait 2>/dev/null \
  || echo "   vm-${ST}-test-data absente (défi 06.4 : rattrapage M4 nécessaire)"
az vm start -g "$RG" -n "$VM" -o none
echo "   ${VM} démarrée"

echo "== Disque de données"
if ! az disk show -g "$RG" -n "$DISK" -o none 2>/dev/null; then
  az disk create -g "$RG" -n "$DISK" -l "$LOC" --size-gb 32 --sku StandardSSD_LRS \
    --tags "${TAGS[@]}" -o none
  echo "   ${DISK} créé (32 Go)"
fi
ATTACHED=$(az vm show -g "$RG" -n "$VM" \
  --query "storageProfile.dataDisks[?name=='${DISK}'] | length(@)" -o tsv)
if [[ "$ATTACHED" == "0" ]]; then
  az vm disk attach -g "$RG" --vm-name "$VM" --name "$DISK" --lun 0 -o none
  echo "   ${DISK} attaché (LUN 0)"
fi

echo "== Identité managée"
PRINCIPAL=$(az vm identity assign -g "$RG" -n "$VM" --query systemAssignedIdentity -o tsv)
echo "   ID de principal : ${PRINCIPAL}"

echo "== Préparation Windows (commande d'exécution managée ${RC})"
STATE=$(az vm run-command show -g "$RG" --vm-name "$VM" -n "$RC" --instance-view \
  --query instanceView.executionState -o tsv 2>/dev/null || echo "Absente")
if [[ "$STATE" == "Succeeded" || "$STATE" == "Running" ]]; then
  echo "   ${RC} déjà ${STATE} : conservée"
else
  az vm run-command create -g "$RG" --vm-name "$VM" -n "$RC" -l "$LOC" \
    --script @"${DIR}/lyon-fs-prep.ps1" \
    --async-execution true --timeout-in-seconds 3600 -o none
  echo "   ${RC} lancée en arrière-plan (10 à 15 min)"
fi

if [[ "$MODE" == "--wait" ]]; then
  for _ in $(seq 1 60); do
    STATE=$(az vm run-command show -g "$RG" --vm-name "$VM" -n "$RC" --instance-view \
      --query instanceView.executionState -o tsv)
    [[ "$STATE" == "Succeeded" || "$STATE" == "Failed" || "$STATE" == "TimedOut" ]] && break
    sleep 30
  done
  echo "   ${RC} : ${STATE}"
  [[ "$STATE" == "Succeeded" ]] || { echo "   voir : ./lyon-fs-prep.sh ${NN} --status" >&2; exit 1; }
fi

echo "Suivi : ./scripts/labs/module-06/lyon-fs-prep.sh ${NN} --status"
