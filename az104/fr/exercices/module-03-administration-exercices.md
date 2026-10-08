# Module 03 — Exercices

Fil rouge : constitution du **socle partagé Arvéo** dans `rg-stNN-shared`, réutilisé aux modules 7 (diagnostics de démarrage) et 10 (supervision).

| Ressource | Nom (stagiaire 07) | Outil de création | Lab |
|---|---|---|---|
| Espace de travail Log Analytics | `log-st07-shared` | Azure CLI | 03.2 |
| Compte de stockage de diagnostic | `starveost07diag` | PowerShell Az | 03.3 |
| Identité managée affectée par l'utilisateur | `id-st07-deploy` | Modèle ARM JSON | 03.4 |
| Les trois, repris sous IaC | `socle.bicep` | Bicep | 03.5 |

Variables utilisées dans tous les labs :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<DOMAINE>` = domaine du tenant de formation, communiqué par la formatrice

Tags obligatoires sur chaque ressource (stratégie du module 2) : `Projet=Arveo`, `Environnement=Formation`, `Proprietaire=st<NN>`.

---

## Lab 03.1 ⭐ — Prise en main de Cloud Shell (guidé)
**Durée** : 5 min · **Objectif** : ouvrir un terminal authentifié et vérifier le contexte de travail (objectif 4)
**Contexte** : les équipes d'Arvéo n'installent aucun outil sur leurs postes ; toute l'administration passe par Cloud Shell.
**Prérequis** : compte `st<NN>@<DOMAINE>` avec méthode MFA enregistrée (M0) ; navigateur récent.

### Étapes
1. Se connecter au portail `https://portal.azure.com` avec `st<NN>@<DOMAINE>`.
   Résultat attendu : page d'accueil du portail, nom du tenant de formation en haut à droite.

2. Ouvrir Cloud Shell (icône `>_` de la barre supérieure), choisir **Bash**.
   À l'écran de première utilisation : sélectionner **Aucun compte de stockage requis** `[À VÉRIFIER]` libellé exact, puis l'abonnement de formation, puis **Appliquer**.
   Résultat attendu : invite `st07 [ ~ ]$` (ou proche) après quelques secondes.

3. Vérifier le compte et l'abonnement actifs.
   ```bash
   az account show --query "{Compte:user.name, Abonnement:name}" -o table
   ```
   Résultat attendu :
   ```
   Compte                               Abonnement
   -----------------------------------  ------------------------
   st07@<DOMAINE>                       <NOM_ABONNEMENT>
   ```

4. Vérifier les versions des outils.
   ```bash
   az version --query '"azure-cli"' -o tsv
   az bicep version
   ```
   Résultat attendu : une version `2.x` pour Azure CLI, puis `Bicep CLI version 0.x.y` `[À VÉRIFIER]` versions du jour.

5. Vérifier qu'un fournisseur de ressources utilisé dans le module est enregistré.
   ```bash
   az provider show --namespace Microsoft.OperationalInsights --query registrationState -o tsv
   ```
   Résultat attendu :
   ```
   Registered
   ```

6. Basculer en PowerShell depuis la même session, puis revenir.
   ```bash
   pwsh
   ```
   ```powershell
   Get-AzContext | Select-Object Account, Subscription
   exit
   ```
   Résultat attendu : compte `st07@<DOMAINE>` et l'abonnement de formation ; retour à l'invite Bash après `exit`.

7. Dans le portail, ouvrir le groupe de ressources `rg-st<NN>-shared` > **Journal d'activité**.
   Résultat attendu : opérations du module 2 (tags, attributions) visibles, avec l'auteur et le statut.

### Critères de réussite
- [ ] `az account show` affiche le compte `st<NN>@<DOMAINE>`.
- [ ] `az provider show` renvoie `Registered`.
- [ ] `Get-AzContext` affiche le même compte depuis PowerShell.

---

## Lab 03.2 ⭐ — Azure CLI : contexte, tags et espace de travail Log Analytics (guidé)
**Durée** : 10 min · **Objectif** : créer et interroger une ressource avec Azure CLI (objectif 4)
**Contexte** : Arvéo centralise les journaux de la future landing zone dans un espace de travail Log Analytics unique par environnement, placé dans `rg-stNN-shared`.
**Prérequis** : Lab 03.1 terminé, Cloud Shell en Bash.

### Étapes
1. Définir les variables de session. Remplacer `<NN>` par son numéro.
   ```bash
   NN=<NN>
   ST="st${NN}"
   RG="rg-${ST}-shared"
   LOC="francecentral"
   echo "$ST $RG $LOC"
   ```
   Résultat attendu (stagiaire 07) :
   ```
   st07 rg-st07-shared francecentral
   ```

