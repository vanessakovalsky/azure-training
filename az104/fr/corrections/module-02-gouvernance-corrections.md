# Module 02 — Corrections

Toutes les solutions supposent les variables de début de session définies :

```bash
ST="st<NN>"
DOMAINE="<DOMAINE>"
SUB_ID=$(az account show --query id --output tsv)
```

---

## Lab 02.1 ⭐ — Organiser et taguer la landing zone Arvéo

### Solution
Les étapes du lab constituent la solution. Variante 100 % CLI pour l'étape 2 (portail) :

```bash
RG_ID=$(az group show --name "rg-${ST}-hub" --query id --output tsv)
az tag update --resource-id "$RG_ID" --operation Merge --output none \
  --tags Proprietaire=$ST CentreDeCout=CC-IT-1042 Environnement=Prod Application=Socle
```

Contrôle des tags d'un seul groupe :

```bash
az tag list --resource-id "$(az group show --name rg-${ST}-hub --query id -o tsv)" \
  --query "properties.tags"
```
Sortie attendue :
```
{
  "Application": "Socle",
  "CentreDeCout": "CC-IT-1042",
  "Environnement": "Prod",
  "Proprietaire": "st07"
}
```

Budget : la création par le portail est la méthode de référence (alertes et destinataires dans le même assistant). Montant suggéré : celui annoncé par la formatrice, calé sur l'estimation de la calculatrice de prix pour le pare-feu et la passerelle VPN du hub `[À VÉRIFIER]`.

### Pourquoi
- **Tag `Proprietaire`** : dans l'abonnement partagé, c'est le seul filtre fiable pour isoler les groupes d'un stagiaire dans l'analyse des coûts (les valeurs `CentreDeCout` sont identiques pour tous).
- **`az tag update --operation Merge`** plutôt que `az group update --tags` : la seconde commande remplace l'ensemble des tags ; un tag posé par la formatrice ou par une stratégie serait perdu.
- **Budget sur `rg-stNN-hub`** : ce groupe portera les deux ressources les plus coûteuses de la formation (Azure Firewall au module 4, passerelle VPN au module 5).
- **Alerte « Prévu » à 100 %** : prévient AVANT le dépassement, sur la base de la tendance ; l'alerte « Réel » à 80 % confirme la consommation constatée.
- **Courriel personnel** : les comptes `stNN` n'ont pas de licence Exchange Online, donc aucune boîte aux lettres.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `ResourceGroupNotFound` | Variable `ST` non définie (nouvelle session Cloud Shell) ou faute de frappe | Redéfinir `ST`, vérifier avec `echo $ST` |
| `AuthorizationFailed` sur `az tag update` | Groupe d'un autre stagiaire (numéro erroné) | Vérifier `<NN>` ; seuls les groupes `rg-stNN-*` du stagiaire sont modifiables |
| Tags du hub disparus après une commande | Usage de `az group update --tags` | Réappliquer avec `az tag update --operation Merge` |
| Menu **Budgets** absent ou grisé | Type d'offre de l'abonnement non compatible avec Cost Management `[À VÉRIFIER]` | Démonstration formatrice sur son groupe de ressources |
| `az consumption budget list` en erreur | Groupe de commandes en préversion | Contrôle dans le portail |
| Boucle `declare -A` en erreur | Shell PowerShell ouvert au lieu de Bash | Basculer Cloud Shell en **Bash** |

---

## Exercice 02.2 ⭐⭐ — Garde-fous de région et de taille de VM

### Solution

1. Récupérer les définitions intégrées (une seule fois, la liste complète est longue à charger) :

```bash
DEF_LOC=$(az policy definition list \
  --query "[?displayName=='Allowed locations'].name" --output tsv)
DEF_SKU=$(az policy definition list \
  --query "[?displayName=='Allowed virtual machine size SKUs'].name" --output tsv)
echo "$DEF_LOC / $DEF_SKU"
```
Sortie attendue :
```
e56962a6-4747-49cd-b67b-bf8b01975c4c / cccc23c7-8427-4f53-ad12-b6a63eb452b3
```
Les GUID sont ceux des définitions intégrées publiques `[À VÉRIFIER]` ; seule la recherche par `displayName` fait foi.

