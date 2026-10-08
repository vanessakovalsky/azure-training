#!/usr/bin/env bash
# module-06-storage.sh — à lancer en FIN DE MATINÉE DU JOUR 3 (12:28)
# Le stockage Arvéo est conservé (réutilisé aux modules 8, 9 et 10) : coût au Go stocké,
# négligeable avec les volumes du lab. Seules les VMs sont arrêtées (deallocate) :
#   vm-stNN-lyon-fs (redémarrée au module 9 : agent MARS), vm-stNN-test-data, vm-stNN-test-web.
# Conservés : comptes de stockage, private endpoint pe-stNN-blob (facturé à l'heure, faible),
# service de synchronisation et serveur inscrit, disque disk-stNN-lyon-fs-data.
# La passerelle NAT de Lyon est gérée par la formatrice (lyon-nat.sh cleanup en fin de J4).
# Suppression complète du stockage (fin de formation) : ./module-06-storage.sh <NN> --purge
# Usage : ./module-06-storage.sh <NN> [--purge]
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
RG_DATA="rg-${ST}-data"

echo "== Arrêt des VMs"
az vm deallocate -g "rg-${ST}-lyon" -n "vm-${ST}-lyon-fs" --no-wait 2>/dev/null || true
for role in data web; do
  az vm deallocate -g "rg-${ST}-spoke" -n "vm-${ST}-test-${role}" --no-wait 2>/dev/null || true
done

if [[ "${2:-}" == "--purge" ]]; then
  echo "== Suppression du stockage (fin de formation)"
  # Le point de terminaison serveur, puis le serveur inscrit, doivent disparaître avant le service
  SSS_ID=$(az resource show -g "$RG_DATA" -n "sss-${ST}" \
    --resource-type Microsoft.StorageSync/storageSyncServices --query id -o tsv 2>/dev/null || true)
  if [[ -n "$SSS_ID" ]]; then
    API="api-version=2022-06-01"
    for SG in $(az rest --method get --url "https://management.azure.com${SSS_ID}/syncGroups?${API}" \
        --query "value[].name" -o tsv); do
      for EP in serverEndpoints cloudEndpoints; do
        for ID in $(az rest --method get \
            --url "https://management.azure.com${SSS_ID}/syncGroups/${SG}/${EP}?${API}" \
            --query "value[].id" -o tsv); do
          az rest --method delete --url "https://management.azure.com${ID}?${API}" -o none
          echo "   ${ID##*/} supprimé"
        done
      done
    done
    for ID in $(az rest --method get --url "https://management.azure.com${SSS_ID}/registeredServers?${API}" \
        --query "value[].id" -o tsv); do
      az rest --method delete --url "https://management.azure.com${ID}?${API}" -o none
      echo "   serveur inscrit ${ID##*/} supprimé"
    done
    az resource delete --ids "$SSS_ID"
  fi
  az network private-endpoint delete -g "$RG_DATA" -n "pe-${ST}-blob" 2>/dev/null || true
  for SA in $(az storage account list -g "$RG_DATA" --query "[].name" -o tsv); do
    az storage account or-policy list -g "$RG_DATA" --account-name "$SA" --query "[].policyId" -o tsv \
      | while read -r P; do
          az storage account or-policy delete -g "$RG_DATA" --account-name "$SA" --policy-id "$P"
        done
    az storage account delete -g "$RG_DATA" -n "$SA" --yes
    echo "   ${SA} supprimé"
  done
fi

az resource list -g "$RG_DATA" --query "[].{Nom:name, Type:type}" -o table
