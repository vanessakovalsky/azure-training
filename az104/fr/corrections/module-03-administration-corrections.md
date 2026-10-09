# Module 03 — Corrections

Exemples donnés pour le stagiaire 07 (`NN=07`). Remplacer `07` par son numéro.

## Lab 03.1 ⭐ — Prise en main de Cloud Shell

### Solution
```bash
az account show --query "{Compte:user.name, Abonnement:name}" -o table
az version --query '"azure-cli"' -o tsv
az bicep version
az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
pwsh
```
```powershell
Get-AzContext | Select-Object Account, Subscription
exit
```

### Pourquoi
- Session éphémère : aucun compte de stockage à créer dans l'abonnement partagé, aucun droit supplémentaire requis.
- Vérification du compte actif avant toute action : un stagiaire connecté avec un compte personnel ou un autre tenant obtient des erreurs d'autorisation déroutantes plus tard.
- `az version --query '"azure-cli"'` : guillemets doubles internes obligatoires, le nom de clé contient un tiret.
- `pwsh` depuis Bash : même conteneur, même authentification ; démontre que CLI et PowerShell parlent au même ARM.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Cloud Shell demande de créer un compte de stockage | Option « éphémère » non sélectionnée | Fermer, rouvrir Cloud Shell > Paramètres > Réinitialiser les paramètres utilisateur `[À VÉRIFIER]` libellé, choisir l'option sans stockage |
| Erreur à l'ouverture de Cloud Shell mentionnant `Microsoft.CloudShell` | Fournisseur non enregistré sur l'abonnement `[À VÉRIFIER]` | Formatrice : `az provider register --namespace Microsoft.CloudShell` |
| `az account show` affiche un autre tenant | Compte personnel déjà connecté dans le navigateur | Fenêtre de navigation privée, reconnexion avec `st07@<DOMAINE>` |
| Session fermée en cours de lab | 20 min d'inactivité | Rouvrir Cloud Shell, redéfinir les variables (étape 1 du lab 03.2) |

## Lab 03.2 ⭐ — Azure CLI : contexte, tags et espace de travail Log Analytics

### Solution
```bash
NN=07
ST="st${NN}"
RG="rg-${ST}-shared"
LOC="francecentral"

az configure --defaults group="$RG" location="$LOC"
az configure --list-defaults -o table

az group list --query "[?starts_with(name, 'rg-${ST}-')].{Nom:name, Region:location}" -o table

RG_ID=$(az group show --name "$RG" --query id -o tsv)
az tag update --resource-id "$RG_ID" --operation Merge \
  --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
  --query "properties.tags"

az monitor log-analytics workspace create \
  --workspace-name "log-${ST}-shared" \
  --retention-time 30 \
  --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
  --query "{Nom:name, Etat:provisioningState, Retention:retentionInDays}" -o table

az resource list \
  --query "[].{Nom:name, Type:type, Proprietaire:tags.Proprietaire}" -o table

WS_ID=$(az monitor log-analytics workspace show -n "log-${ST}-shared" \
  --query customerId -o tsv)
echo "$WS_ID"
```

