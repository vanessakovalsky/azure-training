#!/usr/bin/env bash
# lancer-sauvegarde.sh — préparation de la sauvegarde Arvéo (module 9), J4 09:00 (début du M8)
# La première sauvegarde d'une VM dure de 30 min à plus d'une heure : elle est lancée le matin
# pour disposer d'un point de récupération de web01 au module 9 (11:00).
#   1. Démarrage de vm-stNN-web01 et vm-stNN-web02 (désallouées en fin de J3) et du serveur de
#      Lyon vm-stNN-lyon-fs (agent MARS, lab 09.3), sans attente pour ce dernier
#   2. Données métier de web01 : /srv/arveo/contrats (5 fichiers, disque de données du LUN 0)
#   3. Coffre rsv-stNN-arveo (rg-stNN-shared, France Central), stockage de sauvegarde LRS
#      réglé AVANT toute protection (verrouillé ensuite)
#   4. Stratégie pol-vm-arveo (Améliorée, obligatoire pour les VMs à lancement fiable)
#   5. Protection de vm-stNN-web01 puis sauvegarde immédiate (conservée 30 jours)
# Idempotent : coffre, stratégie et protection existants conservés.
# Usage : ./lancer-sauvegarde.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
RG_APP="rg-${ST}-app"
RG_SHARED="rg-${ST}-shared"
RG_LYON_ST="rg-${ST}-lyon"
LOC="francecentral"
VAULT="rsv-${ST}-arveo"
POLICY="pol-vm-arveo"
DIR="$(cd "$(dirname "$0")" && pwd)"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true

echo "== Démarrage des VMs"
for VM in web01 web02; do
  az vm show -g "$RG_APP" -n "vm-${ST}-${VM}" -o none 2>/dev/null \
    || { echo "   vm-${ST}-${VM} absente : ./scripts/catch-up/module-07/deploy.sh ${NN}" >&2; exit 1; }
  STATE=$(az vm get-instance-view -g "$RG_APP" -n "vm-${ST}-${VM}" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState')].code | [0]" -o tsv)
  [[ "$STATE" == "PowerState/running" ]] || az vm start -g "$RG_APP" -n "vm-${ST}-${VM}" -o none
  echo "   vm-${ST}-${VM} : démarrée"
done
if az vm start -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" --no-wait 2>/dev/null; then
  echo "   vm-${ST}-lyon-fs : démarrage lancé (agent MARS, lab 09.3)"
else
  echo "   vm-${ST}-lyon-fs absente : ./scripts/labs/module-05/lyon-vm.sh ${NN} puis module 6" >&2
fi

echo "== Données métier de web01 (/srv/arveo/contrats)"
read -r -d '' SEED <<'EOS' || true
set -e
mountpoint -q /srv/arveo || mount /srv/arveo
mkdir -p /srv/arveo/contrats
for i in 01 02 03 04 05; do
  F=/srv/arveo/contrats/contrat-transporteur-${i}.txt
  [ -s "$F" ] || printf 'Contrat-cadre transporteur %s - Arveo Logistique - signe le 2026-09-%s\n' \
    "$i" "1${i#0}" > "$F"
done
sync
echo "   $(ls /srv/arveo/contrats | wc -l) fichiers dans /srv/arveo/contrats"
EOS
az vm run-command invoke -g "$RG_APP" -n "vm-${ST}-web01" --command-id RunShellScript \
  --scripts "$SEED" --query "value[0].message" -o tsv \
  | sed -n '/\[stdout\]/,/\[stderr\]/p' | sed '1d;$d'

echo "== Coffre ${VAULT} (${RG_SHARED}, ${LOC})"
if az backup vault show -g "$RG_SHARED" -n "$VAULT" -o none 2>/dev/null; then
  echo "   déjà présent ; stockage de sauvegarde : $(az backup vault backup-properties show \
    -g "$RG_SHARED" -n "$VAULT" --query "[0].properties.storageModelType" -o tsv)"
else
  az backup vault create -g "$RG_SHARED" -n "$VAULT" -l "$LOC" --tags "${TAGS[@]}" -o none
  # Redondance réglable tant qu'aucun élément n'est protégé (LRS : coût réduit en formation)
  az backup vault backup-properties set -g "$RG_SHARED" -n "$VAULT" \
    --backup-storage-redundancy LocallyRedundant -o none
  echo "   créé ; stockage de sauvegarde : LocallyRedundant"
fi

echo "== Stratégie ${POLICY} (Améliorée, 22:00, instantanés 7 j)"
if az backup policy show -g "$RG_SHARED" -v "$VAULT" -n "$POLICY" -o none 2>/dev/null; then
  echo "   déjà présente"
else
  az backup policy create -g "$RG_SHARED" -v "$VAULT" -n "$POLICY" \
    --backup-management-type AzureIaasVM --policy @"${DIR}/pol-vm-arveo.json" -o none
  echo "   créée"
fi

echo "== Protection de vm-${ST}-web01"
item() {   # noms internes « conteneur élément » de la VM protégée
  az backup item list -g "$RG_SHARED" -v "$VAULT" \
    --backup-management-type AzureIaasVM --workload-type VM \
    --query "[?properties.friendlyName=='vm-${ST}-web01'] | [0].[properties.containerName, name]" -o tsv
}
if [[ -n "$(item)" ]]; then
  echo "   déjà protégée"
else
  az backup protection enable-for-vm -g "$RG_SHARED" -v "$VAULT" --policy-name "$POLICY" \
    --vm "$(az vm show -g "$RG_APP" -n "vm-${ST}-web01" --query id -o tsv)" -o none
  echo "   protection activée"
fi

RETAIN=$(date -d '+30 days' +%d-%m-%Y)
echo "== Sauvegarde immédiate de vm-${ST}-web01 (conservée jusqu'au ${RETAIN})"
RUNNING=$(az backup job list -g "$RG_SHARED" -v "$VAULT" --status InProgress \
  --query "[?properties.entityFriendlyName=='vm-${ST}-web01' && properties.operation=='Backup'] | length(@)" \
  -o tsv)
if [[ "$RUNNING" != "0" ]]; then
  echo "   sauvegarde déjà en cours : conservée"
else
  read -r CONT ITEM < <(item)
  JOB=$(az backup protection backup-now -g "$RG_SHARED" -v "$VAULT" \
    --container-name "$CONT" --item-name "$ITEM" --backup-management-type AzureIaasVM \
    --retain-until "$RETAIN" --query name -o tsv)
  echo "   travail lancé : ${JOB}"
fi
echo "Suivi : az backup job list -g ${RG_SHARED} -v ${VAULT} -o table"
