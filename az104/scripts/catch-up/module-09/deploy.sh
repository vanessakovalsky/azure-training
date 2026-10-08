#!/usr/bin/env bash
# Rattrapage module 09 — protection des données Arvéo (rg-stNN-shared, -app, -data, -lyon)
# 1. Prérequis : VMs web du M7, compte de fichiers et partage du M6, serveur de Lyon
# 2. Coffre rsv-stNN-arveo et stratégies pol-vm-arveo, pol-files-arveo : main.bicep
# 3. web01 : démarrage, données /srv/arveo/contrats, protection, sauvegarde (lancer-sauvegarde.sh)
# 4. web02 : protection et sauvegarde immédiate
# 5. partage-lyon : protection et sauvegarde immédiate
# 6. Serveur de Lyon : rôle sur le coffre, agent MARS (mars-lyon.sh --wait), stratégie et
#    sauvegarde F:\Compta (mars-policy.ps1)
# 7. Contrôles
# Durée : 15 à 25 min (sauvegardes des VMs poursuivies en arrière-plan). Idempotent.
# Usage : ./deploy.sh <NN> <SES>
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
SES="${2:?Code de session du module 6 requis (ex. 2610)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
[[ "$SES" =~ ^[a-z0-9]{4}$ ]] || { echo "Code de session invalide : $SES" >&2; exit 1; }
ST="st${NN}"
SHARED="rg-${ST}-shared"
APP="rg-${ST}-app"
DATA="rg-${ST}-data"
LYON="rg-${ST}-lyon"
VAULT="rsv-${ST}-arveo"
SA_FILES="starveost${NN}files${SES}"
DIR="$(cd "$(dirname "$0")" && pwd)"
LABS="${DIR}/../../labs/module-09"
RETAIN=$(date -d '+30 days' +%d-%m-%Y)

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true
exists() { az "$@" -o none 2>/dev/null; }
item() {   # item <VM|AzureFileShare> <nom> : « conteneur élément » ou vide
  local BMT=AzureIaasVM; [[ "$1" == "AzureFileShare" ]] && BMT=AzureStorage
  az backup item list -g "$SHARED" -v "$VAULT" --backup-management-type "$BMT" --workload-type "$1" \
    --query "[?properties.friendlyName=='$2'] | [0].[properties.containerName, name]" -o tsv
}
backup_now() {   # backup_now <VM|AzureFileShare> <nom>
  local BMT=AzureIaasVM; [[ "$1" == "AzureFileShare" ]] && BMT=AzureStorage
  local CONT ITEM
  read -r CONT ITEM < <(item "$1" "$2")
  az backup protection backup-now -g "$SHARED" -v "$VAULT" --container-name "$CONT" \
    --item-name "$ITEM" --backup-management-type "$BMT" --retain-until "$RETAIN" \
    --query "properties.status" -o tsv
}

echo "== Étape 1/7 : prérequis"
for VM in web01 web02; do
  exists vm show -g "$APP" -n "vm-${ST}-${VM}" \
    || { echo "   vm-${ST}-${VM} absente : ./scripts/catch-up/module-07/deploy.sh ${NN}" >&2; exit 1; }
done
exists storage share-rm show -g "$DATA" --storage-account "$SA_FILES" -n partage-lyon \
  || { echo "   partage-lyon absent : ./scripts/catch-up/module-06/deploy.sh ${NN} ${SES}" >&2; exit 1; }
LYON_OK=true
exists vm show -g "$LYON" -n "vm-${ST}-lyon-fs" \
  || { LYON_OK=false; echo "   vm-${ST}-lyon-fs absente : partie MARS ignorée (module 5 puis 6)"; }
echo "   VMs web, partage et serveur de Lyon : vérifiés"

echo "== Étape 2/7 : coffre et stratégies (main.bicep)"
CONF=true
exists backup vault show -g "$SHARED" -n "$VAULT" && CONF=false
az deployment group create -g "$SHARED" -n rattrapage-m09 \
  --template-file "${DIR}/main.bicep" \
  --parameters numero="$NN" configurerStockage="$CONF" \
  --query "properties.outputs.{Coffre:vaultName.value, Strategies:join(', ', policies.value)}" -o table

echo "== Étape 3/7 : web01 (lancer-sauvegarde.sh)"
"${LABS}/lancer-sauvegarde.sh" "$NN"

echo "== Étape 4/7 : web02"
if [[ -z "$(item VM "vm-${ST}-web02")" ]]; then
  az backup protection enable-for-vm -g "$SHARED" -v "$VAULT" --policy-name pol-vm-arveo \
    --vm "$(az vm show -g "$APP" -n "vm-${ST}-web02" --query id -o tsv)" -o none
  echo "   vm-${ST}-web02 : sauvegarde $(backup_now VM "vm-${ST}-web02")"
else
  echo "   vm-${ST}-web02 : déjà protégée"
fi

echo "== Étape 5/7 : partage-lyon (${SA_FILES})"
if [[ -z "$(item AzureFileShare partage-lyon)" ]]; then
  exists backup policy show -g "$SHARED" -v "$VAULT" -n pol-files-arveo \
    || { echo "   pol-files-arveo absente" >&2; exit 1; }
  az backup protection enable-for-azurefileshare -g "$SHARED" -v "$VAULT" \
    --policy-name pol-files-arveo --storage-account "$SA_FILES" \
    --azure-file-share partage-lyon -o none
  echo "   partage-lyon : sauvegarde $(backup_now AzureFileShare partage-lyon)"
else
  echo "   partage-lyon : déjà protégé"
fi

echo "== Étape 6/7 : serveur de Lyon (agent MARS)"
if [[ "$LYON_OK" == "true" ]]; then
  az vm start -g "$LYON" -n "vm-${ST}-lyon-fs" -o none
  MI=$(az vm identity assign -g "$LYON" -n "vm-${ST}-lyon-fs" --query systemAssignedIdentity -o tsv)
  VAULT_ID=$(az backup vault show -g "$SHARED" -n "$VAULT" --query id -o tsv)
  if [[ "$(az role assignment list --assignee "$MI" --scope "$VAULT_ID" \
        --query "[?roleDefinitionName=='Backup Contributor'] | length(@)" -o tsv)" == "0" ]]; then
    az role assignment create --assignee-object-id "$MI" --assignee-principal-type ServicePrincipal \
      --role "Backup Contributor" --scope "$VAULT_ID" -o none
    echo "   rôle Backup Contributor attribué ; propagation (2 min)"
    sleep 120
  fi
  "${LABS}/mars-lyon.sh" "$NN" --wait
  az vm run-command invoke -g "$LYON" -n "vm-${ST}-lyon-fs" --command-id RunPowerShellScript \
    --scripts @"${DIR}/mars-policy.ps1" --query "value[0].message" -o tsv
fi

echo "== Étape 7/7 : contrôles"
az backup item list -g "$SHARED" -v "$VAULT" -o table \
  --query "[].{Element:properties.friendlyName, Type:properties.workloadType, Strategie:properties.policyName, Etat:properties.protectionState}"
az backup job list -g "$SHARED" -v "$VAULT" -o table \
  --query "[].{Element:properties.entityFriendlyName, Operation:properties.operation, Etat:properties.status}"
echo "Sauvegardes des VMs : 30 min à plus d'une heure ; lab 09.4 possible dès l'état « instantané »."
echo "Phrase secrète MARS : ~/.arveo/mars-passphrase.txt (à conserver hors du serveur)"