### Pourquoi
- `az configure --defaults` : `--resource-group` et `--location` deviennent facultatifs ; commandes plus courtes, mais risque d'agir sur le mauvais groupe si les valeurs par défaut sont oubliées.
- `[?starts_with(name, 'rg-${ST}-')]` : le rôle Lecteur sur l'abonnement rend visibles les groupes de TOUS les stagiaires ; le filtre isole les siens. Le `${ST}` est développé par Bash car la chaîne est entre guillemets doubles.
- `az tag update --operation Merge` : ajoute ou met à jour les tags fournis sans supprimer les autres. `Replace` remplacerait l'ensemble et pourrait retirer un tag exigé par une stratégie (refus `RequestDisallowedByPolicy`).
- Rétention 30 jours : valeur incluse sans surcoût de rétention `[À VÉRIFIER]` conditions tarifaires en vigueur.
- `customerId` (ID de l'espace de travail, GUID) ≠ `id` (ID de ressource ARM) : le premier sert aux agents et aux requêtes KQL, le second aux attributions RBAC et aux paramètres de diagnostic.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `AuthorizationFailed` | Groupe d'un autre stagiaire ou faute de frappe dans `NN` | `echo $RG`, corriger la variable |
| `RequestDisallowedByPolicy` | Tag manquant ou région non autorisée (stratégies du M2) | Vérifier `--tags` et `LOC`, consulter le détail de l'erreur (nom de l'affectation) |
| La liste des groupes est vide | `ST` vide (variables perdues après fermeture de session) | Redéfinir les variables de l'étape 1 |
| `MissingSubscriptionRegistration` pour `Microsoft.OperationalInsights` | Fournisseur non enregistré | Formatrice : `az provider register --namespace Microsoft.OperationalInsights` |
| `WS_ID` contient des guillemets | `-o json` au lieu de `-o tsv` | Relancer avec `-o tsv` |

## Exercice 03.3 ⭐⭐ — PowerShell Az : compte de stockage idempotent et inventaire

### Solution
Script `New-SocleStockage.ps1` :
```powershell
# New-SocleStockage.ps1 — compte de stockage de diagnostic du socle Arvéo
# Usage : ./New-SocleStockage.ps1 -Numero 07 [-Suffixe ab]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d{2}$')]
    [string] $Numero,

    [ValidatePattern('^[a-z0-9]{0,4}$')]
    [string] $Suffixe = ''
)

$ErrorActionPreference = 'Stop'

$st       = "st$Numero"
$rg       = "rg-$st-shared"
$location = 'francecentral'
$nom      = "starveo$($st)diag$Suffixe"
$tags     = @{ Projet = 'Arveo'; Environnement = 'Formation'; Proprietaire = $st }

$existant = Get-AzStorageAccount -ResourceGroupName $rg -Name $nom -ErrorAction SilentlyContinue
if ($existant) {
    Write-Output "Compte $nom déjà présent dans $rg : aucune action."
    return
}

$dispo = Get-AzStorageAccountNameAvailability -Name $nom
if (-not $dispo.NameAvailable) {
    throw "Nom $nom indisponible ($($dispo.Reason)). Relancer avec -Suffixe <2 lettres>."
}

New-AzStorageAccount -ResourceGroupName $rg -Name $nom -Location $location `
    -SkuName Standard_LRS -Kind StorageV2 -AccessTier Hot `
    -MinimumTlsVersion TLS1_2 -EnableHttpsTrafficOnly $true `
    -AllowBlobPublicAccess $false -Tag $tags | Out-Null

Write-Output "Compte $nom créé dans $rg."
```

Exécution et vérification :
```powershell
./New-SocleStockage.ps1 -Numero 07
./New-SocleStockage.ps1 -Numero 07
Get-AzStorageAccount -ResourceGroupName rg-st07-shared -Name starveost07diag |
  Select-Object MinimumTlsVersion, AllowBlobPublicAccess, EnableHttpsTrafficOnly
```
Sortie attendue :
```
Compte starveost07diag créé dans rg-st07-shared.
Compte starveost07diag déjà présent dans rg-st07-shared : aucune action.

MinimumTlsVersion AllowBlobPublicAccess EnableHttpsTrafficOnly
----------------- --------------------- ----------------------
TLS1_2                            False                   True
```

Inventaire :
```powershell
$st = 'st07'
Get-AzResource |
  Where-Object ResourceGroupName -like "rg-$st-*" |
  Select-Object Name, ResourceType, ResourceGroupName, Location,
    @{ Name = 'Proprietaire'; Expression = { $_.Tags['Proprietaire'] } } |
  Export-Csv -Path "./inventaire-$st.csv" -NoTypeInformation -Encoding utf8

