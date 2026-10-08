#!/usr/bin/env bash
# module-10-monitoring.sh — à lancer en FIN DE MODULE 10 (15:43, J4), puis avec --purge en fin
# de formation, AVANT la suppression des groupes de ressources des stagiaires.
# Sans option :
#   - arrête la charge CPU du lab 10.2 sur vm-stNN-web01, redémarre nginx sur vm-stNN-web02 ;
#   - supprime le journal de flux fl-stNN-spoke-app (coût de Traffic analytics) ;
#   - supprime les captures de paquets pc-stNN-* et moniteurs de connexion cm-stNN-* (bonus) ;
#   - désalloue vm-stNN-test-data.
#   Conservés pour l'évaluation : diagnostics, groupe d'actions, alertes, fonction KQL.
# Avec --purge (fin de formation) :
#   - supprime en plus les règles alr-stNN-*, la règle de traitement apr-stNN-*, le groupe
#     d'actions, les requêtes enregistrées (catégorie Arveo), les paramètres diag-arveo et
#     l'extension NetworkWatcherAgentLinux.
#   Les objets de NetworkWatcherRG (journaux de flux, moniteurs, captures) ne sont PAS supprimés
#   avec les groupes rg-stNN-* : ce script est le seul à les retirer.
# Usage : ./module-10-monitoring.sh <NN> [--purge]
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
SHARED="rg-${ST}-shared"
APP="rg-${ST}-app"
SPOKE="rg-${ST}-spoke"
LOC="francecentral"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true
running() {   # running <GROUPE> <VM> : vrai si la VM est démarrée
  [[ "$(az vm get-instance-view -g "$1" -n "$2" \
    --query "instanceView.statuses[?code=='PowerState/running'] | length(@)" -o tsv 2>/dev/null)" == "1" ]]
}

echo "== Charge CPU (web01) et nginx (web02)"
if running "$APP" "vm-${ST}-web01"; then
  az vm run-command invoke -g "$APP" -n "vm-${ST}-web01" --command-id RunShellScript \
    --scripts "systemctl stop arveo-charge 2>/dev/null; echo charge arrêtée" -o none
  echo "   vm-${ST}-web01 : charge arrêtée"
fi
if running "$APP" "vm-${ST}-web02"; then
  az vm run-command invoke -g "$APP" -n "vm-${ST}-web02" --command-id RunShellScript \
    --scripts "systemctl is-active --quiet nginx || systemctl start nginx" -o none
  echo "   vm-${ST}-web02 : nginx actif"
fi

echo "== Network Watcher (${LOC})"
if az network watcher flow-log show --location "$LOC" --name "fl-${ST}-spoke-app" -o none 2>/dev/null; then
  az network watcher flow-log delete --location "$LOC" --name "fl-${ST}-spoke-app"
  echo "   fl-${ST}-spoke-app : supprimé"
fi
for PC in $(az network watcher packet-capture list --location "$LOC" \
    --query "[?starts_with(name, 'pc-${ST}')].name" -o tsv 2>/dev/null); do
  az network watcher packet-capture stop --location "$LOC" --name "$PC" 2>/dev/null || true
  az network watcher packet-capture delete --location "$LOC" --name "$PC"
  echo "   ${PC} : supprimée"
done
for CM in $(az network watcher connection-monitor list --location "$LOC" \
    --query "[?starts_with(name, 'cm-${ST}')].name" -o tsv 2>/dev/null); do
  az network watcher connection-monitor delete --location "$LOC" --name "$CM"
  echo "   ${CM} : supprimé"
done

echo "== VM de test de la base"
az vm deallocate -g "$SPOKE" -n "vm-${ST}-test-data" --no-wait 2>/dev/null \
  && echo "   vm-${ST}-test-data : désallocation lancée" || true

if [[ "${2:-}" == "--purge" ]]; then
  echo "== Règles d'alerte et de traitement"
  for R in $(az monitor metrics alert list -g "$SHARED" \
      --query "[?starts_with(name, 'alr-${ST}')].name" -o tsv); do
    az monitor metrics alert delete -g "$SHARED" -n "$R" && echo "   ${R} : supprimée"
  done
  for R in $(az monitor activity-log alert list -g "$SHARED" \
      --query "[?starts_with(name, 'alr-${ST}')].name" -o tsv); do
    az monitor activity-log alert delete -g "$SHARED" -n "$R" && echo "   ${R} : supprimée"
  done
  for R in $(az monitor scheduled-query list -g "$SHARED" \
      --query "[?starts_with(name, 'alr-${ST}')].name" -o tsv); do
    az monitor scheduled-query delete -g "$SHARED" -n "$R" --yes && echo "   ${R} : supprimée"
  done
  for R in $(az monitor alert-processing-rule list -g "$SHARED" \
      --query "[?starts_with(name, 'apr-${ST}')].name" -o tsv 2>/dev/null); do
    az monitor alert-processing-rule delete -g "$SHARED" -n "$R" --yes && echo "   ${R} : supprimée"
  done

  echo "== Groupe d'actions et requêtes enregistrées"
  az monitor action-group delete -g "$SHARED" -n "ag-${ST}-exploitation" 2>/dev/null \
    && echo "   ag-${ST}-exploitation : supprimé" || true
  for S in $(az monitor log-analytics workspace saved-search list -g "$SHARED" \
      --workspace-name "log-${ST}-shared" --query "[?category=='Arveo'].name" -o tsv 2>/dev/null); do
    az monitor log-analytics workspace saved-search delete -g "$SHARED" \
      --workspace-name "log-${ST}-shared" -n "$S" --yes && echo "   requête ${S} : supprimée"
  done

  echo "== Paramètres de diagnostic diag-arveo"
  for ID in \
      "$(az backup vault show -g "$SHARED" -n "rsv-${ST}-arveo" --query id -o tsv 2>/dev/null)" \
      "$(az network nsg show -g "$SPOKE" -n "nsg-${ST}-web" --query id -o tsv 2>/dev/null)" \
      "$(az network lb show -g "$APP" -n "lbe-${ST}-web" --query id -o tsv 2>/dev/null)"; do
    [[ -n "$ID" ]] || continue
    az monitor diagnostic-settings delete -n diag-arveo --resource "$ID" 2>/dev/null \
      && echo "   ${ID##*/} : diag-arveo supprimé" || true
  done

  echo "== Extension Network Watcher"
  az vm extension delete -g "$APP" --vm-name "vm-${ST}-web01" -n NetworkWatcherAgentLinux 2>/dev/null \
    && echo "   NetworkWatcherAgentLinux : supprimée" || true
fi

az network watcher flow-log list --location "$LOC" \
  --query "[?starts_with(name, 'fl-${ST}')].{JournalDeFlux:name, Actif:enabled}" -o table