2. Affecter « Allowed locations » sur les six groupes (le spoke PRA est en North Europe) :

```bash
for R in shared hub spoke data app lyon; do
  if [ "$R" = "spoke" ]; then
    LOCS='["francecentral","northeurope"]'
  else
    LOCS='["francecentral"]'
  fi
  az policy assignment create --name "pa-${ST}-loc-${R}" \
    --display-name "Arveo ${ST} - Regions autorisees (${R})" \
    --policy "$DEF_LOC" --resource-group "rg-${ST}-${R}" \
    --params "{\"listOfAllowedLocations\":{\"value\":${LOCS}}}" \
    --output none
done
```

3. Affecter « Allowed virtual machine size SKUs » sur `app` et `lyon` :

```bash
for R in app lyon; do
  az policy assignment create --name "pa-${ST}-vmsku-${R}" \
    --display-name "Arveo ${ST} - Tailles de VM autorisees (${R})" \
    --policy "$DEF_SKU" --resource-group "rg-${ST}-${R}" \
    --params '{"listOfAllowedSKUs":{"value":["Standard_B2s_v2","Standard_F1als_v7","Standard_F1alds_v7","Standard_D2as_v6","Standard_D2s_v6"]}}' \
    --output none
done
```

4. Contrôler les affectations (critère de réussite) :

```bash
for R in shared hub spoke data app lyon; do
  az policy assignment list --resource-group "rg-${ST}-${R}" \
    --query "[?starts_with(name,'pa-${ST}-')].name" --output tsv
done
```
Sortie attendue :
```
pa-st07-loc-shared
pa-st07-loc-hub
pa-st07-loc-spoke
pa-st07-loc-data
pa-st07-loc-app
pa-st07-vmsku-app
pa-st07-loc-lyon
pa-st07-vmsku-lyon
```

5. Preuve de refus (après quelques minutes) :

```bash
az network nsg create --resource-group "rg-${ST}-hub" \
  --name "nsg-${ST}-test" --location westeurope
```
Sortie attendue (extrait) :
```
(RequestDisallowedByPolicy) Resource 'nsg-st07-test' was disallowed by policy.
```

6. Preuve d'acceptation, puis nettoyage :

```bash
az network nsg create --resource-group "rg-${ST}-hub" \
  --name "nsg-${ST}-test" --location francecentral \
  --query "NewNSG.provisioningState" --output tsv
az network nsg delete --resource-group "rg-${ST}-hub" --name "nsg-${ST}-test"
```
Sortie attendue :
```
Succeeded
```

7. Conformité :

```bash
az policy state trigger-scan --resource-group "rg-${ST}-hub"
az policy state summarize --resource-group "rg-${ST}-hub" \
  --query "results.{nonConformes:nonCompliantResources, strategies:nonCompliantPolicies}"
```
Sortie attendue :
```
{
  "nonConformes": 0,
  "strategies": 0
}
```
Sans `--no-wait`, `trigger-scan` rend la main à la fin de l'analyse (plusieurs minutes possibles).

### Pourquoi
- **Scope groupe de ressources** : dans le tenant partagé, les stagiaires n'ont pas le droit d'affecter au niveau abonnement ; en entreprise, ces deux stratégies seraient affectées une seule fois au groupe d'administration `mg-arveo`, avec une exclusion (`notScopes`) pour le site de Lyon.
- **NSG comme ressource de test** : création instantanée, gratuite, soumise à la région (mode `Indexed`).
- **Réseau virtuel dans `rg-stNN-spoke` en North Europe (spoke PRA)** : autorisé car l'affectation de ce groupe porte `["francecentral","northeurope"]`. Les affectations sont indépendantes : chaque groupe a sa propre liste. C'est la raison pour laquelle `rg-stNN-spoke` reçoit deux régions et non une.
- **Ressources `global`** (zones DNS privées du module 4, groupes d'actions et règles d'alerte métrique du module 10) : exclues par la règle intégrée (`notEquals: global`), donc non bloquées.
- **Tailles de VM** : la gamme B suffit à tous les labs (modules 5 à 9). Toute autre taille nécessite la mise à jour du paramètre, ce qui trace la décision.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `DEF_LOC` vide | Faute de frappe dans `displayName` (sensible à la casse) | Copier le nom exact : `Allowed locations` |
| `InvalidPolicyParameters` | JSON de `--params` mal échappé (guillemets dans la boucle) | Reprendre la syntaxe `\"…\"` de la solution |
| `InvalidRequestContent` sur `--params` | Nom de paramètre inexact (`listOfAllowedLocation`) | `az policy definition show --name $DEF_LOC --query parameters` |
| NSG West Europe accepté | Affectation trop récente | Attendre quelques minutes, puis réessayer |
| `trigger-scan` très long | Évaluation de tout le groupe | Ajouter `--no-wait`, consulter la conformité plus tard |
| Résumé de conformité vide | Évaluation initiale non terminée | Relancer `summarize` après quelques minutes |