Import-Csv "./inventaire-$st.csv" | Format-Table
```
Sortie attendue :
```
Name            ResourceType                             ResourceGroupName Location      Proprietaire
----            ------------                             ----------------- --------      ------------
log-st07-shared Microsoft.OperationalInsights/workspaces rg-st07-shared    francecentral st07
starveost07diag Microsoft.Storage/storageAccounts        rg-st07-shared    francecentral st07
```

### Pourquoi
- `$ErrorActionPreference = 'Stop'` : toute erreur non gérée interrompt le script ; sans cela, PowerShell poursuit après une erreur non bloquante et affiche un faux succès.
- `-ErrorAction SilentlyContinue` sur `Get-AzStorageAccount` : l'absence du compte est un cas attendu, pas une erreur ; ce paramètre local prime sur la préférence globale.
- `return` dans le bloc « déjà présent » : sortie propre, code retour sans erreur, script rejouable (idempotence).
- `Get-AzStorageAccountNameAvailability` : le nom est global à Azure ; la vérification donne un message clair au lieu d'une erreur `StorageAccountAlreadyTaken` en fin de création.
- `ValidatePattern` : rejet d'un numéro mal formé AVANT tout appel à Azure (même principe que les décorateurs Bicep).
- `-AllowBlobPublicAccess $false`, `-MinimumTlsVersion TLS1_2` : paramètres de sécurité attendus par la DSI et réévalués au module 6.
- `Get-AzResource` puis filtre : le rôle Lecteur sur l'abonnement donne une vue complète, le filtre `-like` (insensible à la casse) restreint aux groupes du stagiaire.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `Nom starveost07diag indisponible (AlreadyExists)` | Nom déjà pris dans Azure (autre session, autre client) | Relancer avec `-Suffixe` (2 lettres, ex. initiales) et noter le nom pour le défi 03.5 |
| `A parameter cannot be found that matches parameter name 'MinimumTlsVersion'` | Module Az.Storage ancien (poste local) | Utiliser Cloud Shell ou `Update-Module Az.Storage` |
| La deuxième exécution recrée ou échoue | `-ErrorAction SilentlyContinue` oublié : l'absence du compte stoppe le script | Ajouter le paramètre sur `Get-AzStorageAccount` |
| Colonne `Proprietaire` vide | `$_.Tags.Proprietaire` sur une ressource sans tag, ou faute de casse dans la clé | Vérifier la clé exacte avec `(Get-AzResource -Name <NOM>).Tags` |
| Accents illisibles dans le CSV ouvert sous Excel | Encodage sans BOM | `-Encoding utf8BOM` (PowerShell 7) |
| Script refusé : `cannot be loaded because running scripts is disabled` | Poste Windows local, stratégie d'exécution | Cloud Shell n'est pas concerné ; en local : `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |

### Variantes acceptables
- `try { Get-AzStorageAccount ... } catch { ... }` au lieu de `-ErrorAction SilentlyContinue` : plus explicite, plus long.
- Inventaire en Azure CLI : `az resource list --query "[?starts_with(resourceGroup, 'rg-st07-')]"` puis `-o tsv` redirigé vers un fichier ; correct, mais en-têtes à ajouter à la main.
- Nom calculé avec un suffixe aléatoire (`Get-Random`) : unicité garantie mais nom non prévisible, à éviter pour un socle référencé par d'autres modules.

## Exercice 03.4 ⭐⭐ — Lire un modèle ARM JSON, le déployer, le convertir en Bicep

### Solution
Réponses de lecture :
- Deux paramètres : `numero` (obligatoire, aucune `defaultValue`) et `location` (facultatif).
- Type `Microsoft.ManagedIdentity/userAssignedIdentities`, nom `id-st07-deploy` pour le stagiaire 07 (`prefix` = `st07`).
- Sans `location` : région du groupe de ressources cible (`resourceGroup().location`), soit `francecentral` pour `rg-st07-shared`.

