#!/usr/bin/env bash
# Rattrapage module 06 — stockage Arvéo (rg-stNN-data, private endpoint dans rg-stNN-spoke,
# zone DNS dans rg-stNN-hub, serveur de Lyon dans rg-stNN-lyon)
# 1. Contrôle de l'état réseau (spoke données, snet-pe, hub) et du serveur de Lyon
# 2. Serveur de Lyon : disque F:, agent Azure File Sync, modules Az (lyon-fs-prep.sh --wait)
# 3. main.bicep, passe 1 : comptes, protection des données, cycle de vie, rôles, synchronisation
# 4. Données d'exemple dans pod, règle de réplication d'objets (Azure CLI)
# 5. Inscription du serveur (identité managée), main.bicep passe 2 : point de terminaison
#    serveur, accès public du compte de données désactivé
# Durée : 15 à 25 min. Prérequis formatrice : fournisseur Microsoft.StorageSync inscrit,
# passerelle NAT de Lyon (lyon-nat.sh create).
# Usage : ./deploy.sh <NN> <SES>        (SES = code de session à 4 caractères)
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
SES="${2:?Code de session requis (4 caractères, fourni par la formatrice)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
[[ "$SES" =~ ^[a-z0-9]{4}$ ]] || { echo "Code de session invalide : $SES" >&2; exit 1; }
ST="st${NN}"
RG_DATA="rg-${ST}-data"
RG_LYON_ST="rg-${ST}-lyon"
SA_DATA="starveost${NN}data${SES}"
SA_ARCH="starveost${NN}arch${SES}"
SSS="sss-${ST}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== Étape 1/5 : état réseau et serveur de Lyon"
az network vnet subnet show -g "rg-${ST}-spoke" --vnet-name "vnet-${ST}-spoke-data" -n snet-pe \
  -o none 2>/dev/null \
  || { echo "   snet-pe absent : rattrapage du module 4 nécessaire (prévenir la formatrice)" >&2; exit 1; }
az network vnet show -g "rg-${ST}-hub" -n "vnet-${ST}-hub" -o none 2>/dev/null \
  || { echo "   vnet-${ST}-hub absent : rattrapage du module 4 nécessaire" >&2; exit 1; }
if ! az vm show -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" -o none 2>/dev/null; then
  "${DIR}/../../labs/module-05/lyon-vm.sh" "$NN"
  az vm wait -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" --created
fi
echo "   réseau et serveur de Lyon présents"

echo "== Étape 2/5 : préparation du serveur de Lyon (10 à 15 min)"
"${DIR}/../../labs/module-06/lyon-fs-prep.sh" "$NN" --wait