### Variantes acceptables
- **Portail** : **Stratégie** → **Affectations** → **Affecter une stratégie** → scope = groupe de ressources → définition « Emplacements autorisés » → onglet **Paramètres**. Plus lent pour six groupes, mais montre le champ **Exclusions**.
- **Initiative** : impossible à créer par les stagiaires (définition au niveau abonnement), mais une initiative « Arvéo - Socle » regroupant les deux définitions éviterait huit affectations.
- **PowerShell Az** `[À VÉRIFIER]` sur la propriété `DisplayName` selon la version d'Az.Resources :
  ```powershell
  $def = Get-AzPolicyDefinition -Builtin | Where-Object DisplayName -eq 'Allowed locations'
  New-AzPolicyAssignment -Name "pa-$ST-loc-hub" -PolicyDefinition $def `
    -Scope (Get-AzResourceGroup -Name "rg-$ST-hub").ResourceId `
    -PolicyParameterObject @{ listOfAllowedLocations = @('francecentral') }
  ```

---

## Exercice 02.3 ⭐⭐ — Matrice des accès Arvéo et verrou

### Solution

1. Identifiants des groupes :

```bash
ID_RESEAU=$(az ad group show --group "${ST}-GRP-AdminsReseau" --query id --output tsv)
ID_EXPLOIT=$(az ad group show --group "${ST}-GRP-Exploitation" --query id --output tsv)
ID_LOGIST=$(az ad group show --group "${ST}-GRP-Logistique" --query id --output tsv)
echo "$ID_RESEAU / $ID_EXPLOIT / $ID_LOGIST"
```
Sortie attendue : trois GUID non vides.

2. Attributions :

```bash
for R in hub spoke; do
  az role assignment create --assignee-object-id "$ID_RESEAU" \
    --assignee-principal-type Group --role "Network Contributor" \
    --resource-group "rg-${ST}-${R}" --output none
done
az role assignment create --assignee-object-id "$ID_EXPLOIT" \
  --assignee-principal-type Group --role "Virtual Machine Contributor" \
  --resource-group "rg-${ST}-app" --output none
az role assignment create --assignee-object-id "$ID_LOGIST" \
  --assignee-principal-type Group --role "Reader" \
  --resource-group "rg-${ST}-app" --output none
```

3. Contrôle (critère de réussite) :

```bash
for R in hub spoke app; do
  az role assignment list --resource-group "rg-${ST}-${R}" \
    --query "[?principalType=='Group'].{groupe:principalName, role:roleDefinitionName}" \
    --output table
done
```
Sortie attendue :
```
Groupe                 Role
---------------------  -------------------
st07-GRP-AdminsReseau  Network Contributor
Groupe                 Role
---------------------  -------------------
st07-GRP-AdminsReseau  Network Contributor
Groupe                 Role
---------------------  ---------------------------
st07-GRP-Exploitation  Virtual Machine Contributor
st07-GRP-Logistique    Reader
```

4. Accès effectifs de Léa Martin :