Déploiement :
```bash
az deployment group create \
  --resource-group rg-st07-shared \
  --name identite-arm \
  --template-file identite.json \
  --parameters numero=07 \
  --query "properties.outputs.principalId.value" -o tsv
```
Sortie attendue : un GUID (identifiant du principal de service de l'identité dans Entra ID).

Conversion et comparaison :
```bash
az bicep decompile --file identite.json
wc -l identite.json identite.bicep
```
Sortie attendue (Bicep CLI 0.48, extrait) :
```
WARNING: Decompilation is a best-effort process, as there is no guaranteed mapping from ARM JSON to Bicep Template or Bicep Parameters.
identite.bicep(21,29) : Warning use-resource-symbol-reference: Use a resource reference instead of invoking function "reference".
  42 identite.json
  21 identite.bicep
  63 total
```
Le libellé des avertissements peut varier selon la version de Bicep.

Fichier `identite.bicep` obtenu :
```bicep
@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string
param location string = resourceGroup().location

var prefix = 'st${numero}'
var identityName = 'id-${prefix}-deploy'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

output principalId string = reference(identity.id, '2023-01-31').principalId
```

Nettoyage recommandé par le linter (dernière ligne) :
```bicep
output principalId string = identity.properties.principalId
```

Prévisualisation :
```bash
az deployment group what-if \
  --resource-group rg-st07-shared \
  --template-file identite.bicep \
  --parameters numero=07
```
Sortie attendue (fin) :
```
  = Microsoft.ManagedIdentity/userAssignedIdentities/id-st07-deploy [2023-01-31]

Resource changes: 1 no change.
```

### Pourquoi
- `--query "properties.outputs.principalId.value"` : chaque sortie de déploiement est un objet `{ type, value }`.
- Le `principalId` servira à attribuer des rôles RBAC à l'identité (modules 7 et 8) ; le récupérer par sortie évite une recherche manuelle.
- `reference()` : la décompilation le conserve tel quel ; le linter recommande l'accès symbolique `identity.properties.principalId`, même appel ARM, dépendance explicite pour Bicep. Illustration du « au mieux » : le code décompilé se relit et se nettoie.
- `what-if` sans changement = preuve que le fichier Bicep décrit EXACTEMENT l'existant ; la conversion est validée sans risque.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `InvalidTemplate ... Unable to parse` | JSON mal collé (guillemet ou virgule manquants) | `az deployment group validate` ou `python3 -m json.tool identite.json` pour localiser la ligne |
| `The value of parameter numero is not valid` / longueur | `numero=7` au lieu de `numero=07` | Toujours deux chiffres |
| `--query` renvoie vide | Chemin incorrect (`outputs.principalId` sans `properties`) | `--query properties.outputs` pour explorer |
| `identite.bicep` existe déjà, decompile refuse | Deuxième exécution | Option `--force` `[À VÉRIFIER]` ou supprimer le fichier |
| `what-if` affiche `~` sur `tags` | Tag modifié à la main entre-temps | Normal : `what-if` révèle la dérive ; redéployer ou corriger le fichier |

### Variantes acceptables
- Déploiement en PowerShell : `New-AzResourceGroupDeployment -ResourceGroupName rg-st07-shared -Name identite-arm -TemplateFile identite.json -numero '07'` puis `(Get-AzResourceGroupDeployment -ResourceGroupName rg-st07-shared -Name identite-arm).Outputs.principalId.Value`.
- Déploiement par le portail : **Déployer un modèle personnalisé** > **Créer votre propre modèle** > coller le JSON. Correct, mais non reproductible par script.
- Noms symboliques renommés après décompilation (`identity` → `identite`) : recommandé pour la lisibilité, sans effet sur le déploiement.

## Défi 03.5 ⭐⭐⭐ — Reprendre le socle sous IaC et corriger une dérive

### Solution
Fichier `socle.bicep` (identique au script de rattrapage `scripts/catch-up/module-03/main.bicep`) :
```bicep
// socle.bicep — socle partagé Arvéo (rg-stNN-shared)
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Région de déploiement')
@allowed([ 'francecentral', 'westeurope' ])
param location string = 'francecentral'

@description('Nom du compte de stockage de diagnostic (3 à 24 minuscules ou chiffres)')
@minLength(3)
@maxLength(24)
param storageName string = 'starveost${numero}diag'

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${prefix}-shared'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource diagStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-deploy'
  location: location
  tags: tags
}

output workspaceId string = workspace.id
output storageAccountId string = diagStorage.id
output identityPrincipalId string = deployIdentity.properties.principalId
```

Contrôle, déploiement, dérive, correction :
```bash
az bicep build --file socle.bicep --stdout > /dev/null && echo "Syntaxe OK"

az deployment group what-if -g rg-st07-shared \
  --template-file socle.bicep --parameters numero=07

az deployment group create -g rg-st07-shared --name socle \
  --template-file socle.bicep --parameters numero=07 \
  --query "properties.provisioningState" -o tsv

# Dérive simulée
az storage account update -n starveost07diag -g rg-st07-shared --access-tier Cool
az tag update --resource-id "$(az storage account show -n starveost07diag \
  -g rg-st07-shared --query id -o tsv)" --operation Merge --tags Temporaire=oui

# Détection puis correction
az deployment group what-if -g rg-st07-shared \
  --template-file socle.bicep --parameters numero=07
az deployment group create -g rg-st07-shared --name socle \
  --template-file socle.bicep --parameters numero=07 \
  --query "properties.provisioningState" -o tsv

az storage account show -n starveost07diag -g rg-st07-shared \
  --query "{Niveau:accessTier, Tags:tags}"
```
Sortie attendue du `what-if` après dérive (extrait) :
```
  ~ Microsoft.Storage/storageAccounts/starveost07diag [2023-05-01]
    - tags.Temporaire: "oui"
    ~ properties.accessTier: "Cool" => "Hot"

  = Microsoft.ManagedIdentity/userAssignedIdentities/id-st07-deploy [2023-01-31]
  = Microsoft.OperationalInsights/workspaces/log-st07-shared [2023-09-01]

Resource changes: 1 to modify, 2 no change.
```
Sortie attendue de la vérification finale :
```
{
  "Niveau": "Hot",
  "Tags": {
    "Environnement": "Formation",
    "Projet": "Arveo",
    "Proprietaire": "st07"
  }
}
```
Si le compte a été créé avec un suffixe à l'exercice 03.3 : ajouter `storageName=starveost07diag<SUFFIXE>` dans `--parameters`.

### Pourquoi
- Un fichier, trois ressources créées par trois outils : ARM ne connaît que l'état des ressources, pas l'outil d'origine. Décrire l'existant à l'identique = reprise sous IaC sans recréation.
- `tags` déclaré une seule fois en variable : cohérence garantie, une seule ligne à modifier.
- `storageName` en paramètre avec valeur par défaut : cas général sans paramètre, cas du suffixe couvert.
- Propriété `tags` déclarée = ensemble complet : le redéploiement supprime le tag `Temporaire` ajouté à la main. Le fichier est la source de vérité.
- Mode Incremental : les éventuelles autres ressources du groupe (bonus, template spec) sont conservées.
- Sorties : `workspaceId` (ID ARM) sera passé aux paramètres de diagnostic au module 10 ; `identityPrincipalId` aux attributions RBAC.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `what-if` annonce `+ Create` pour le compte de stockage | Nom différent de l'existant (suffixe oublié) | Passer `storageName=<NOM_REEL>` |
| `what-if` affiche `~` sur des propriétés de l'espace de travail non déclarées (`features`, `workspaceCapping`) | Valeurs par défaut posées par la CLI à la création, comparées au fichier | Bruit acceptable : vérifier qu'aucune valeur métier ne change ; option `--result-format ResourceIdOnly` pour un résumé `[À VÉRIFIER]` |
| Avertissement linter `use-recent-api-versions` | Versions d'API plus récentes disponibles | Sans effet sur le déploiement ; mettre à jour après test |
| `BCP035` / `BCP037` | Propriété mal orthographiée ou mal placée (`accessTier` hors de `properties`) | Lire la position de l'erreur, utiliser la complétion de VS Code |
| `RequestDisallowedByPolicy` sur le compte de stockage | Stratégie du M2 (tag, région ou paramètre de sécurité) | Lire `policyAssignmentName` dans l'erreur, aligner le fichier |
| `InvalidTemplateDeployment` sur la région | `location` hors de la liste `@allowed` | Normal : la validation joue son rôle |

### Variantes acceptables
- Ressources existantes référencées avec `existing` au lieu d'être redéclarées : valide pour les LIRE, mais aucune correction de dérive possible (le fichier ne décrit plus l'état voulu).
- Tags passés en paramètre objet (`param tags object`) : plus souple, mais risque de valeurs divergentes entre stagiaires.
- Un module Bicep par ressource (`modules/workspace.bicep`) : structure recommandée pour un socle plus large, surdimensionnée pour trois ressources.
- Corriger la dérive par `az storage account update --access-tier Hot` : résultat identique ici, mais correction manuelle non tracée, contraire à l'objectif.