echo "== Étape 3/5 : comptes, protection, rôles, synchronisation (main.bicep, passe 1)"
USER_ID=$(az ad signed-in-user show --query id -o tsv)
LYON_PID=$(az vm show -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" --query identity.principalId -o tsv)
SYNC_SP=$(az ad sp list --display-name "Microsoft.StorageSync" --query "[0].id" -o tsv)
[[ -n "$SYNC_SP" ]] || { echo "   principal Microsoft.StorageSync introuvable : fournisseur non inscrit" >&2; exit 1; }
RDA_ROLE=$(az role definition list --name "Reader and Data Access" --query "[0].name" -o tsv)
COMMON=(numero="$NN" session="$SES" userObjectId="$USER_ID" lyonPrincipalId="$LYON_PID"
        storageSyncSpObjectId="$SYNC_SP" readerDataAccessRoleId="$RDA_ROLE")
az deployment group create -g "$RG_DATA" -n rattrapage-m06 \
  --template-file "${DIR}/main.bicep" \
  --parameters "${COMMON[@]}" publicNetworkAccess=Enabled \
  --query properties.provisioningState -o tsv

echo "== Étape 4/5 : données d'exemple et réplication d'objets"
mkdir -p "$HOME/arveo-m06/pod"
for i in $(seq -w 1 20); do
  echo "Preuve de livraison ${i} - tournée T${i} - signée" > "$HOME/arveo-m06/pod/pod-0${i}.txt"
done
for _ in $(seq 1 20); do   # propagation du rôle Storage Blob Data Contributor (jusqu'à 10 min)
  if az storage blob upload-batch -d pod -s "$HOME/arveo-m06/pod" --destination-path 2026/10 \
       --account-name "$SA_DATA" --auth-mode login --overwrite -o none 2>/dev/null; then
    echo "   20 blobs déposés dans pod/2026/10"
    break
  fi
  echo "   rôle en cours de propagation... nouvelle tentative dans 30 s"
  sleep 30
done
if [[ -z "$(az storage account or-policy list -g "$RG_DATA" --account-name "$SA_DATA" \
      --query "[].policyId" -o tsv)" ]]; then
  az storage account or-policy create -g "$RG_DATA" --account-name "$SA_ARCH" \
    --source-account "$SA_DATA" --destination-account "$SA_ARCH" \
    --source-container pod --destination-container pod-replica \
    --min-creation-time '2026-01-01T00:00:00Z' -o none
  POLICY_ID=$(az storage account or-policy list -g "$RG_DATA" --account-name "$SA_ARCH" \
    --query "[0].policyId" -o tsv)
  az storage account or-policy show -g "$RG_DATA" --account-name "$SA_ARCH" --policy-id "$POLICY_ID" \
    | az storage account or-policy create -g "$RG_DATA" --account-name "$SA_DATA" --policy "@-" -o none
  echo "   règle de réplication ${POLICY_ID} : pod → ${SA_ARCH}/pod-replica"
else
  echo "   règle de réplication déjà présente : conservée"
fi

echo "== Étape 5/5 : inscription du serveur et point de terminaison serveur"
SSS_ID=$(az resource show -g "$RG_DATA" -n "$SSS" \
  --resource-type Microsoft.StorageSync/storageSyncServices --query id -o tsv)
SERVERS_URL="https://management.azure.com${SSS_ID}/registeredServers?api-version=2022-06-01"
SERVER_ID=$(az rest --method get --url "$SERVERS_URL" --query "value[0].id" -o tsv)
if [[ -z "$SERVER_ID" ]]; then
  SUB=$(az account show --query id -o tsv)
  for _ in $(seq 1 10); do   # propagation du rôle de l'identité managée
    az vm run-command invoke -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" \
      --command-id RunPowerShellScript \
      --scripts "Connect-AzAccount -Identity -Subscription '${SUB}' | Out-Null; Register-AzStorageSyncServer -ResourceGroupName '${RG_DATA}' -StorageSyncServiceName '${SSS}' | Select-Object -ExpandProperty ServerId" \
      --query "value[0].message" -o tsv
    SERVER_ID=$(az rest --method get --url "$SERVERS_URL" --query "value[0].id" -o tsv)
    [[ -n "$SERVER_ID" ]] && break
    echo "   inscription non aboutie... nouvelle tentative dans 60 s"
    sleep 60
  done
fi
[[ -n "$SERVER_ID" ]] || { echo "   inscription impossible : voir les erreurs fréquentes du lab 06.5" >&2; exit 1; }
echo "   serveur inscrit : ${SERVER_ID##*/}"
az deployment group create -g "$RG_DATA" -n rattrapage-m06 \
  --template-file "${DIR}/main.bicep" \
  --parameters "${COMMON[@]}" publicNetworkAccess=Disabled registeredServerId="$SERVER_ID" \
  --query "properties.outputs.{Compte:dataAccount.value, IP_PE:privateEndpointIp.value}" -o table

echo "== Contrôle"
az storage account list -g "$RG_DATA" \
  --query "[].{Nom:name, SKU:sku.name, Public:publicNetworkAccess, CleePartagee:allowSharedKeyAccess}" \
  -o table
