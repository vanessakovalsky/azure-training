#!/usr/bin/env bash
# Rattrapage module 02 — Gouvernance et conformité / Catch-up module 02 — Governance
# Usage (Cloud Shell Bash, compte stNN) : ./catch-up-module-02.sh <NN>
# Prérequis : état de fin de module 01 (groupes stNN-GRP-AdminsReseau, -Exploitation, -Logistique)
# Idempotent : relançable sans erreur bloquante. Le budget reste à créer dans le portail.
set -uo pipefail

NN="${1:?Numéro de stagiaire sur deux chiffres requis (ex. 07)}"
ST="st${NN}"
SUFFIXES="shared hub spoke data app lyon"

echo "== 1/5 Tags des groupes de ressources"
declare -A APP=( [shared]=Socle [hub]=Socle [spoke]=Socle [data]=Donnees \
                 [app]=PortailClient [lyon]=SiteLyon )
for R in $SUFFIXES; do
  ENV=Prod; [ "$R" = "lyon" ] && ENV=HorsProd
  RG_ID=$(az group show --name "rg-${ST}-${R}" --query id --output tsv)
  az tag update --resource-id "$RG_ID" --operation Merge --output none \
    --tags Proprietaire="$ST" CentreDeCout=CC-IT-1042 Environnement="$ENV" \
           Application="${APP[$R]}"
done

echo "== 2/5 Stratégies de région et de taille de VM"
DEF_LOC=$(az policy definition list \
  --query "[?displayName=='Allowed locations'].name" --output tsv)
DEF_SKU=$(az policy definition list \
  --query "[?displayName=='Allowed virtual machine size SKUs'].name" --output tsv)
for R in $SUFFIXES; do
  REGION=francecentral
  az policy assignment create --name "pa-${ST}-loc-${R}" \
    --display-name "Arveo ${ST} - Regions autorisees (${R})" \
    --policy "$DEF_LOC" --resource-group "rg-${ST}-${R}" \
    --params "{\"listOfAllowedLocations\":{\"value\":[\"${REGION}\"]}}" --output none
done
for R in app lyon; do
  az policy assignment create --name "pa-${ST}-vmsku-${R}" \
    --display-name "Arveo ${ST} - Tailles de VM autorisees (${R})" \
    --policy "$DEF_SKU" --resource-group "rg-${ST}-${R}" \
    --params '{"listOfAllowedSKUs":{"value":["Standard_B2s_v2","Standard_F1als_v7","Standard_F1alds_v7","Standard_D2as_v6","Standard_D2s_v6"]}}' \
    --output none
done

echo "== 3/5 Attributions de rôle"
ID_RESEAU=$(az ad group show --group "${ST}-GRP-AdminsReseau" --query id --output tsv)
ID_EXPLOIT=$(az ad group show --group "${ST}-GRP-Exploitation" --query id --output tsv)
ID_LOGIST=$(az ad group show --group "${ST}-GRP-Logistique" --query id --output tsv)
for R in hub spoke; do
  az role assignment create --assignee-object-id "$ID_RESEAU" \
    --assignee-principal-type Group --role "Network Contributor" \
    --resource-group "rg-${ST}-${R}" --output none 2>/dev/null || true
done
az role assignment create --assignee-object-id "$ID_LOGIST" \
  --assignee-principal-type Group --role "Reader" \
  --resource-group "rg-${ST}-app" --output none 2>/dev/null || true

echo "== 4/5 Rôle personnalisé Opérateur VM"
RG_APP_ID=$(az group show --name "rg-${ST}-app" --query id --output tsv)
ROLE_FILE=$(mktemp)
cat > "$ROLE_FILE" <<EOF
{
  "Name": "${ST}-Operateur-VM-Arveo",
  "IsCustom": true,
  "Description": "Arveo - consulter, demarrer, arreter, desallouer et redemarrer les VM",
  "Actions": [
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/instanceView/read",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/powerOff/action",
    "Microsoft.Compute/virtualMachines/deallocate/action",
    "Microsoft.Compute/virtualMachines/restart/action",
    "Microsoft.Compute/disks/read",
    "Microsoft.Network/networkInterfaces/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read"
  ],
  "NotActions": [], "DataActions": [], "NotDataActions": [],
  "AssignableScopes": [ "${RG_APP_ID}" ]
}
EOF
EXISTE=$(az role definition list --custom-role-only true --scope "$RG_APP_ID" \
  --query "[?roleName=='${ST}-Operateur-VM-Arveo'] | length(@)" --output tsv)
if [ "$EXISTE" = "0" ]; then
  az role definition create --role-definition "@${ROLE_FILE}" --output none
  echo "   Attente de la réplication du rôle (60 s)"; sleep 60
fi
az role assignment create --assignee-object-id "$ID_EXPLOIT" \
  --assignee-principal-type Group --role "${ST}-Operateur-VM-Arveo" \
  --scope "$RG_APP_ID" --output none 2>/dev/null || true
az role assignment delete --assignee "$ID_EXPLOIT" \
  --role "Virtual Machine Contributor" --resource-group "rg-${ST}-app" 2>/dev/null || true
rm -f "$ROLE_FILE"

echo "== 5/5 Verrou sur rg-${ST}-shared"
az lock create --name "lock-${ST}-shared" --lock-type CanNotDelete \
  --resource-group "rg-${ST}-shared" --notes "Ressources partagees Arveo" --output none

echo "== Contrôle"
az group list --tag Proprietaire="$ST" \
  --query "[].{RG:name, App:tags.Application, Env:tags.Environnement}" --output table
az role assignment list --all --query \
  "[?starts_with(principalName,'${ST}-GRP-')].{groupe:principalName, role:roleDefinitionName, rg:resourceGroup}" \
  --output table
echo "Rattrapage module 02 terminé pour ${ST}. Budget bud-${ST}-hub à créer dans le portail."