## Bonus

### 1. Fichier de paramètres `.bicepparam`
```bicep
// socle.bicepparam
using './socle.bicep'

param numero = '07'
```
```bash
az deployment group create -g rg-st07-shared --name socle \
  --parameters socle.bicepparam \
  --query "properties.provisioningState" -o tsv
```
Sortie attendue :
```
Succeeded
```
`using` relie le fichier de paramètres au modèle : `--template-file` devient inutile (Azure CLI 2.53 ou supérieur `[À VÉRIFIER]`).

### 2. Template spec
```bash
az ts create --name ts-st07-socle --version 1.0 \
  --resource-group rg-st07-shared --location francecentral \
  --template-file socle.bicep --query id -o tsv

TS_ID=$(az ts show --name ts-st07-socle --version 1.0 \
  --resource-group rg-st07-shared --query id -o tsv)

az deployment group create -g rg-st07-shared --name socle-ts \
  --template-spec "$TS_ID" --parameters numero=07 \
  --query "properties.provisioningState" -o tsv
```
Sortie attendue : un ID de ressource `.../templateSpecs/ts-st07-socle/versions/1.0`, puis `Succeeded`.
Intérêt : modèle versionné stocké dans Azure, partageable par RBAC (rôle Lecteur sur la template spec) sans dépôt Git.

