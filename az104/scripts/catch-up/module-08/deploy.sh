#!/usr/bin/env bash
# Rattrapage module 08 — calcul PaaS et conteneurs Arvéo (rg-stNN-app, rg-stNN-spoke pour --defi)
# 1. Contrôles (groupe, fournisseurs de ressources, disponibilité des noms)
# 2. Plan, application + emplacement staging, mise à l'échelle, registre, identité : main.bicep
# 3. Portail : v3 publié dans staging, v4 dans production (état après l'échange de l'exercice 08.3)
# 4. Image arveo/api-suivi-colis:2.0 construite par ACR Tasks
# 5. Conteneur public aci-stNN-api (lab 08.4) : aci.bicep
# 6. Option --defi : sous-réseaux snet-appsvc et snet-aci, NSG, conteneur privé, intégration
#    au réseau virtuel de l'application, API_URL (solution du défi 08.5)
# 7. Contrôles : page de production, /api/ (si --defi), API publique
# Durée : 8 à 15 min. Idempotent : relançable ; l'image n'est reconstruite que si elle manque.
# Usage : ./deploy.sh <NN> <SES> [--defi]
set -euo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
SES="${2:?Code de session à 4 caractères requis (ex. 2610, module 6)}"
DEFI="${3:-}"
[[ "$NN" =~ ^[0-9]{2}$ ]] || { echo "Numéro invalide : $NN" >&2; exit 1; }
[[ "$SES" =~ ^[a-z0-9]{4,6}$ ]] || { echo "Code de session invalide : $SES (4 à 6 caractères a-z, 0-9)" >&2; exit 1; }
OCT=$((10#$NN))
ST="st${NN}"
APP_RG="rg-${ST}-app"
SPOKE="rg-${ST}-spoke"
LOC="francecentral"
TAGS=(Projet=Arveo Environnement=Formation "Proprietaire=${ST}")
DIR="$(cd "$(dirname "$0")" && pwd)"
LABS="${DIR}/../../labs/module-08"
APP="app-${ST}-portail-${SES}"
ACR="crarveo${ST}${SES}"
IMAGE="arveo/api-suivi-colis:2.0"

az config set extension.use_dynamic_install=yes_without_prompt -o none 2>/dev/null || true
exists() { az "$@" -o none 2>/dev/null; }

echo "== Étape 1/7 : contrôles"
exists group show -n "$APP_RG" || { echo "   ${APP_RG} absent : provisionnement de la formation" >&2; exit 1; }
for P in Microsoft.Web Microsoft.ContainerRegistry Microsoft.ContainerInstance Microsoft.ManagedIdentity; do
  ETAT=$(az provider show -n "$P" --query registrationState -o tsv)
  [[ "$ETAT" == "Registered" ]] || { echo "   ${P} : ${ETAT} (enregistrement par la formatrice)" >&2; exit 1; }
done
echo "   fournisseurs enregistrés"
if ! exists webapp show -g "$APP_RG" -n "$APP"; then
  [[ "$(az rest --method post \
      --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.Web/checkNameAvailability?api-version=2024-04-01" \
      --body "{\"name\":\"${APP}\",\"type\":\"Microsoft.Web/sites\"}" --query nameAvailable -o tsv)" == "true" ]] \
    || { echo "   nom ${APP} déjà pris : changer de code de session" >&2; exit 1; }
fi
if ! exists acr show -n "$ACR"; then
  [[ "$(az acr check-name -n "$ACR" --query nameAvailable -o tsv)" == "true" ]] \
    || { echo "   nom ${ACR} déjà pris : changer de code de session" >&2; exit 1; }
fi
echo "   noms ${APP} et ${ACR} disponibles ou déjà à ce stagiaire"

echo "== Étape 2/7 : plan, application, mise à l'échelle, registre, identité (main.bicep)"
API_URL=""
if [[ "$DEFI" == "--defi" ]] && exists container show -g "$APP_RG" -n "aci-${ST}-api-priv"; then
  API_URL="http://$(az container show -g "$APP_RG" -n "aci-${ST}-api-priv" --query ipAddress.ip -o tsv):8080/"
fi
read -r APP_HOST STG_HOST LOGIN ID_ACI < <(az deployment group create \
  --resource-group "$APP_RG" --name "rattrapage-m08" \
  --template-file "${DIR}/main.bicep" \
  --parameters numero="$NN" session="$SES" apiUrl="$API_URL" \
  --query "properties.outputs.[appHost.value, stagingHost.value, acrLoginServer.value, identityId.value]" \
  -o tsv | tr '\n' ' ')
echo "   production : ${APP_HOST}"
echo "   staging    : ${STG_HOST}"
echo "   registre   : ${LOGIN}"

echo "== Étape 3/7 : publication du portail (v4 en production, v3 en staging)"
for V in v3 v4; do "${LABS}/empaqueter-portail.sh" "$V" >/dev/null; done
az webapp deploy -g "$APP_RG" -n "$APP" --slot staging \
  --src-path "${HOME}/arveo-build/portail-v3.zip" --type zip -o none
az webapp deploy -g "$APP_RG" -n "$APP" \
  --src-path "${HOME}/arveo-build/portail-v4.zip" --type zip -o none
echo "   déploiements zip terminés"

echo "== Étape 4/7 : image ${IMAGE} (ACR Tasks)"
if az acr repository show-tags -n "$ACR" --repository arveo/api-suivi-colis -o tsv 2>/dev/null | grep -qx '2.0'; then
  echo "   image déjà présente"
else
  az acr build -r "$ACR" -t "$IMAGE" "${LABS}/api" --no-logs -o none
  echo "   image construite"
fi

echo "== Étape 5/7 : conteneur public aci-${ST}-api"
sleep 30   # propagation du rôle AcrPull (attribution récente)
az deployment group create -g "$APP_RG" -n "rattrapage-m08-aci" \
  --template-file "${DIR}/aci.bicep" \
  --parameters numero="$NN" session="$SES" acrLoginServer="$LOGIN" identityId="$ID_ACI" \
  --query "properties.outputs.fqdn.value" -o tsv | sed 's/^/   FQDN : /'

if [[ "$DEFI" == "--defi" ]]; then
  echo "== Étape 6/7 : solution du défi 08.5 (API privée)"
  VNET="vnet-${ST}-spoke-app"
  az network nsg create -g "$SPOKE" -n "nsg-${ST}-aci" -l "$LOC" --tags "${TAGS[@]}" -o none
  az network nsg rule create -g "$SPOKE" --nsg-name "nsg-${ST}-aci" -n Allow-8080-From-AppSvc \
    --priority 100 --access Allow --protocol Tcp --direction Inbound \
    --source-address-prefixes "10.${OCT}.6.0/26" --destination-port-ranges 8080 -o none
  az network nsg rule create -g "$SPOKE" --nsg-name "nsg-${ST}-aci" -n Deny-VNet-Inbound \
    --priority 4000 --access Deny --protocol '*' --direction Inbound \
    --source-address-prefixes VirtualNetwork --destination-port-ranges '*' -o none
  exists network vnet subnet show -g "$SPOKE" --vnet-name "$VNET" -n snet-appsvc \
    || az network vnet subnet create -g "$SPOKE" --vnet-name "$VNET" -n snet-appsvc \
         --address-prefixes "10.${OCT}.6.0/26" --delegations Microsoft.Web/serverFarms -o none
  exists network vnet subnet show -g "$SPOKE" --vnet-name "$VNET" -n snet-aci \
    || az network vnet subnet create -g "$SPOKE" --vnet-name "$VNET" -n snet-aci \
         --address-prefixes "10.${OCT}.6.64/27" --delegations Microsoft.ContainerInstance/containerGroups -o none
  az network vnet subnet update -g "$SPOKE" --vnet-name "$VNET" -n snet-aci \
    --nat-gateway "ng-${ST}-app" --nsg "nsg-${ST}-aci" -o none
  SNET_ACI=$(az network vnet subnet show -g "$SPOKE" --vnet-name "$VNET" -n snet-aci --query id -o tsv)
  SNET_APPSVC=$(az network vnet subnet show -g "$SPOKE" --vnet-name "$VNET" -n snet-appsvc --query id -o tsv)
  IP_PRIV=$(az deployment group create -g "$APP_RG" -n "rattrapage-m08-aci-priv" \
    --template-file "${DIR}/aci.bicep" \
    --parameters numero="$NN" session="$SES" acrLoginServer="$LOGIN" identityId="$ID_ACI" \
                 prive=true subnetId="$SNET_ACI" \
    --query "properties.outputs.ip.value" -o tsv)
  echo "   aci-${ST}-api-priv : ${IP_PRIV}"
  if [[ -z "$(az webapp vnet-integration list -g "$APP_RG" -n "$APP" --query '[0].name' -o tsv)" ]]; then
    az webapp vnet-integration add -g "$APP_RG" -n "$APP" --vnet "$(az network vnet show -g "$SPOKE" \
      -n "$VNET" --query id -o tsv)" --subnet "$SNET_APPSVC" -o none
  fi
  az webapp config appsettings set -g "$APP_RG" -n "$APP" \
    --slot-settings "API_URL=http://${IP_PRIV}:8080/" -o none
  echo "   intégration au réseau virtuel : snet-appsvc ; API_URL=http://${IP_PRIV}:8080/"
else
  echo "== Étape 6/7 : défi non déployé (option --defi)"
fi

echo "== Étape 7/7 : contrôles"
sleep 20
curl -s --max-time 30 "https://${APP_HOST}/" || echo "ECHEC production"
curl -s --max-time 30 "https://${STG_HOST}/" || echo "ECHEC staging"
[[ "$DEFI" == "--defi" ]] && { curl -s --max-time 30 "https://${APP_HOST}/api/" || echo "ECHEC /api/"; }
FQDN=$(az container show -g "$APP_RG" -n "aci-${ST}-api" --query ipAddress.fqdn -o tsv)
curl -s --max-time 10 "http://${FQDN}:8080/" || echo "ECHEC API publique"
echo "Nettoyage en fin de module : ./scripts/cleanup/module-08-paas.sh ${NN} ${SES}"
