#!/usr/bin/env bash
# module-08-paas.sh — à lancer en FIN DE MODULE 8 (J4, 10:58)
# Les modules 9 et 10 n'utilisent aucune ressource du module 8 : tout ce qui est facturé à
# l'heure ou à la seconde est supprimé.
#   Sans option : conteneurs aci-stNN-api et aci-stNN-api-priv, mise à l'échelle automatique,
#                 application (emplacement staging compris) puis plan App Service.
#                 Conservés : registre crarveostNN<SES> et son image, identité id-stNN-aci,
#                 sous-réseaux snet-appsvc / snet-aci et NSG du défi (gratuits ou quasi gratuits).
#   --purge     : en plus, registre, identité, sous-réseaux et NSG du défi (fin de formation).
# Relançable sans risque. Rattrapage complet : ./scripts/catch-up/module-08/deploy.sh <NN> <SES>
# Usage : ./module-08-paas.sh <NN> <SES> [--purge]
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
SES="${2:?Code de session à 4 caractères requis (ex. 2610)}"
PURGE="${3:-}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
ST="st${NN}"
APP_RG="rg-${ST}-app"
SPOKE="rg-${ST}-spoke"
APP="app-${ST}-portail-${SES}"
ACR="crarveo${ST}${SES}"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true
exists() { az "$@" -o none 2>/dev/null; }

echo "== Conteneurs (facturés à la seconde)"
for C in "aci-${ST}-api" "aci-${ST}-api-priv"; do
  if exists container show -g "$APP_RG" -n "$C"; then
    az container delete -g "$APP_RG" -n "$C" --yes -o none
    echo "   ${C} supprimé"
  fi
done

echo "== Container Apps (bonus 1)"
if exists containerapp show -g "$APP_RG" -n "ca-${ST}-api"; then
  az containerapp delete -g "$APP_RG" -n "ca-${ST}-api" --yes -o none
  echo "   ca-${ST}-api supprimée"
fi
if exists containerapp env show -g "$APP_RG" -n "cae-${ST}-arveo"; then
  az containerapp env delete -g "$APP_RG" -n "cae-${ST}-arveo" --yes -o none
  echo "   cae-${ST}-arveo supprimé"
fi

echo "== Mise à l'échelle automatique du plan"
if exists monitor autoscale show -g "$APP_RG" -n "as-${ST}-portail"; then
  az monitor autoscale delete -g "$APP_RG" -n "as-${ST}-portail"
  echo "   as-${ST}-portail supprimée"
fi

echo "== Application et plan App Service (facturés à l'heure par instance)"
for WA in "$APP" "app-${ST}-api-${SES}"; do   # portail + application conteneur du bonus 4
  if exists webapp show -g "$APP_RG" -n "$WA"; then
    az webapp delete -g "$APP_RG" -n "$WA"   # emplacements et intégration réseau compris
    echo "   ${WA} supprimée (emplacements compris)"
  fi
done
if exists appservice plan show -g "$APP_RG" -n "asp-${ST}-portail"; then
  az appservice plan delete -g "$APP_RG" -n "asp-${ST}-portail" --yes
  echo "   asp-${ST}-portail supprimé"
fi

if [[ "$PURGE" == "--purge" ]]; then
  echo "== Purge : registre, identité, réseau du défi"
  exists acr show -n "$ACR" && az acr delete -n "$ACR" --yes && echo "   ${ACR} supprimé"
  exists identity show -g "$APP_RG" -n "id-${ST}-aci" \
    && az identity delete -g "$APP_RG" -n "id-${ST}-aci" && echo "   id-${ST}-aci supprimée"
  for SNET in snet-aci snet-appsvc; do
    for TENTATIVE in 1 2 3 4 5 6; do   # liens d'association de service libérés en quelques minutes
      exists network vnet subnet show -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-app" -n "$SNET" || break
      if az network vnet subnet delete -g "$SPOKE" --vnet-name "vnet-${ST}-spoke-app" -n "$SNET" 2>/dev/null; then
        echo "   ${SNET} supprimé"; break
      fi
      echo "   ${SNET} encore utilisé (tentative ${TENTATIVE}/6) : nouvel essai dans 60 s"; sleep 60
    done
  done
  exists network nsg show -g "$SPOKE" -n "nsg-${ST}-aci" \
    && az network nsg delete -g "$SPOKE" -n "nsg-${ST}-aci" && echo "   nsg-${ST}-aci supprimé"
fi

echo "== Ressources du module 8 restantes dans ${APP_RG}"
az resource list -g "$APP_RG" -o table --query "[?contains(name, 'portail') || contains(name, 'aci') \
  || starts_with(name, 'crarveo')].{Nom:name, Type:type}"