```bash
az role assignment list --assignee "${ST}-lea.martin@${DOMAINE}" \
  --all --include-groups \
  --query "[].{role:roleDefinitionName, scope:scope}" --output table
```
Sortie attendue :
```
Role    Scope
------  ----------------------------------------------------------
Reader  /subscriptions/1a2b3c4d-…/resourceGroups/rg-st07-app
```
Portail : `rg-stNN-app` → **Contrôle d'accès (IAM)** → **Vérifier l'accès** → `stNN-lea.martin` → rôle Lecteur, attribution « Hérité d'un groupe » `[À VÉRIFIER]` sur le libellé exact.

5. Verrou et preuve :

```bash
az lock create --name "lock-${ST}-shared" --lock-type CanNotDelete \
  --resource-group "rg-${ST}-shared" --notes "Ressources partagees Arveo"
az network nsg create --resource-group "rg-${ST}-shared" \
  --name "nsg-${ST}-verrou" --location francecentral --output none
az network nsg delete --resource-group "rg-${ST}-shared" --name "nsg-${ST}-verrou"
```
Sortie attendue (dernière commande, extrait) :
```
(ScopeLocked) The scope '/subscriptions/…/resourceGroups/rg-st07-shared/providers/
Microsoft.Network/networkSecurityGroups/nsg-st07-verrou' cannot perform delete
operation because following scope(s) are locked: '…/resourceGroups/rg-st07-shared'.
```

### Pourquoi
- **Groupes plutôt qu'utilisateurs** : l'arrivée ou le départ d'un collaborateur se gère dans Entra ID (module 1), sans toucher aux attributions Azure.
- **`--assignee-object-id` + `--assignee-principal-type`** : évite une résolution de nom dans Microsoft Graph et les échecs de réplication juste après la création d'un groupe.
- **Contributeur de réseau sur hub ET spoke** : le peering (module 5) se configure des deux côtés ; un droit sur le hub seul ne suffit pas.
- **Lecteur pour la logistique** : visibilité sur le portail client sans aucune modification possible.
- **Verrou au niveau groupe** : protège aussi les ressources qui seront créées plus tard dans `rg-stNN-shared` (héritage).
- **Propriétaire bloqué** : le verrou s'applique à tous ; il faut le SUPPRIMER pour supprimer une ressource, ce qui impose une action volontaire et tracée dans le journal d'activité.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `az ad group show` : `Resource … does not exist` | Nom du groupe différent au module 1 | `az ad group list --filter "startswith(displayName,'${ST}')" --query "[].displayName"` |
| `PrincipalNotFound` | Groupe créé il y a quelques secondes (réplication) | Réessayer après 1 à 2 minutes |
| `AuthorizationFailed` sur `Microsoft.Authorization/roleAssignments/write` | Scope hors `rg-stNN-*` (ex. abonnement) | Le stagiaire n'est propriétaire que de ses groupes |
| Léa Martin sans aucune attribution | `--include-groups` oublié, ou Léa absente du groupe | Ajouter l'option ; vérifier `az ad group member list --group "${ST}-GRP-Logistique"` |
| Suppression du NSG réussie | Verrou créé sur le mauvais groupe | `az lock list --resource-group "rg-${ST}-shared" --output table` |
| `RoleAssignmentExists` | Commande relancée | Sans gravité : l'attribution existe déjà |

### Variantes acceptables
- **Portail** : groupe de ressources → **Contrôle d'accès (IAM)** → **Ajouter une attribution de rôle** → rôle → membres → groupe. Recommandé pour la première attribution (visualisation des onglets Rôle / Membres / Conditions).
- **PowerShell Az** :
  ```powershell
  $id = (Get-AzADGroup -DisplayName "$ST-GRP-AdminsReseau").Id
  New-AzRoleAssignment -ObjectId $id -RoleDefinitionName "Network Contributor" `
    -ResourceGroupName "rg-$ST-hub"
  New-AzResourceLock -LockName "lock-$ST-shared" -LockLevel CanNotDelete `
    -ResourceGroupName "rg-$ST-shared" -Force
  ```
- **Rôle Contributeur au lieu de Contributeur de réseau** : refusé, car il donne aussi le droit de créer des VM, des comptes de stockage, etc. dans le hub.

---

## Défi 02.4 ⭐⭐⭐ — Rôle personnalisé « Opérateur VM »

### Solution

1. Définition du rôle :