### 3. Déploiement PowerShell avec `-WhatIf`
```powershell
New-AzResourceGroupDeployment -ResourceGroupName rg-st07-shared `
  -TemplateFile ./socle.bicep -numero '07' -WhatIf
```
Même résultat que `az deployment group what-if`, même moteur côté ARM. `-numero` est un paramètre dynamique généré à partir des paramètres du modèle. Bicep CLI doit être présent dans le `PATH` (cas de Cloud Shell).

## QCM — Réponses
1. **C** — ARM est le point d'entrée unique du plan de contrôle ; Graph gère les objets Entra ID, Policy est un contrôle appliqué par ARM.
2. **A** — Propriétaire agit sur le plan de contrôle ; la lecture des blobs via Entra ID exige un rôle de données (ex. Lecteur des données Blob du stockage).
3. **D** — `--query id` extrait la propriété, `-o tsv` la renvoie brute, sans guillemets JSON.
4. **C** — La CLI produit du texte (JSON par défaut) ; PowerShell Az manipule des objets .NET typés dans le pipeline.
5. **B** — Le mode Incremental ne touche pas aux ressources non déclarées ; seul le mode Complete les supprime.
6. **C** — `what-if` calcule et affiche le différentiel sans rien appliquer.
7. **A** — Bicep est un langage transpilé en ARM JSON ; aucun fichier d'état, aucun agent.
8. **D** — `@secure()` masque la valeur dans l'historique et les journaux de déploiement.
9. **B** — `MissingSubscriptionRegistration` = fournisseur de ressources non enregistré ; l'enregistrement se fait au niveau abonnement.
