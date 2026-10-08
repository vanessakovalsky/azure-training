#!/usr/bin/env bash
# module-09-backup.sh — à lancer en FIN DE MATINÉE DU JOUR 4 (12:28), puis avec --purge en fin
# de formation, AVANT ./module-06-storage.sh <NN> --purge.
# Sans option :
#   - désalloue vm-stNN-lyon-fs (agent MARS conservé, inscrit) ;
#   - supprime les disques NON attachés de rg-stNN-app (disques restaurés au lab 09.4 ou
#     au défi 09.5 et oubliés), sauf le disque de données d'origine disk-stNN-web01-data ;
#     aucune suppression pendant une restauration en cours (disques temporaires du service).
#   Coffre, stratégies, protections et points de récupération conservés (module 10).
# Avec --purge (fin de formation) :
#   1. suppression réversible désactivée (sinon coffre bloqué 14 jours) ;
#   2. éléments en suppression réversible restaurés, puis toutes les protections arrêtées
#      avec suppression des données (VMs, partage) ;
#   3. serveur MARS et compte de stockage désinscrits ; verrou AzureBackupProtectionLock retiré ;
#   4. coffre supprimé.
# Usage : ./module-09-backup.sh <NN> [--purge]
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
SHARED="rg-${ST}-shared"
APP="rg-${ST}-app"
DATA="rg-${ST}-data"
VAULT="rsv-${ST}-arveo"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true

echo "== Arrêt du serveur de Lyon"
az vm deallocate -g "rg-${ST}-lyon" -n "vm-${ST}-lyon-fs" --no-wait 2>/dev/null \
  && echo "   vm-${ST}-lyon-fs : désallocation lancée" || true

echo "== Disques non attachés de ${APP}"
# Une restauration en cours (défi 09.5) crée des disques non encore attachés : ne rien supprimer
RESTORING=$(az backup job list -g "$SHARED" -v "$VAULT" --status InProgress --operation Restore \
  --query "length(@)" -o tsv 2>/dev/null || echo 0)
if [[ "${RESTORING:-0}" != "0" ]]; then
  echo "   restauration en cours : disques conservés, relancer le script après la fin du travail"
else
  for D in $(az disk list -g "$APP" \
      --query "[?managedBy==null && name!='disk-${ST}-web01-data'].name" -o tsv); do
    az disk delete -g "$APP" -n "$D" --yes --no-wait
    echo "   ${D} : suppression lancée"
  done
fi

if [[ "${2:-}" == "--purge" ]]; then
  if ! az backup vault show -g "$SHARED" -n "$VAULT" -o none 2>/dev/null; then
    echo "== ${VAULT} absent : rien à purger"
    exit 0
  fi
  echo "== Suppression réversible désactivée"
  az backup vault backup-properties set -g "$SHARED" -n "$VAULT" \
    --soft-delete-feature-state Disable -o none

  echo "== Arrêt des protections avec suppression des données"
  for BMT in AzureIaasVM AzureStorage; do
    az backup item list -g "$SHARED" -v "$VAULT" --backup-management-type "$BMT" \
      --query "[].[properties.containerName, name, properties.friendlyName, properties.isScheduledForDeferredDelete]" \
      -o tsv | while read -r CONT ITEM NAME DEFERRED; do
        if [[ "$DEFERRED" == "True" ]]; then   # élément en suppression réversible
          az backup protection undelete -g "$SHARED" -v "$VAULT" --container-name "$CONT" \
            --item-name "$ITEM" --backup-management-type "$BMT" -o none
        fi
        az backup protection disable -g "$SHARED" -v "$VAULT" --container-name "$CONT" \
          --item-name "$ITEM" --backup-management-type "$BMT" \
          --delete-backup-data true --yes -o none
        echo "   ${NAME} : protection arrêtée, données supprimées"
      done
  done

  echo "== Désinscription des conteneurs (compte de stockage, serveur MARS)"
  for CONT in $(az backup container list -g "$SHARED" -v "$VAULT" \
      --backup-management-type AzureStorage --query "[].name" -o tsv); do
    az backup container unregister -g "$SHARED" -v "$VAULT" --container-name "$CONT" \
      --backup-management-type AzureStorage --yes -o none
    echo "   ${CONT##*;} : désinscrit"
  done
  # Serveurs MARS : conteneurs de type MAB [À VÉRIFIER] prise en charge par l'API ci-dessous ;
  # à défaut : portail, coffre › Infrastructure de sauvegarde › Serveurs protégés › Supprimer
  VAULT_ID=$(az backup vault show -g "$SHARED" -n "$VAULT" --query id -o tsv)
  API="api-version=2023-04-01"
  for ID in $(az rest --method get \
      --url "https://management.azure.com${VAULT_ID}/backupFabrics/Azure/protectionContainers?${API}&\$filter=backupManagementType%20eq%20'MAB'" \
      --query "value[].id" -o tsv 2>/dev/null); do
    az rest --method delete --url "https://management.azure.com${ID}?${API}" -o none \
      && echo "   serveur MARS ${ID##*/} : supprimé" || echo "   ${ID##*/} : supprimer par le portail"
  done
  for LOCK in $(az lock list -g "$DATA" --query "[?name=='AzureBackupProtectionLock'].id" -o tsv); do
    az lock delete --ids "$LOCK"
    echo "   verrou AzureBackupProtectionLock retiré"
  done

  echo "== Suppression du coffre"
  az backup vault delete -g "$SHARED" -n "$VAULT" --yes --force -o none \
    && echo "   ${VAULT} supprimé" \
    || echo "   ${VAULT} non supprimé : éléments restants (portail : Éléments de sauvegarde)" >&2
fi

az resource list -g "$SHARED" --resource-type Microsoft.RecoveryServices/vaults \
  --query "[].{Coffre:name, Groupe:resourceGroup}" -o table