```bash
RG_APP_ID=$(az group show --name "rg-${ST}-app" --query id --output tsv)
cat > "role-${ST}-operateur-vm.json" <<EOF
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
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": [ "${RG_APP_ID}" ]
}
EOF
az role definition create --role-definition "@role-${ST}-operateur-vm.json" \
  --query "{nom:roleName, type:roleType}" --output table
```
Sortie attendue :
```
Nom                      Type
-----------------------  ----------
st07-Operateur-VM-Arveo  CustomRole
```

2. Remplacement de l'attribution (attendre 1 à 2 minutes si le rôle n'est pas encore trouvé) :

```bash
ID_EXPLOIT=$(az ad group show --group "${ST}-GRP-Exploitation" --query id --output tsv)
az role assignment create --assignee-object-id "$ID_EXPLOIT" \
  --assignee-principal-type Group --role "${ST}-Operateur-VM-Arveo" \
  --scope "$RG_APP_ID" --output none
az role assignment delete --assignee "$ID_EXPLOIT" \
  --role "Virtual Machine Contributor" --resource-group "rg-${ST}-app"
```

3. Vérifications :

```bash
az role definition list --custom-role-only true --scope "$RG_APP_ID" \
  --query "[?roleName=='${ST}-Operateur-VM-Arveo'].assignableScopes[]" --output tsv
az role assignment list --resource-group "rg-${ST}-app" \
  --query "[?principalName=='${ST}-GRP-Exploitation'].roleDefinitionName" --output tsv
```
Sortie attendue :
```
/subscriptions/1a2b3c4d-…/resourceGroups/rg-st07-app
st07-Operateur-VM-Arveo
```

Réponse attendue à la question du verrou : **non compatible**. Un verrou `ReadOnly` bloque les opérations d'écriture ET les actions déclenchées par une requête POST ; `start`, `restart`, `powerOff` et `deallocate` sont des POST. L'équipe ne pourrait plus démarrer ni arrêter les VM. Un verrou `CanNotDelete` est compatible : il bloque la suppression, pas les opérations d'exploitation.

### Pourquoi
- **Pas de `virtualMachines/*`** : le caractère générique inclurait `write` (redimensionnement) et `delete`.
- **`instanceView/read`** : nécessaire pour afficher l'état d'exécution (en cours, désallouée) ; sans lui, le portail n'affiche pas l'état réel.
- **`deallocate` en plus de `powerOff`** : seul `deallocate` arrête la facturation du calcul (rappel S2.1).
- **`disks/read` et `networkInterfaces/read`** : affichage complet de la VM dans le portail (onglets Disques et Réseau).
- **`resourceGroups/read`** : navigation jusqu'au groupe dans le portail.
- **`AssignableScopes` limité à `rg-stNN-app`** : le rôle ne peut pas être réutilisé ailleurs par erreur, et le stagiaire n'a de toute façon le droit `roleDefinitions/write` que sur ses groupes.
- **Création AVANT suppression** : l'équipe ne perd jamais l'accès pendant la bascule.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `RoleDefinitionWithSameNameExists` | Nom déjà utilisé dans le tenant (autre stagiaire, numéro erroné) | Vérifier le préfixe `stNN` |
| `AuthorizationFailed` à la création du rôle | `AssignableScopes` au niveau abonnement | Limiter au groupe `rg-stNN-app` |
| `Role '…' doesn't exist` à l'attribution | Réplication du nouveau rôle, ou scope de recherche abonnement | Attendre ; utiliser `--scope "$RG_APP_ID"` |
| Rôle absent de `az role definition list` | Recherche au scope abonnement par défaut | Ajouter `--scope "$RG_APP_ID"` |
| `InvalidActionOrNotAction` | Faute dans le nom d'une opération | `az provider operation show --namespace Microsoft.Compute --query "resourceTypes[?name=='virtualMachines'].operations[].name"` |
| Fichier JSON avec `${ST}` littéral | Heredoc écrit avec `<<'EOF'` (guillemets) | Utiliser `<<EOF` sans guillemets |

