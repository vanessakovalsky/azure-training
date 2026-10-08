#!/usr/bin/env bash
# preparer-supervision.sh — module 10, à lancer à 13:30 (J4) par CHAQUE stagiaire (2 à 4 min)
# Les journaux de ressources n'ont aucun historique : activés dès le début du module, ils
# alimentent les requêtes du lab 10.3 (vers 14:35) et Traffic analytics (lab 10.5, 15:30).
# 1. VMs web démarrées si besoin (en fonctionnement depuis 09:00, module 9)
# 2. Instances de vmss-stNN-api démarrées, mise à l'échelle as-stNN-api réactivée
#    (désactivées par cleanup/module-07-vm.sh en fin de J3)
# 3. vm-stNN-test-data démarrée : base de test du ticket ERP (lab 10.5)
# 4. Extension NetworkWatcherAgentLinux sur vm-stNN-web01 (résolution des problèmes de connexion)
# 5. Paramètres de diagnostic diag-arveo vers log-stNN-shared :
#    coffre rsv-stNN-arveo (6 catégories Azure Backup, tables spécifiques à la ressource),
#    nsg-stNN-web (allLogs). Paramètre existant vers un espace de travail : conservé.
# 6. Sauvegarde immédiate de partage-lyon : travail visible dans AddonAzureBackupJobs
# 7. Journal de flux de VNet fl-stNN-spoke-app (NetworkWatcherRG), stockage starveostNNdiag,
#    Traffic analytics toutes les 10 min vers log-stNN-shared
# 8. Contrôle : pulsations reçues dans les 15 dernières minutes
# Idempotent : relançable sans risque.
# Usage : ./preparer-supervision.sh <NN>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
SHARED="rg-${ST}-shared"
APP="rg-${ST}-app"
SPOKE="rg-${ST}-spoke"
LOC="francecentral"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")
VAULT="rsv-${ST}-arveo"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true
exists() { az "$@" -o none 2>/dev/null; }

WS_ID=$(az monitor log-analytics workspace show -g "$SHARED" -n "log-${ST}-shared" \
  --query id -o tsv 2>/dev/null || true)
[[ -n "$WS_ID" ]] || { echo "log-${ST}-shared absent : ./scripts/catch-up/module-03/deploy.sh ${NN}" >&2; exit 1; }

echo "== VMs web"
for VM in web01 web02; do
  exists vm show -g "$APP" -n "vm-${ST}-${VM}" \
    || { echo "   vm-${ST}-${VM} absente : ./scripts/catch-up/module-07/deploy.sh ${NN}" >&2; exit 1; }
  az vm start -g "$APP" -n "vm-${ST}-${VM}" -o none
  echo "   vm-${ST}-${VM} : $(az vm get-instance-view -g "$APP" -n "vm-${ST}-${VM}" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0]" -o tsv)"
done

echo "== API vmss-${ST}-api"
API_VMS=$(az vm list -g "$APP" --query "[?virtualMachineScaleSet!=null].name" -o tsv)
if [[ -z "$API_VMS" ]]; then
  echo "   aucune instance (défi 07.5 non réalisé) : lab 10.5, test de l'API sans cible"
else
  N=0
  for V in $API_VMS; do
    az vm start -g "$APP" -n "$V" --no-wait
    N=$((N + 1))
  done
  if exists monitor autoscale show -g "$APP" -n "as-${ST}-api"; then
    az monitor autoscale update -g "$APP" -n "as-${ST}-api" --enabled true -o none
  fi
  echo "   ${N} instance(s) : démarrage lancé ; mise à l'échelle as-${ST}-api réactivée"
fi

echo "== VM de test de la base (vm-${ST}-test-data)"
if exists vm show -g "$SPOKE" -n "vm-${ST}-test-data"; then
  az vm start -g "$SPOKE" -n "vm-${ST}-test-data" --no-wait
  echo "   démarrage lancé (lab 10.5)"
else
  echo "   absente : diagnostic du lab 10.5 identique (route absente), sans service SQL"
fi

echo "== Agent Network Watcher sur vm-${ST}-web01"
az vm extension set -g "$APP" --vm-name "vm-${ST}-web01" \
  --publisher Microsoft.Azure.NetworkWatcher --name NetworkWatcherAgentLinux -o none
echo "   NetworkWatcherAgentLinux : $(az vm extension show -g "$APP" --vm-name "vm-${ST}-web01" \
  -n NetworkWatcherAgentLinux --query provisioningState -o tsv)"