2. Configurer les valeurs par défaut de la CLI.
   ```bash
   az configure --defaults group="$RG" location="$LOC"
   az configure --list-defaults -o table
   ```
   Résultat attendu : deux lignes `group` = `rg-st07-shared` et `location` = `francecentral`.

3. Lister uniquement ses propres groupes de ressources.
   ```bash
   az group list --query "[?starts_with(name, 'rg-${ST}-')].{Nom:name, Region:location}" -o table
   ```
   Résultat attendu :
   ```
   Nom             Region
   --------------  -------------
   rg-st07-app     francecentral
   rg-st07-data    francecentral
   rg-st07-hub     francecentral
   rg-st07-lyon    francecentral
   rg-st07-shared  francecentral
   rg-st07-spoke   francecentral
   ```
   La région de `rg-st07-lyon` dépend du script de provisioning `[À VÉRIFIER]`.

4. Fusionner les tags Arvéo sur le groupe `rg-stNN-shared` (sans écraser les tags existants).
   ```bash
   RG_ID=$(az group show --name "$RG" --query id -o tsv)
   az tag update --resource-id "$RG_ID" --operation Merge \
     --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
     --query "properties.tags"
   ```
   Résultat attendu :
   ```
   {
     "Environnement": "Formation",
     "Projet": "Arveo",
     "Proprietaire": "st07"
   }
   ```
   (d'autres tags posés au module 2 peuvent apparaître : ils sont conservés)

5. Créer l'espace de travail Log Analytics.
   ```bash
   az monitor log-analytics workspace create \
     --workspace-name "log-${ST}-shared" \
     --retention-time 30 \
     --tags Projet=Arveo Environnement=Formation Proprietaire="$ST" \
     --query "{Nom:name, Etat:provisioningState, Retention:retentionInDays}" -o table
   ```
   Résultat attendu (30 à 60 secondes) :
   ```
   Nom              Etat       Retention
   ---------------  ---------  -----------
   log-st07-shared  Succeeded  30
   ```

6. Lister les ressources du groupe avec une projection JMESPath.
   ```bash
   az resource list \
     --query "[].{Nom:name, Type:type, Proprietaire:tags.Proprietaire}" -o table
   ```
   Résultat attendu :
   ```
   Nom              Type                                      Proprietaire
   ---------------  ----------------------------------------  ------------
   log-st07-shared  Microsoft.OperationalInsights/workspaces  st07
   ```

7. Récupérer l'identifiant de l'espace de travail dans une variable (utilisé au module 10).
   ```bash
   WS_ID=$(az monitor log-analytics workspace show -n "log-${ST}-shared" \
     --query customerId -o tsv)
   echo "$WS_ID"
   ```
   Résultat attendu : un GUID seul, sans guillemets (ex. `3f2b9c1e-8a4d-4c55-9e0b-2d7f1a6c4b90`, valeur propre à chaque espace de travail).

### Critères de réussite
- [ ] `az configure --list-defaults -o table` affiche `rg-st<NN>-shared` et `francecentral`.
- [ ] `az group show -n rg-st<NN>-shared --query tags` contient `Projet`, `Environnement`, `Proprietaire`.
- [ ] `az monitor log-analytics workspace show -n log-st<NN>-shared --query provisioningState -o tsv` renvoie `Succeeded`.
- [ ] `echo "$WS_ID"` affiche un GUID sans guillemets.

---

## Exercice 03.3 ⭐⭐ — PowerShell Az : compte de stockage idempotent et inventaire (semi-autonome)
**Durée** : 10 min · **Objectif** : créer une ressource par script réutilisable et produire un rapport avec PowerShell Az (objectif 4)

> 🔸 **Session ajustée** : cet exercice est traité en démonstration par la formatrice. À faire en autonomie si vous avez terminé les labs 03.1 et 03.2, pendant les labs du M4.
**Contexte** : les VMs d'Arvéo (M7) écriront leurs diagnostics de démarrage dans un compte de stockage dédié. La DSI exige un script rejouable sans erreur et un inventaire CSV des ressources de chaque environnement.

**Énoncé** :
1. Dans Cloud Shell en PowerShell, écrire un script `New-SocleStockage.ps1` qui prend en paramètre le numéro de stagiaire et crée dans `rg-st<NN>-shared` le compte de stockage `starveost<NN>diag` avec :
   - performance Standard, redondance LRS, type StorageV2, niveau d'accès Hot ;
   - version TLS minimale 1.2, trafic HTTPS uniquement, accès public anonyme aux blobs désactivé ;
   - les trois tags Arvéo.
2. Le script doit :
   - s'arrêter à la première erreur ;
   - ne rien faire (et l'afficher) si le compte existe déjà ;
   - vérifier la disponibilité du nom avant la création et accepter un suffixe facultatif si le nom est pris.
3. Exécuter le script deux fois de suite : la deuxième exécution ne doit produire aucune erreur.
4. Produire `inventaire-st<NN>.csv` listant toutes les ressources des groupes `rg-st<NN>-*` avec les colonnes `Name`, `ResourceType`, `ResourceGroupName`, `Location`, `Proprietaire` (valeur du tag).

**Indices** :
- Édition du script dans Cloud Shell : `code New-SocleStockage.ps1`.
- Cmdlets utiles : `Get-AzStorageAccount`, `Get-AzStorageAccountNameAvailability`, `New-AzStorageAccount`, `Get-AzResource`, `Export-Csv`.
- `Get-Help New-AzStorageAccount -Parameter MinimumTlsVersion` pour la syntaxe exacte d'un paramètre.
- Nom de compte de stockage : 3 à 24 caractères, minuscules et chiffres uniquement, unique dans tout Azure.
- Propriété calculée : `@{ Name = '<COLONNE>'; Expression = { <EXPRESSION> } }`.

**Critères de réussite** :
- [ ] `Get-AzStorageAccount -ResourceGroupName rg-st<NN>-shared -Name starveost<NN>diag | Select-Object MinimumTlsVersion, AllowBlobPublicAccess, EnableHttpsTrafficOnly` affiche `TLS1_2`, `False`, `True`.
- [ ] La deuxième exécution du script affiche un message « déjà présent » et aucune erreur.
- [ ] `Import-Csv ./inventaire-st<NN>.csv | Format-Table` affiche au moins `log-st<NN>-shared` et `starveost<NN>diag`, avec `st<NN>` dans la colonne `Proprietaire`.

---

## Exercice 03.4 ⭐⭐ — Lire un modèle ARM JSON, le déployer, le convertir en Bicep (semi-autonome)
**Durée** : 10 min · **Objectif** : lire et déployer un modèle ARM JSON, puis le convertir en Bicep (objectif 4)

> 🔸 **Session ajustée** : cet exercice est projeté en démonstration par la formatrice. À faire en autonomie si vous avez terminé les labs 03.1 et 03.2, pendant les labs du M4.
**Contexte** : l'ancien prestataire d'Arvéo a laissé un modèle ARM JSON qui crée l'identité managée utilisée plus tard par les scripts de déploiement. La décision est prise de migrer tous les modèles vers Bicep.

**Fichier fourni** : créer `identite.json` dans Cloud Shell (`code identite.json`) avec ce contenu exact.
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "numero": {
      "type": "string",
      "minLength": 2,
      "maxLength": 2,
      "metadata": {
        "description": "Numéro du stagiaire sur deux chiffres"
      }
    },
    "location": {
      "type": "string",
      "defaultValue": "[resourceGroup().location]"
    }
  },
  "variables": {
    "prefix": "[format('st{0}', parameters('numero'))]",
    "identityName": "[format('id-{0}-deploy', variables('prefix'))]",
    "tags": {
      "Projet": "Arveo",
      "Environnement": "Formation",
      "Proprietaire": "[variables('prefix')]"
    }
  },
  "resources": [
    {
      "type": "Microsoft.ManagedIdentity/userAssignedIdentities",
      "apiVersion": "2023-01-31",
      "name": "[variables('identityName')]",
      "location": "[parameters('location')]",
      "tags": "[variables('tags')]"
    }
  ],
  "outputs": {
    "principalId": {
      "type": "string",
      "value": "[reference(resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', variables('identityName')), '2023-01-31').principalId]"
    }
  }
}
```

**Énoncé** :
1. Sans rien déployer, répondre par écrit :
   - combien de paramètres le modèle attend-il, et lequel est obligatoire ?
   - quel type de ressource est créé, et sous quel nom pour le stagiaire 07 ?
   - dans quelle région la ressource est-elle créée si `location` n'est pas fourni ?
2. Déployer le modèle dans `rg-st<NN>-shared` sous le nom de déploiement `identite-arm`, et afficher uniquement la sortie `principalId`.
3. Retrouver ce déploiement dans le portail (groupe de ressources > Déploiements) et consulter l'onglet **Modèle**.
4. Convertir `identite.json` en `identite.bicep`, comparer les deux fichiers (nombre de lignes, lisibilité).
5. Prévisualiser le déploiement du fichier Bicep : le résultat attendu ne comporte aucune création ni modification.

**Indices** :
- `az deployment group create --help` : paramètres `--name`, `--template-file`, `--parameters`, `--query`.
- Sorties d'un déploiement : `properties.outputs`.
- Conversion : `az bicep decompile`.
- Comptage de lignes : `wc -l identite.json identite.bicep`.

**Critères de réussite** :
- [ ] `az identity show -n id-st<NN>-deploy -g rg-st<NN>-shared --query tags` affiche les trois tags Arvéo.
- [ ] `az deployment group show -n identite-arm -g rg-st<NN>-shared --query properties.provisioningState -o tsv` renvoie `Succeeded`.
- [ ] Le `what-if` du fichier Bicep se termine par `Resource changes: 1 no change.`

---

## Défi 03.5 ⭐⭐⭐ — Reprendre le socle sous IaC et corriger une dérive (autonome)
**Durée** : 10 min · **Objectif** : déployer un fichier Bicep paramétré de façon reproductible après contrôle `what-if` (objectif 4)

> 🔸 **Session ajustée** : remplacé par `./scripts/m3/deploy.sh <NN>` (déploie les trois ressources du socle en 1–2 min). À faire en autonomie si vous êtes en avance.
**Contexte** : le socle `rg-stNN-shared` a été construit avec trois outils différents. La DSI d'Arvéo veut un fichier unique, source de vérité, capable de recréer le socle à l'identique et de corriger toute modification manuelle.

**Énoncé** :
1. Écrire `socle.bicep` décrivant les trois ressources existantes : `log-st<NN>-shared`, `starveost<NN>diag`, `id-st<NN>-deploy`, avec les mêmes propriétés et les trois tags.
2. Contraintes :
   - un seul paramètre obligatoire : le numéro de stagiaire, validé sur deux caractères ;
   - nom du compte de stockage surchargeable par paramètre (cas du suffixe de l'exercice 03.3) ;
   - région limitée à `francecentral` et `westeurope` ;
   - tags définis une seule fois dans le fichier ;
   - trois sorties : ID de l'espace de travail, ID du compte de stockage, `principalId` de l'identité.
3. `what-if` : aucune création ni suppression (des modifications mineures de propriétés non déclarées sont admises, à expliquer).
4. Déployer, puis simuler une dérive :
   ```bash
   az storage account update -n starveost<NN>diag -g rg-st<NN>-shared --access-tier Cool
   az tag update --resource-id "$(az storage account show -n starveost<NN>diag \
     -g rg-st<NN>-shared --query id -o tsv)" --operation Merge --tags Temporaire=oui
   ```
5. Détecter la dérive avec `what-if`, la corriger en redéployant, puis prouver que le compte est revenu à l'état décrit.

**Critères de réussite** :
- [ ] `az bicep build --file socle.bicep` ne produit aucune erreur.
- [ ] Le `what-if` après dérive affiche `~` sur le compte de stockage, avec `accessTier` modifié et `tags.Temporaire` supprimé.
- [ ] Après redéploiement, `az storage account show -n starveost<NN>diag --query "{Niveau:accessTier, Tags:tags}"` affiche `Hot` et exactement les trois tags Arvéo.
- [ ] Un nouveau `what-if` ne signale aucun changement sur le compte de stockage.

---

## Bonus 🚀
1. **Fichier de paramètres** : créer `socle.bicepparam` (paramètre `numero`), puis déployer avec `--parameters socle.bicepparam` seul, sans `--template-file`.
2. **Template spec** : publier `socle.bicep` comme template spec `ts-st<NN>-socle` en version `1.0` dans `rg-st<NN>-shared`, puis déployer depuis cette template spec.
3. **Comparaison** : déployer `socle.bicep` depuis PowerShell (`New-AzResourceGroupDeployment`) avec `-WhatIf`, et comparer l'affichage avec celui de la CLI.

## Nettoyage
- Aucune suppression : le socle `rg-st<NN>-shared` est réutilisé aux modules 7 et 10.
- Coût : espace de travail sans ingestion et compte de stockage vide = coût quasi nul `[À VÉRIFIER]` calculatrice de prix Azure.
- Bonus 2 : la template spec peut rester (aucun coût) ou être supprimée avec `az ts delete --name ts-st<NN>-socle -g rg-st<NN>-shared --yes`.