### Variantes acceptables
- **Portail** : `rg-stNN-app` → **Contrôle d'accès (IAM)** → **Ajouter** → **Ajouter un rôle personnalisé** → **Cloner un rôle** (Contributeur de machines virtuelles) → retirer les actions superflues. Plus visuel, mais le clonage part d'un rôle trop large : risque d'oubli d'une action `write`.
- **`Microsoft.Insights/metrics/read`** en plus : acceptable (consultation des métriques CPU pendant l'astreinte).
- **Ajout des opérations `virtualMachineScaleSets/start/action` et `virtualMachineScaleSets/deallocate/action`** : pertinent si l'équipe exploite aussi le VMSS du module 7 ; à justifier.
- **PowerShell Az** : `New-AzRoleDefinition -InputFile "role-$ST-operateur-vm.json"`.

---

## Bonus — Héritage automatique du centre de coût

### Solution

```bash
DEF_TAG=$(az policy definition list \
  --query "[?displayName=='Inherit a tag from the resource group if missing'].name" \
  --output tsv)
ROLE_ID=$(az policy definition show --name "$DEF_TAG" \
  --query "policyRule.then.details.roleDefinitionIds[0]" --output tsv)
for R in app spoke; do
  RG_ID=$(az group show --name "rg-${ST}-${R}" --query id --output tsv)
  for T in CentreDeCout Environnement; do
    az policy assignment create --name "pa-${ST}-tag-${T}-${R}" \
      --policy "$DEF_TAG" --scope "$RG_ID" \
      --params "{\"tagName\":{\"value\":\"${T}\"}}" \
      --mi-system-assigned --location francecentral \
      --role "$ROLE_ID" --identity-scope "$RG_ID" --output none
  done
done
```

Test (attendre quelques minutes après l'affectation) :

```bash
az network nsg create --resource-group "rg-${ST}-app" \
  --name "nsg-${ST}-tagtest" --location francecentral \
  --query "NewNSG.tags" --output json
az network nsg delete --resource-group "rg-${ST}-app" --name "nsg-${ST}-tagtest"
```
Sortie attendue :
```
{
  "CentreDeCout": "CC-IT-1042",
  "Environnement": "Prod"
}
```

Tâche de correction (ressources antérieures à l'affectation) :

```bash
az policy remediation create --name "rem-${ST}-tag-cc-app" \
  --policy-assignment "pa-${ST}-tag-CentreDeCout-app" --resource-group "rg-${ST}-app"
```

### Pourquoi
- **Effet `Modify`** : la stratégie complète la requête de création avant son exécution ; aucun tag n'est oublié, même par un script.
- **Identité managée** : nécessaire pour la tâche de correction, qui modifie des ressources EXISTANTES au nom de l'affectation.
- **Rôle lu dans la définition** (`roleDefinitionIds`) : évite de deviner le rôle et respecte le moindre privilège voulu par l'auteur de la définition.
- **Une affectation par tag** : la définition intégrée ne prend qu'un nom de tag en paramètre.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `The policy assignment … requires a managed identity` | Option `--mi-system-assigned` absente | Recréer l'affectation avec l'identité |
| `--location` requis | Identité managée sans région | Ajouter `--location francecentral` |
| NSG créé sans tags | Affectation trop récente | Attendre, supprimer et recréer le NSG |
| Tâche de correction en échec | Attribution de rôle de l'identité pas encore propagée | Relancer la tâche après quelques minutes |

---

## QCM — Réponses
1. **A** — Une ressource appartient à un seul groupe de ressources ; un déplacement la change de groupe.
2. **C** — Les tags ne sont pas hérités ; seule une stratégie (`Modify`, « Inherit a tag… ») les recopie.
3. **C** — Un budget envoie des notifications et peut déclencher un groupe d'actions, sans rien arrêter seul.
4. **B** — `Deny` refuse la requête ; `Audit` et `AuditIfNotExists` journalisent, `Append` complète.
5. **B** — Une définition personnalisée s'enregistre sur un groupe d'administration ou un abonnement.
6. **B** — Les droits effectifs sont l'union des rôles hérités et directs : Contributeur l'emporte.
7. **C** — Contributeur gère tout sauf les accès ; Propriétaire gère aussi les accès.
8. **B** — `ReadOnly` bloque les POST comme `start`, même pour un propriétaire.