echo "== Paramètres de diagnostic vers log-${ST}-shared"
diag() {   # diag <ID_RESSOURCE> <JSON_JOURNAUX> <TABLES_SPECIFIQUES:true|false> <LIBELLE>
  local ID="$1" N
  N=$(az monitor diagnostic-settings list --resource "$ID" \
    --query "[?workspaceId!=null] | length(@)" -o tsv)
  if [[ "$N" != "0" ]]; then
    echo "   ${ID##*/} : paramètre vers un espace de travail déjà présent (conservé)"
    return
  fi
  az monitor diagnostic-settings create -n diag-arveo --resource "$ID" --workspace "$WS_ID" \
    --logs "$2" --export-to-resource-specific "$3" -o none
  echo "   ${ID##*/} : diag-arveo créé ($4)"
}
VAULT_ID=$(az backup vault show -g "$SHARED" -n "$VAULT" --query id -o tsv 2>/dev/null || true)
if [[ -n "$VAULT_ID" ]]; then
  CATS=""
  for C in CoreAzureBackup AddonAzureBackupJobs AddonAzureBackupAlerts AddonAzureBackupPolicy \
           AddonAzureBackupStorage AddonAzureBackupProtectedInstance; do
    CATS="${CATS}{\"category\":\"${C}\",\"enabled\":true},"
  done
  diag "$VAULT_ID" "[${CATS%,}]" true "6 catégories, tables spécifiques à la ressource"
else
  echo "   ${VAULT} absent : ./scripts/catch-up/module-09/deploy.sh ${NN} <SES>" >&2
fi
NSG_ID=$(az network nsg show -g "$SPOKE" -n "nsg-${ST}-web" --query id -o tsv)
diag "$NSG_ID" '[{"categoryGroup":"allLogs","enabled":true}]' false "allLogs"

echo "== Sauvegarde de partage-lyon (travail pour la table AddonAzureBackupJobs)"
CONT=""; ITEM=""
if [[ -n "$VAULT_ID" ]]; then
  read -r CONT ITEM < <(az backup item list -g "$SHARED" -v "$VAULT" \
    --backup-management-type AzureStorage --workload-type AzureFileShare \
    --query "[?properties.friendlyName=='partage-lyon'] | [0].[properties.containerName, name]" \
    -o tsv 2>/dev/null) || true
fi
if [[ -n "$ITEM" ]]; then
  STATUS=$(az backup protection backup-now -g "$SHARED" -v "$VAULT" --container-name "$CONT" \
    --item-name "$ITEM" --backup-management-type AzureStorage \
    --retain-until "$(date -d '+30 days' +%d-%m-%Y)" --query "properties.status" -o tsv 2>/dev/null) \
    || STATUS="non lancé (sauvegarde déjà en cours ?)"
  echo "   travail lancé : ${STATUS}"
else
  echo "   partage-lyon non protégé : table alimentée par les seuls travaux des VMs"
fi

echo "== Journal de flux de VNet fl-${ST}-spoke-app (Traffic analytics toutes les 10 min)"
DIAG_SA_ID=$(az storage account list -g "$SHARED" \
  --query "[?starts_with(name, 'starveost${NN}diag')].id | [0]" -o tsv)
[[ -n "$DIAG_SA_ID" ]] || { echo "   starveost${NN}diag absent : ./scripts/catch-up/module-03/deploy.sh ${NN}" >&2; exit 1; }
if exists network watcher flow-log show --location "$LOC" --name "fl-${ST}-spoke-app"; then
  echo "   déjà présent"
else
  # [À VÉRIFIER] option --vnet selon la version d'Azure CLI (journaux de flux de VNet)
  az network watcher flow-log create --location "$LOC" --name "fl-${ST}-spoke-app" \
    --vnet "$(az network vnet show -g "$SPOKE" -n "vnet-${ST}-spoke-app" --query id -o tsv)" \
    --storage-account "$DIAG_SA_ID" --retention 7 \
    --traffic-analytics true --workspace "$WS_ID" --interval 10 \
    --tags "${TAGS[@]}" -o none
  echo "   créé dans NetworkWatcherRG (stockage ${DIAG_SA_ID##*/})"
fi

echo "== Pulsations des 15 dernières minutes (log-${ST}-shared)"
WS=$(az monitor log-analytics workspace show --ids "$WS_ID" --query customerId -o tsv)
HB=$(az monitor log-analytics query -w "$WS" \
  --analytics-query "Heartbeat | where TimeGenerated > ago(15m) | distinct Computer | order by Computer asc" \
  --query "[].Computer" -o tsv | tr '\n' ' ')
[[ -n "$HB" ]] || HB="AUCUNE : vérifier l'agent Azure Monitor (lab 07.7)"
echo "   ${HB}"
