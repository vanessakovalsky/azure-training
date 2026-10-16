# Module 06 — Corrections

Exemples donnés pour le stagiaire 07, session `2610` (`NN=07`, `OCT=7`, `SES=2610`). Toutes les solutions supposent le bloc de variables des exercices exécuté dans Cloud Shell (Bash), fonctions `tester` et `lyon` comprises. Les identifiants (GUID, versions, horodatages) varient d'une exécution à l'autre.

## Lab 06.1 ⭐ — Compte de données et redondance

### Solution
```bash
# 1. Disponibilité des noms
az storage account check-name --name "st-${NN}-data" --query "[nameAvailable, reason]" -o tsv
az storage account check-name --name "$SA_DATA" --query nameAvailable -o tsv

# 2. Création en LRS, sécurisée dès le départ
az storage account create -g "$RG_DATA" -n "$SA_DATA" -l "$LOC" \
  --kind StorageV2 --sku Standard_LRS --access-tier Hot \
  --min-tls-version TLS1_2 --allow-blob-public-access false \
  --tags $TAGS \
  --query "[provisioningState, primaryLocation, sku.name]" -o tsv
```
Sortie attendue :
```
false	AccountNameInvalid
true
Succeeded	francecentral	Standard_LRS
```

```bash
# 3. Points de terminaison
az storage account show -g "$RG_DATA" -n "$SA_DATA" \
  --query "primaryEndpoints.{Blob:blob, Fichiers:file, Files_attente:queue, Tables:table}" -o table

# 4. Passage en RA-GRS
az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Standard_RAGRS \
  --query "{SKU:sku.name, Secondaire:secondaryLocation, Etat:statusOfSecondary}" -o table
az storage account show -g "$RG_DATA" -n "$SA_DATA" --query secondaryEndpoints.blob -o tsv

# 5. État de la réplication géographique
az storage account show -g "$RG_DATA" -n "$SA_DATA" --expand geoReplicationStats \
  --query "geoReplicationStats.{Etat:status, DerniereSynchro:lastSyncTime}" -o table
```
Sortie attendue (étapes 4 et 5) :
```
SKU             Secondaire    Etat
--------------  ------------  ---------
Standard_RAGRS  francesouth   available
https://starveost07data2610-secondary.blob.core.windows.net/
Etat    DerniereSynchro
------  -------------------------
Live    2026-10-08T07:21:44+00:00
```

```bash
# 6. Standard → Premium : refusé
az storage account update -g "$RG_DATA" -n "$SA_DATA" --sku Premium_LRS -o none
```
Sortie attendue (libellé `[À VÉRIFIER]`) : erreur `400`, changement de SKU entre Standard et Premium non pris en charge.

Réponses attendues (étape 7) :
- a. Quatre exigences : rien de public (paramètres du compte, quelle que soit la redondance), TLS 1.2 (idem), copie lisible dans une seconde région (G + RA), niveau Archive. ZRS ne copie pas hors de France Central ; RA-GZRS couvre les deux régions mais n'accepte pas le niveau Archive. RA-GRS est la seule option qui satisfait les quatre.
- b. Les écritures des 10 dernières minutes ne sont pas encore sur le secondaire : en cas de basculement, elles sont perdues (RPO ≈ 10 min à cet instant). `Last Sync Time` sert à évaluer cette perte AVANT de décider un basculement.
- c. La performance est fixée à la création : créer un compte Premium objets blob de blocs (`--kind BlockBlobStorage --sku Premium_LRS`), copier les données de compte à compte avec AzCopy, puis repointer les applications.

### Pourquoi
- `check-name` d'abord : l'unicité est globale à Azure ; un échec de création au milieu d'un script coûte plus cher qu'un test.
- Création en LRS puis passage en RA-GRS : montre qu'un changement LRS ↔ GRS ↔ RA-GRS est une simple mise à jour, sans migration ni interruption.
- `--allow-blob-public-access false` : interdit tout conteneur anonyme sur le compte, même si un conteneur est créé plus tard avec un niveau public.
- `--min-tls-version TLS1_2` : refuse les clients obsolètes au niveau du service, sans dépendre de leur configuration.
- `--access-tier Hot` : niveau par défaut des nouveaux blobs ; les preuves de livraison sont consultées pendant 30 jours.
- `geoReplicationStats` : le seul indicateur du retard du secondaire ; état `Bootstrap` tant que la copie initiale n'est pas terminée.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `check-name` renvoie `false` pour `starveost<NN>data<SES>` | Nom pris par une autre session ou un autre tenant | Nouveau code de session fourni par la formatrice |
| `RequestDisallowedByPolicy` | Tags absents (`$TAGS` non défini : bloc de variables non recollé) | Recoller le bloc, `echo $TAGS`, relancer |
| `StorageAccountAlreadyTaken` | Compte créé par un autre stagiaire avec le même numéro | Vérifier `NN` ; prévenir la formatrice |
| `geoReplicationStats` vide | `--expand geoReplicationStats` oublié, ou compte encore en LRS | Ajouter l'option ; vérifier `sku.name` |
| État `Bootstrap` persistant | Copie initiale vers France South en cours | Attendre ; sans incidence sur la suite du lab |

### Variantes acceptables
- Création par le portail (onglets « Informations de base », « Avancé », « Mise en réseau ») : acceptable, mêmes propriétés à vérifier par `az storage account show`.
- Création directe en `Standard_RAGRS` : correcte ; l'étape 4 devient sans effet.
- PowerShell : `New-AzStorageAccount -SkuName Standard_RAGRS -Kind StorageV2 -MinimumTlsVersion TLS1_2 -AllowBlobPublicAccess $false`.

## Lab 06.2 ⭐⭐ — Protection, réplication et cycle de vie des preuves de livraison

### Solution
```bash
# 1. Protection des données du service Blob
az storage account blob-service-properties update -g "$RG_DATA" -n "$SA_DATA" \
  --enable-versioning true --enable-change-feed true \
  --enable-delete-retention true --delete-retention-days 14 \
  --enable-container-delete-retention true --container-delete-retention-days 14 \
  --query "[isVersioningEnabled, changeFeed.enabled, deleteRetentionPolicy.days, containerDeleteRetentionPolicy.days]" \
  -o tsv
```
Sortie attendue :
```
True	True	14	14
```

```bash
# 2. Données d'exemple (énoncé)
mkdir -p "$WORK/pod"
for i in $(seq -w 1 20); do
  echo "Preuve de livraison ${i} - tournée T${i} - signée" > "$WORK/pod/pod-0${i}.txt"
done

# 3. Conteneur privé et dépôt
az storage container create -n pod --public-access off \
  --account-name "$SA_DATA" --auth-mode key -o tsv
az storage blob upload-batch -d pod -s "$WORK/pod" --destination-path 2026/10 \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage blob list -c pod --prefix 2026/10/ \
  --account-name "$SA_DATA" --auth-mode key --query "length(@)" -o tsv
```
Sortie attendue :
```
True
20
```

```bash
# 4. Écrasement et versions
echo "Preuve de livraison 01 - CORRIGÉE" > "$WORK/pod-001-v2.txt"
az storage blob upload -c pod -n 2026/10/pod-001.txt -f "$WORK/pod-001-v2.txt" --overwrite \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage blob list -c pod --prefix 2026/10/pod-001.txt --include v \
  --account-name "$SA_DATA" --auth-mode key \
  --query "[].{Version:versionId, Courante:isCurrentVersion}" -o table
```
Sortie attendue :
```
Version                       Courante
----------------------------  ----------
2026-10-08T07:41:12.3856172Z
2026-10-08T07:44:03.1029840Z  True
```

```bash
# 5. Suppression réversible d'un conteneur
az storage container create -n tmp --account-name "$SA_DATA" --auth-mode key -o none
az storage container delete -n tmp --account-name "$SA_DATA" --auth-mode key -o none
DELV=$(az storage container list --include-deleted --account-name "$SA_DATA" --auth-mode key \
  --query "[?name=='tmp' && deleted].version | [0]" -o tsv)
echo "$DELV"
sleep 30
az storage container restore -n tmp --deleted-version "$DELV" \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage container list --account-name "$SA_DATA" --auth-mode key --query "[].name" -o tsv
```
Sortie attendue :
```
01DB3F7A2C9E4D10
pod
tmp
```

```bash
# 6. Compte d'archive, destination de la réplication
az storage account create -g "$RG_DATA" -n "$SA_ARCH" -l "$LOC" \
  --kind StorageV2 --sku Standard_LRS --access-tier Cool \
  --min-tls-version TLS1_2 --allow-blob-public-access false --tags $TAGS -o none
az storage account blob-service-properties update -g "$RG_DATA" -n "$SA_ARCH" \
  --enable-versioning true -o none
az storage container create -n pod-replica --account-name "$SA_ARCH" --auth-mode key -o none

# 7. Réplication d'objets : destination d'abord, puis source
POLICY_ID=$(az storage account or-policy create -g "$RG_DATA" --account-name "$SA_ARCH" \
  --source-account "$SA_DATA" --destination-account "$SA_ARCH" \
  --source-container pod --destination-container pod-replica \
  --min-creation-time '2026-01-01T00:00:00Z' --query policyId -o tsv)
az storage account or-policy show -g "$RG_DATA" --account-name "$SA_ARCH" --policy-id "$POLICY_ID" \
  | az storage account or-policy create -g "$RG_DATA" --account-name "$SA_DATA" --policy "@-" \
    --query "[policyId, rules[0].ruleId]" -o tsv
sleep 180
az storage blob list -c pod-replica --account-name "$SA_ARCH" --auth-mode key \
  --query "length(@)" -o tsv
```
Sortie attendue :
```
1f3c6a2e-0b7d-4c55-9e1a-6d2f8b0c4e91	7a90e3c4-52d1-4c6b-8f0e-3b2a1d9c5e77
20
```
Contrôle facultatif, état de réplication d'un blob source (nom de propriété `[À VÉRIFIER]` selon la version d'Azure CLI) :
```bash
az storage blob show -c pod -n 2026/10/pod-010.txt --account-name "$SA_DATA" --auth-mode key \
  --query "objectReplicationSourceProperties[0].rules[0].status" -o tsv
```
Sortie attendue : `complete`.

Fichier `lifecycle-pod.json` (identique à `scripts/catch-up/module-06/lifecycle-pod.json`) :
```json
{
  "rules": [
    {
      "enabled": true,
      "name": "pod-cycle-de-vie",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": [ "blockBlob" ],
          "prefixMatch": [ "pod/" ]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": { "daysAfterModificationGreaterThan": 30 },
            "tierToCold": { "daysAfterModificationGreaterThan": 90 },
            "tierToArchive": { "daysAfterModificationGreaterThan": 180 },
            "delete": { "daysAfterModificationGreaterThan": 3650 }
          },
          "version": {
            "delete": { "daysAfterCreationGreaterThan": 90 }
          }
        }
      }
    }
  ]
}
```

```bash
# 8. Application de la règle de cycle de vie
cp scripts/catch-up/module-06/lifecycle-pod.json "$WORK/"   # ou fichier écrit par le stagiaire
az storage account management-policy create -g "$RG_DATA" --account-name "$SA_DATA" \
  --policy @"$WORK/lifecycle-pod.json" -o none
az storage account management-policy show -g "$RG_DATA" --account-name "$SA_DATA" \
  --query "policy.rules[0].definition.actions.baseBlob" -o json
```
Sortie attendue (propriétés nulles omises) :
```
{
  "delete": { "daysAfterModificationGreaterThan": 3650.0 },
  "tierToArchive": { "daysAfterModificationGreaterThan": 180.0 },
  "tierToCold": { "daysAfterModificationGreaterThan": 90.0 },
  "tierToCool": { "daysAfterModificationGreaterThan": 30.0 }
}
```

```bash
# 9. Archive, lecture refusée, réhydratation
az storage blob set-tier -c pod -n 2026/10/pod-003.txt --tier Archive \
  --account-name "$SA_DATA" --auth-mode key
az storage blob download -c pod -n 2026/10/pod-003.txt -f "$WORK/pod-003.txt" \
  --account-name "$SA_DATA" --auth-mode key -o none
az storage blob set-tier -c pod -n 2026/10/pod-003.txt --tier Hot --rehydrate-priority Standard \
  --account-name "$SA_DATA" --auth-mode key
az storage blob show -c pod -n 2026/10/pod-003.txt --account-name "$SA_DATA" --auth-mode key \
  --query "properties.{Niveau:blobTier, Archive:rehydrationStatus}" -o table
```
Sortie attendue :
```
ERROR: This operation is not permitted on an archived blob.
ErrorCode:BlobArchived
Niveau    Archive
--------  ------------------------
Archive   rehydrate-pending-to-hot
```

Réponses attendues (étape 10) :
- a. Tous les blobs ont été modifiés aujourd'hui (seuil de 30 jours non atteint) ; de plus, la plateforme exécute les règles une fois par jour, avec un premier passage sous 24 à 48 h après la création de la règle.
- b. Une copie sous contrôle d'Arvéo : compte distinct (suppression du compte source sans effet sur la copie, droits d'accès séparés), choix du conteneur, niveau Cool à moindre coût, copie toujours lisible et déplaçable dans une autre région ou un autre abonnement. Le secondaire RA-GRS, lui, est géré par Microsoft, en lecture seule, et disparaît avec le compte.
- c. Avec le versioning, chaque écrasement crée une version antérieure facturée ; les actions de `baseBlob` ne s'appliquent qu'à la version courante. Sans action `version`, les versions s'accumuleraient indéfiniment.

### Pourquoi
- Versioning + suppression réversible des blobs + suppression réversible des conteneurs : trois risques différents (écrasement, suppression d'un blob, suppression d'un conteneur) ; 14 jours = délai de réaction demandé par la direction juridique.
- Flux de modifications : prérequis de la réplication d'objets sur la source ; il sert aussi à l'audit (journal des créations, modifications, suppressions).
- Réplication d'objets créée avant l'archivage de `pod-003` : la copie initiale porte sur les 20 blobs ; un changement de niveau dans la source n'est pas répliqué.
- `--min-creation-time` au 1er janvier 2026 : les blobs déposés avant la règle sont aussi copiés ; sans cette option, seuls les nouveaux blobs le seraient.
- Règle créée sur la destination puis recopiée sur la source : c'est la destination qui génère `policyId` et `ruleId` ; la source doit porter exactement les mêmes identifiants.
- Compte d'archive en Cool par défaut : copie de conformité rarement lue.
- Cycle de vie fondé sur la date de modification : le suivi du dernier accès n'est pas activé (coût d'opérations supplémentaire, sans besoin métier).
- Réhydratation en priorité standard : aucune urgence ; la priorité haute est facturée davantage.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `There are no credentials provided in your command and environment` (avertissement) | `--auth-mode` omis : la CLI lit la clé elle-même | Sans effet ; préciser `--auth-mode key` dans ce lab |
| `container restore` : `ContainerBeingDeleted` | Restauration lancée pendant la suppression | Attendre 30 s, relancer |
| `container restore` : `--deleted-version` vide | Requête JMESPath sans `deleted`, ou conteneur jamais supprimé | `az storage container list --include-deleted -o table` |
| `or-policy create` : versioning ou flux de modifications requis | Étape 1 incomplète, ou versioning non activé sur la destination | Activer `--enable-versioning` (2 comptes) et `--enable-change-feed` (source) |
| `or-policy create` (source) : `InvalidRequestPropertyValue` | Règle source créée sans recopier `policyId` et `ruleId` de la destination | Utiliser `or-policy show ... | or-policy create --policy "@-"` |
| `pod-replica` vide après 5 min | Règle absente de la source, ou `--min-creation-time` postérieur aux blobs | `az storage account or-policy list --account-name $SA_DATA` ; recréer la règle |
| `management-policy create` : JSON invalide | Virgule finale, guillemets typographiques, préfixe sans le nom du conteneur | `python3 -m json.tool lifecycle-pod.json` ; `prefixMatch` commence par `pod/` |
| `set-tier --tier Archive` refusé | Compte en ZRS, GZRS ou RA-GZRS | Lab 06.1 : compte en RA-GRS |
| `rehydrationStatus` vide | Nom de propriété différent selon la version de la CLI | Afficher `-o json` et chercher `archiveStatus` |

### Variantes acceptables
- Portail : « Protection des données » du compte, « Gestion du cycle de vie » (assistant graphique, onglet « Mode Code » pour le JSON), « Réplication d'objets » (règle créée en une fois sur les deux comptes).
- Bicep : `blobServices` (versioning, flux, rétentions) et `managementPolicies` alimenté par `loadJsonContent('lifecycle-pod.json')` ; c'est l'approche de `scripts/catch-up/module-06/main.bicep`.
- Stratégie d'immutabilité temporelle (WORM, 10 ans) sur `pod` au lieu de la suppression réversible seule : protection plus forte (conformité, rançongiciel), mais irréversible une fois verrouillée ; à valider par la direction juridique.
- Condition `daysAfterLastAccessTimeGreaterThan` avec suivi du dernier accès : pertinente si les consultations tardives sont fréquentes (ajouter `enableAutoTierToHotFromCool`).

## Exercice 06.3 ⭐⭐ — Accès délégué : SAS, Entra ID et fin des clés

### Solution
```bash
# 1. Rôle de données pour soi-même (10:25)
SA_ID=$(az storage account show -g "$RG_DATA" -n "$SA_DATA" --query id -o tsv)
ME=$(az account show --query user.name -o tsv)
az role assignment create --assignee "$ME" --role "Storage Blob Data Contributor" \
  --scope "$SA_ID" --query roleDefinitionName -o tsv
```
Sortie attendue :
```
Storage Blob Data Contributor
```

```bash
# 2. SAS de compte signé par key1
END=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')
BLOB="https://${SA_DATA}.blob.core.windows.net"
KEY1=$(az storage account keys list -g "$RG_DATA" -n "$SA_DATA" \
  --query "[?keyName=='key1'].value" -o tsv)
SAS_ACC=$(az storage account generate-sas --account-name "$SA_DATA" --account-key "$KEY1" \
  --services b --resource-types sco --permissions rl --expiry "$END" --https-only -o tsv)
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/?comp=list&${SAS_ACC}"

# 3. Stratégie d'accès stockée et SAS de service
az storage container policy create --account-name "$SA_DATA" --account-key "$KEY1" \
  -c pod -n sap-transporteurs --permissions rl --expiry "$END" -o none
SAS_SVC=$(az storage container generate-sas --account-name "$SA_DATA" --account-key "$KEY1" \
  -n pod --policy-name sap-transporteurs -o tsv)
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/pod?restype=container&comp=list&${SAS_SVC}"

# 4. Révocation par suppression de la stratégie
az storage container policy delete --account-name "$SA_DATA" --account-key "$KEY1" \
  -c pod -n sap-transporteurs -o none
sleep 30
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/pod?restype=container&comp=list&${SAS_SVC}"

# 5. Régénération de key1
az storage account keys renew -g "$RG_DATA" -n "$SA_DATA" --key key1 -o none
curl -s -o /dev/null -w "%{http_code}\n" "${BLOB}/?comp=list&${SAS_ACC}"
```
Sortie attendue :
```
200
200
403
403
```

```bash
# 6. SAS de délégation d'utilisateur (variable conservée pour le défi 06.4)
UD_URL=$(az storage blob generate-sas --account-name "$SA_DATA" -c pod -n 2026/10/pod-001.txt \
  --permissions r --expiry "$END" --https-only --auth-mode login --as-user --full-uri -o tsv)
curl -s "$UD_URL"

# 7. Fin des clés
az storage account update -g "$RG_DATA" -n "$SA_DATA" --allow-shared-key-access false \
  --query allowSharedKeyAccess -o tsv
az storage blob list -c pod --account-name "$SA_DATA" --auth-mode key --query "length(@)" -o tsv
az storage blob list -c pod --account-name "$SA_DATA" --auth-mode login --query "length(@)" -o tsv
curl -s -o /dev/null -w "%{http_code}\n" "$UD_URL"
```
Sortie attendue :
```
Preuve de livraison 01 - CORRIGÉE
false
ERROR: Key based authentication is not permitted on this storage account.
ErrorCode:KeyBasedAuthenticationNotPermitted
20
200
```

Réponses attendues (étape 8) :
- a. Le SAS de service ne porte que le nom de la stratégie stockée ; permissions et expiration sont lues dans le conteneur à chaque requête. Stratégie supprimée = SAS invalide (sous 30 s), clé intacte, autres accès intacts. La régénération de `key1` (étape 5) a invalidé TOUS les SAS signés avec elle : le SAS de compte, mais aussi le SAS de service de l'étape 3, et toute application utilisant `key1`.
- b. Le SAS de délégation d'utilisateur : il est signé par une clé de délégation obtenue avec l'identité Entra ID du stagiaire, pas par une clé du compte ; il n'est concerné ni par `allowSharedKeyAccess` ni par la rotation des clés. Il reste limité par les droits RBAC de son émetteur au moment de son usage, et par son expiration.
- c. `Owner` est un rôle du plan de contrôle : il n'inclut aucune `dataAction`. L'accès aux blobs par Entra ID (`--auth-mode login`, clé de délégation) exige un rôle de données comme « Storage Blob Data Contributor ». Sans lui, seul un accès indirect par lecture des clés était possible, et il vient d'être fermé.

### Pourquoi
- Rôle attribué en premier : propagation jusqu'à 10 min, absorbée par la pause.
- Clé lue dans une variable, jamais affichée : elle ne doit apparaître ni à l'écran projeté ni dans un fichier.
- Tests par `curl` et code HTTP : preuve indépendante de la CLI, telle que la verrait un transporteur.
- SAS courts (2 h) et `--https-only` : surface d'exposition minimale si une URL fuit (journal de proxy, courriel).
- Stratégie stockée pour les transporteurs : révocation ciblée d'un groupe de SAS sans rotation de clé (5 stratégies maximum par conteneur).
- Délégation d'utilisateur pour l'application : aucune clé à stocker, émetteur identifié dans les journaux, durée maximale de 7 jours.
- Désactivation de la clé partagée en dernier : vérifiée sans risque, l'accès Entra ID étant déjà en place (étape 1).

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Étape 2 ou 3 : `403` au lieu de `200` | `&` manquant entre l'URL et le SAS, ou guillemets absents autour de l'URL | Recopier la commande ; l'URL doit être entre guillemets doubles |
| Étape 3 : `403`, `AuthenticationFailed` | Stratégie stockée pas encore active (jusqu'à 30 s) | Attendre 30 s, relancer |
| Étape 4 : encore `200` | Test lancé moins de 30 s après la suppression | Attendre, relancer |
| Étape 6 : `AuthorizationPermissionMismatch` | Rôle de données pas encore propagé | Attendre jusqu'à 10 min ; vérifier `az role assignment list --scope $SA_ID -o table` |
| Étape 6 : `--as-user` refusé | `--auth-mode login` absent | Les deux options vont ensemble |
| `date: invalid date` | Commande exécutée hors de Cloud Shell (macOS, `date` BSD) | Cloud Shell, ou `date -u -v+2H '+%Y-%m-%dT%H:%MZ'` sur macOS |
| Portail : conteneurs illisibles après l'étape 7 | Portail configuré pour la clé d'accès | Compte › Configuration › « Utiliser Microsoft Entra par défaut » ; ou bascule « Méthode d'authentification » dans le conteneur |

### Variantes acceptables
- Rôle attribué au niveau du conteneur `pod` (`--scope "$SA_ID/blobServices/default/containers/pod"`) : plus restrictif, correct.
- Rôle « Storage Blob Data Reader » + « Storage Blob Delegator » pour une application qui ne fait que lire et émettre des SAS : moindre privilège, recommandé pour l'application de facturation.
- Révocation par stratégie stockée à expiration modifiée (date passée) plutôt que supprimée : équivalent, garde l'historique.

## Défi 06.4 ⭐⭐⭐ — Compte de données invisible d'Internet

### Solution
Fichier `storage-private.bicep` (identique à `scripts/catch-up/module-06/storage-private.bicep`) :
```bicep
// storage-private.bicep — compte de données Arvéo joignable uniquement depuis le réseau Arvéo
// Solution du défi 06.4. Déployé dans rg-stNN-data.
//   - compte starveostNNdata<SES> redéclaré À L'IDENTIQUE de l'état des labs 06.1 à 06.3
//     (une déclaration de compte est un remplacement complet de ses propriétés), avec
//     publicNetworkAccess à Disabled
//   - private endpoint pe-stNN-blob (sous-ressource blob) dans snet-pe du spoke données
//   - zone privatelink.blob.core.windows.net dans rg-stNN-hub (module private-dns.bicep)
//     et groupe de zones DNS : enregistrement A créé et maintenu par la plateforme
// Déploiement :
//   az deployment group create -g rg-stNN-data -f storage-private.bicep -p numero=NN session=<SES>
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

@description('Code de session (4 caractères, minuscules et chiffres), fourni par la formatrice')
@minLength(4)
@maxLength(4)
param session string

@description('Région du compte et du private endpoint')
param location string = 'francecentral'

@description('Accès public au compte : Disabled (cible du défi) ; Enabled réservé au rattrapage')
@allowed([ 'Enabled', 'Disabled' ])
param publicNetworkAccess string = 'Disabled'

var prefix = 'st${numero}'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var peSubnetId = resourceId('rg-${prefix}-spoke', 'Microsoft.Network/virtualNetworks/subnets',
  'vnet-${prefix}-spoke-data', 'snet-pe')

// ---------- Compte de données (état des labs 06.1 à 06.3) ----------
resource dataAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'starveost${numero}data${session}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_RAGRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: publicNetworkAccess == 'Disabled' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ---------- DNS privé (hub) ----------
module dns 'private-dns.bicep' = {
  name: 'private-dns-blob'
  scope: resourceGroup('rg-${prefix}-hub')
  params: {
    numero: numero
  }
}

// ---------- Private endpoint ----------
resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${prefix}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    customNetworkInterfaceName: 'nic-${prefix}-pe-blob'
    privateLinkServiceConnections: [
      {
        name: 'plsc-${prefix}-blob'
        properties: {
          privateLinkServiceId: dataAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: dns.outputs.zoneId
        }
      }
    ]
  }
}

// IP lue sur la carte réseau créée par la plateforme, nommée par customNetworkInterfaceName
// (customDnsConfigs peut être vide quand un groupe de zones DNS est associé)
resource peNic 'Microsoft.Network/networkInterfaces@2023-11-01' existing = {
  name: 'nic-${prefix}-pe-blob'
}

output privateEndpointIp string = peNic.properties.ipConfigurations[0].properties.privateIPAddress
output blobEndpoint string = dataAccount.properties.primaryEndpoints.blob
output accountName string = dataAccount.name
```

Module `private-dns.bicep` (même dossier) :
```bicep
// private-dns.bicep — zone DNS privée des private endpoints Blob, déployée dans rg-stNN-hub
// Module de storage-private.bicep (défi 06.4) et de main.bicep (rattrapage M6).
// Zone privatelink.blob.core.windows.net liée au hub et aux deux spokes (sans enregistrement
// automatique : une seule zone d'enregistrement par VNet, déjà arveo.internal au M4).
targetScope = 'resourceGroup'

@description('Numéro du stagiaire sur deux chiffres')
@minLength(2)
@maxLength(2)
param numero string

var prefix = 'st${numero}'
var spokeRg = 'rg-${prefix}-spoke'
var tags = {
  Projet: 'Arveo'
  Environnement: 'Formation'
  Proprietaire: prefix
}
var vnets = [
  {
    link: 'link-hub'
    id: resourceId('Microsoft.Network/virtualNetworks', 'vnet-${prefix}-hub')
  }
  {
    link: 'link-spoke-app'
    id: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-app')
  }
  {
    link: 'link-spoke-data'
    id: resourceId(spokeRg, 'Microsoft.Network/virtualNetworks', 'vnet-${prefix}-spoke-data')
  }
]

resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for v in vnets: {
  parent: blobZone
  name: v.link
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: v.id
    }
    registrationEnabled: false
  }
}]

output zoneId string = blobZone.id
```

Contrôle, SAS avant déploiement, prévisualisation, déploiement :
```bash
cd ~/formation/scripts/catch-up/module-06      # ou dossier du fichier écrit par le stagiaire
az bicep build --file storage-private.bicep --stdout > /dev/null && echo "Syntaxe OK"
curl -s -o /dev/null -w "%{http_code}\n" "$UD_URL"
az deployment group what-if -g "$RG_DATA" -f storage-private.bicep -p numero="$NN" session="$SES"
az deployment group create -g "$RG_DATA" -n storage-private -f storage-private.bicep \
  -p numero="$NN" session="$SES" --query "properties.outputs.privateEndpointIp.value" -o tsv
cd ~/formation
```
Sortie attendue du `what-if` (fin, détail des propriétés partiellement omis ; `+` ou `~` sur `publicNetworkAccess` selon que la propriété était renseignée) :
```
Scope: /subscriptions/<ID>/resourceGroups/rg-st07-data
  ~ Microsoft.Storage/storageAccounts/starveost07data2610 [2023-05-01]
    + properties.publicNetworkAccess:      "Disabled"
    ~ properties.networkAcls.defaultAction: "Allow" => "Deny"
  + Microsoft.Network/privateEndpoints/pe-st07-blob [2023-11-01]
  + Microsoft.Network/privateEndpoints/pe-st07-blob/privateDnsZoneGroups/default [2023-11-01]
Scope: /subscriptions/<ID>/resourceGroups/rg-st07-hub
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net [2020-06-01]
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-hub
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-spoke-app
  + Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-spoke-data

Resource changes: 6 to create, 1 to modify.
```
Puis, après 2 à 4 min : `Syntaxe OK`, `200` (avant), puis `10.7.9.4`.

Tests :
```bash
tester data "getent hosts ${SA_DATA}.blob.core.windows.net"                      # a
tester data "curl -s -o /dev/null -w '%{http_code}\n' '${UD_URL}'"                # b
curl -s -o /dev/null -w "%{http_code}\n" "$UD_URL"                                 # c
az storage blob list -c pod --account-name "$SA_DATA" --auth-mode login -o none   # d
nslookup "${SA_DATA}.blob.core.windows.net" | tail -n +3                           # e
```
Sortie attendue (30 à 60 s par test exécuté sur la VM ; noms et adresse publique variables) :
```
10.7.9.4        starveost07data2610.privatelink.blob.core.windows.net starveost07data2610.blob.core.windows.net
200
403
ERROR: This request is not authorized to perform this operation.
ErrorCode:AuthorizationFailure
Non-authoritative answer:
starveost07data2610.blob.core.windows.net	canonical name = starveost07data2610.privatelink.blob.core.windows.net.
starveost07data2610.privatelink.blob.core.windows.net	canonical name = blob.par21prdstr02a.store.core.windows.net.
Name:	blob.par21prdstr02a.store.core.windows.net
Address: <IP_PUBLIQUE>
```

Réponses attendues (étape 5) :
- a. Le réseau et l'autorisation sont deux couches indépendantes, évaluées dans cet ordre : avec `publicNetworkAccess = Disabled`, le service rejette toute requête arrivée par le point de terminaison public AVANT d'examiner le SAS. Un SAS valide prouve un droit, pas une provenance.
- b. Oui : cycle de vie et réplication d'objets sont exécutés par la plateforme de stockage elle-même, pas par un client passant par le point de terminaison public `[À VÉRIFIER]` comportement documenté de la réplication d'objets avec un compte source sans accès public. Vérification simple : un nouveau blob déposé depuis le réseau Arvéo (module 8) doit apparaître dans `pod-replica`.
- c. Trois conditions : un chemin réseau (tunnel VPN du module 5, supprimé ce soir-là, ou ExpressRoute) avec les règles de pare-feu Lyon → `snet-pe` (TCP 443) ; une résolution DNS vers `10.<OCT>.9.4` depuis Lyon : redirecteur conditionnel de la zone `blob.core.windows.net` du DNS de Lyon vers un point de terminaison entrant d'Azure DNS Private Resolver dans le hub (la zone privée n'est pas interrogeable directement depuis Lyon) ; et, si le trafic doit traverser le pare-feu, les stratégies réseau du sous-réseau `snet-pe` activées pour que les UDR s'appliquent au private endpoint.

### Pourquoi
- Compte redéclaré en entier : une ressource `storageAccounts` déclarée en Bicep remplace l'ensemble de ses propriétés ; une propriété omise (`allowSharedKeyAccess`) reviendrait à sa valeur par défaut et rouvrirait l'accès par clé. Le `what-if` sert précisément à le détecter.
- `publicNetworkAccess: 'Disabled'` plutôt que `networkAcls` seul : désactivation explicite et lisible par Azure Policy ; `defaultAction: 'Deny'` en cohérence, au cas où l'accès public serait rouvert par erreur.
- `bypass: 'AzureServices'` : sans effet quand l'accès public est désactivé ; utile si le compte repasse en « réseaux sélectionnés » (services approuvés comme Azure Backup au M9).
- Private endpoint dans `snet-pe` (spoke données) : sous-réseau dédié prévu au M4, aucun NSG ni UDR à ce stade ; IP `10.<OCT>.9.4` = première adresse utilisable (les 4 premières sont réservées par Azure).
- `customNetworkInterfaceName` : nom de carte conforme à la convention au lieu du nom généré `pe-stNN-blob.nic.<GUID>`.
- Zone dans le hub, liée aux trois VNets : modèle hub-spoke du M4 (DNS centralisé) ; la zone appartient au hub, pas au compte, et servira à tous les futurs private endpoints Blob.
- Groupe de zones DNS : l'enregistrement A suit le cycle de vie du private endpoint (créé, mis à jour, supprimé avec lui) ; aucun enregistrement manuel à maintenir.
- `environment().suffixes.storage` : nom de zone correct quel que soit le cloud Azure (public, souverain).
- `UD_URL` généré avant le déploiement : la clé de délégation se demande au service Blob, injoignable depuis Cloud Shell une fois l'accès public désactivé.
- Test e : depuis Internet, le CNAME `privatelink` existe aussi, mais la zone publique le résout vers l'IP publique ; seule la zone privée liée aux VNets Arvéo donne l'IP privée.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `what-if` : `allowSharedKeyAccess: false => true` (ou propriété supprimée) | Compte redéclaré partiellement | Recopier toutes les propriétés de l'état actuel (`az storage account show`) |
| `PrivateEndpointCannotBeCreatedInSubnetThatHasNetworkPoliciesEnabled` `[À VÉRIFIER]` libellé | Stratégies réseau activées sur `snet-pe` (API anciennes) | `az network vnet subnet update ... -n snet-pe --private-endpoint-network-policies Disabled` |
| `AuthorizationFailed` sur la zone DNS | Module déployé dans le mauvais groupe (`scope` absent) | `scope: resourceGroup('rg-${prefix}-hub')` |
| Test a : adresse publique sur la VM | Zone non liée à `vnet-stNN-spoke-data`, ou groupe de zones absent | `az network private-dns link vnet list -g rg-stNN-hub -z privatelink.blob.core.windows.net -o table` |
| Test b : `403` depuis la VM | `UD_URL` expiré (plus de 2 h) ou généré après le déploiement | Rouvrir l'accès public (`publicNetworkAccess=Enabled` au paramètre), générer un nouveau SAS, redéployer en `Disabled` |
| Test b : délai dépassé (`000`) | `vm-stNN-test-data` arrêtée | `az vm start -g rg-stNN-spoke -n vm-stNN-test-data` |
| Test a ou b : `Conflict` sur `run-command` | Autre commande en cours sur la VM | Une seule commande à la fois ; attendre 1 min |
| `RequestDisallowedByPolicy` sur la carte réseau | Carte créée par la plateforme sans tags (stratégie du M2) `[À VÉRIFIER]` | Prévenir la formatrice (exclusion du type `networkInterfaces` prévue au guide) |

### Variantes acceptables
- Private endpoint et zone en Azure CLI (`az network private-endpoint create`, `az network private-dns zone create`, `az network private-dns link vnet create`, `az network private-endpoint dns-zone-group create`) puis `az storage account update --public-network-access Disabled` : correct techniquement, hors de la contrainte « versionné et rejouable ».
- Zone DNS dans `rg-stNN-data` : fonctionne, mais disperse la résolution DNS par application ; à éviter en hub-spoke.
- Point de terminaison de service `Microsoft.Storage` sur `snet-data` + accès « réseaux sélectionnés » : gratuit, mais le compte garde une IP publique et Lyon ne pourrait jamais l'utiliser ; ne répond pas à l'exigence d'audit.
- Azure Policy « Configurer les private endpoints / désactiver l'accès public des comptes de stockage » (effet `DeployIfNotExists` ou `Modify`) : approche d'entreprise, au-delà des droits stagiaires (définitions au niveau abonnement, M2).

## Lab 06.5 ⭐⭐ — Synchroniser le serveur de fichiers de Lyon

### Solution
```bash
# 1. Fin de la préparation du serveur
./scripts/labs/module-06/lyon-fs-prep.sh "$NN" --status

# 2. Compte de fichiers et partage
az storage account create -g "$RG_DATA" -n "$SA_FILES" -l "$LOC" \
  --kind StorageV2 --sku Standard_LRS --min-tls-version TLS1_2 \
  --allow-blob-public-access false --enable-large-file-share --tags $TAGS -o none
az storage share-rm create -g "$RG_DATA" --storage-account "$SA_FILES" -n partage-lyon \
  --quota 100 --access-tier TransactionOptimized \
  --query "{Partage:name, Quota:shareQuota, Niveau:accessTier}" -o table

# 3. Service de synchronisation
az storagesync create -g "$RG_DATA" -n "$SSS" -l "$LOC" --tags $TAGS \
  --query provisioningState -o tsv
```
Sortie attendue (étapes 2 et 3) :
```
Partage       Quota    Niveau
------------  -------  --------------------
partage-lyon  100      TransactionOptimized
Succeeded
```

**4. Portail** : `sss-st07` › Groupes de synchronisation › + Groupe de synchronisation :
- Nom : `sg-partage-lyon` ;
- Point de terminaison cloud : abonnement de formation, compte `starveost07files2610`, partage `partage-lyon` ;
- Créer. Le portail attribue au principal de service « Microsoft.StorageSync » les droits nécessaires sur le compte (`[À VÉRIFIER]` rôle attribué : « Reader and Data Access », ou rôles de l'identité managée du service).

```bash
# 5. Inscription du serveur par son identité managée
LYON_PID=$(az vm show -g "$RG_LYON_ST" -n "vm-${ST}-lyon-fs" --query identity.principalId -o tsv)
SSS_ID=$(az storagesync show -g "$RG_DATA" -n "$SSS" --query id -o tsv)
az role assignment create --assignee-object-id "$LYON_PID" \
  --assignee-principal-type ServicePrincipal --role Contributor --scope "$SSS_ID" \
  --query roleDefinitionName -o tsv
SUB=$(az account show --query id -o tsv)
sleep 60
lyon "Connect-AzAccount -Identity -Subscription '$SUB' | Out-Null; Register-AzStorageSyncServer -ResourceGroupName '$RG_DATA' -StorageSyncServiceName '$SSS' | Select-Object FriendlyName, ServerId, AgentVersion | Format-List"
az rest --method get \
  --url "https://management.azure.com${SSS_ID}/registeredServers?api-version=2022-06-01" \
  --query "value[].{Serveur:properties.friendlyName, Agent:properties.agentVersion}" -o table
```
Sortie attendue :
```
Contributor

FriendlyName : vm-st07-lyon-fs
ServerId     : 6b0c9d2e-4f1a-4e7b-9a3c-2d5e8f1b7c40
AgentVersion : 20.0.0.0

Serveur          Agent
---------------  --------
vm-st07-lyon-fs  20.0.0.0
```

**6. Portail** : `sg-partage-lyon` › + Ajouter un point de terminaison de serveur :
- Serveur inscrit : `vm-st07-lyon-fs` ;
- Chemin : `F:\Partages\Commun` ;
- Hiérarchisation cloud : activée, espace libre du volume `20` %, stratégie de date désactivée ;
- Mode de téléchargement initial et de chargement initial : valeurs par défaut ;
- Créer. État « Provisionnement », puis synchronisation initiale (fichiers du serveur chargés vers le partage).

```bash
# 7. Contenu du partage après la synchronisation initiale (3 à 5 min)
az storage file list --share-name partage-lyon --account-name "$SA_FILES" \
  --query "[].name" -o tsv
az storage file list --share-name partage-lyon --account-name "$SA_FILES" --path Exploitation \
  --query "length(@)" -o tsv

# 8. Serveur → Azure
lyon "Set-Content F:\Partages\Commun\RH\note-migration.txt 'Migration Azure J3'; 'Fichier cree'"
sleep 90
az storage file exists --share-name partage-lyon --account-name "$SA_FILES" \
  -p RH/note-migration.txt --query exists -o tsv
```
Sortie attendue (avertissement de lecture de clé possible) :
```
Exploitation
Qualite
RH
12
Fichier cree
true
```

```bash
# 9. Azure → serveur : détection forcée
echo "Consigne qualité : contrôle des signatures" > "$WORK/consigne-qualite.txt"
az storage file upload --share-name partage-lyon --account-name "$SA_FILES" \
  --source "$WORK/consigne-qualite.txt" --path Qualite/consigne-qualite.txt -o none
lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"
lyon "Connect-AzAccount -Identity -Subscription '$SUB' | Out-Null; \$ce = Get-AzStorageSyncCloudEndpoint -ResourceGroupName '$RG_DATA' -StorageSyncServiceName '$SSS' -SyncGroupName sg-partage-lyon; Invoke-AzStorageSyncChangeDetection -InputObject \$ce -DirectoryPath 'Qualite' -Recursive; 'Detection lancee'"
sleep 120
lyon "Test-Path F:\Partages\Commun\Qualite\consigne-qualite.txt"
```
Sortie attendue :
```
False
Detection lancee
True
```
Paramètres de `Invoke-AzStorageSyncChangeDetection` `[À VÉRIFIER]` sur la version du module installée (`Get-Help Invoke-AzStorageSyncChangeDetection`).

Réponses attendues (étape 10) :
- a. L'agent ouvre lui-même des connexions sortantes HTTPS (443) vers le service de synchronisation et le compte de stockage, par la passerelle NAT du site ; Azure ne contacte jamais le serveur. Aucun flux SMB (445) ne traverse Internet : le partage n'est jamais monté à distance.
- b. La hiérarchisation cloud n'est pas prise en charge sur le volume système ; un volume de données dédié permet aussi de dimensionner le cache (20 % libres) sans risque pour le système.
- c. Au prochain passage de la tâche de détection des changements du partage, jusqu'à 24 h plus tard : les modifications faites directement dans Azure Files (portail, SMB, REST, AzCopy) ne génèrent pas de notification vers le service de synchronisation, contrairement au journal USN du serveur.

### Pourquoi
- Compte de fichiers séparé du compte de données : besoins opposés (clé partagée et accès public nécessaires à File Sync dans sa configuration par défaut, contre un compte Blob sans clé et privé).
- `--enable-large-file-share` : partages jusqu'à 100 Tio ; activation irréversible, sans surcoût.
- `share-rm` (plan de contrôle) plutôt que `share` (plan de données) : quota et niveau gérés par ARM, aucune clé nécessaire.
- Niveau optimisé pour les transactions : la synchronisation initiale génère beaucoup d'opérations ; passage en Cool envisageable une fois le partage stabilisé.
- Groupe de synchronisation créé par le portail : le portail crée le point de terminaison cloud et attribue les droits du service de synchronisation sur le compte en une seule opération.
- Inscription par identité managée : aucun mot de passe ni jeton manipulé sur le serveur ; le rôle Contributeur est limité au seul service de synchronisation (pas au groupe de ressources).
- Point de terminaison serveur sur `F:` avec 20 % d'espace libre : le volume de 32 Go conserve au moins 6,4 Go libres ; avec 120 Mo de données, aucun fichier n'est hiérarchisé tant que le volume ne se remplit pas (bonus 1 pour forcer).
- Détection forcée limitée au dossier `Qualite` : coût et durée proportionnels au nombre d'éléments analysés.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `--status` : `Failed`, sortie `Unable to connect to the remote server` | Pas d'accès Internet sortant depuis le site de Lyon | Formatrice : `lyon-nat.sh create` ; puis relancer `lyon-fs-prep.sh <NN>` |
| `--status` : `Running` après 20 min | Téléchargement ou installation de modules lent | Attendre ; au-delà de 30 min, prévenir la formatrice |
| `--status` : `Aucun disque RAW` | Disque non attaché (stratégie, quota) | `az vm show ... --query storageProfile.dataDisks` ; relancer le script |
| `az storagesync` : extension à installer | Première utilisation | Répondre `Y` ; ou `az extension add -n storagesync` |
| `MissingSubscriptionRegistration` pour `Microsoft.StorageSync` | Fournisseur non inscrit (droit de l'abonnement) | Formatrice : `az provider register -n Microsoft.StorageSync` |
| Portail : création du point de terminaison cloud refusée (droits) | Attribution de rôle impossible pour le portail | Vérifier le rôle Owner sur `rg-stNN-data` ; à défaut, formatrice |
| `Connect-AzAccount -Identity` : `ManagedIdentityCredential authentication unavailable` | Identité managée absente | `az vm identity assign -g rg-stNN-lyon -n vm-stNN-lyon-fs` |
| Inscription : `AuthorizationFailed` | Rôle de l'identité pas encore propagé | Attendre 2 à 5 min, relancer |
| Inscription : `Register-AzStorageSyncServer` non reconnu | Modules Az non installés (préparation incomplète) | `lyon-fs-prep.sh <NN> --status` ; relancer le script |
| Inscription : serveur déjà inscrit | Serveur rattaché à un autre service (essai précédent) | Portail : désinscrire le serveur, ou `Reset-StorageSyncServer` sur le serveur `[À VÉRIFIER]` |
| Point de terminaison serveur : chemin refusé | Volume système (`C:`) ou chemin inexistant | `F:\Partages\Commun` exactement |
| Partage vide après 10 min | Serveur arrêté ou point de terminaison en erreur | État d'intégrité du point de terminaison serveur dans le portail ; `az vm start` |

### Variantes acceptables
- Groupe et points de terminaison en CLI : `az storagesync sync-group create`, `az storagesync sync-group cloud-endpoint create --storage-account <COMPTE> --azure-file-share-name partage-lyon`, `az storagesync sync-group server-endpoint create --registered-server-id <ID> --server-local-path F:\\Partages\\Commun --cloud-tiering on --volume-free-space-percent 20` `[À VÉRIFIER]` noms des options ; les droits du service sur le compte sont alors à attribuer explicitement.
- Inscription par jeton de l'utilisateur, si l'inscription par identité managée échoue sur la version du module installée (le jeton reste valable environ 1 h ; il apparaît dans l'historique des commandes d'exécution de la VM) :
  ```bash
  TOKEN=$(az account get-access-token --query accessToken -o tsv)
  lyon "\$p = (Get-Command Connect-AzAccount).Parameters['AccessToken'].ParameterType; \$t = if (\$p -eq [securestring]) { ConvertTo-SecureString '$TOKEN' -AsPlainText -Force } else { '$TOKEN' }; Connect-AzAccount -AccessToken \$t -AccountId '$(az account show --query user.name -o tsv)' -Subscription '$SUB' | Out-Null; Register-AzStorageSyncServer -ResourceGroupName '$RG_DATA' -StorageSyncServiceName '$SSS' | Select-Object FriendlyName, ServerId"
  ```
- Bicep : `Microsoft.StorageSync/storageSyncServices` et ses ressources enfants (`syncGroups`, `cloudEndpoints`, `serverEndpoints`), le point de terminaison serveur exigeant l'ID du serveur inscrit ; c'est l'approche de `scripts/catch-up/module-06/main.bicep`, déployé en deux passes.
- Rôle plus restreint que Contributeur pour l'identité du serveur : « Azure File Sync Administrator » `[À VÉRIFIER]` disponibilité et périmètre du rôle intégré.

## Lab 06.6 ⭐ — Exporter et synchroniser avec AzCopy

### Solution
```bash
# 1. Version
azcopy --version

# 2. SAS du partage et du compte d'archive
END=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ')
KEY_F=$(az storage account keys list -g "$RG_DATA" -n "$SA_FILES" --query "[0].value" -o tsv)
KEY_A=$(az storage account keys list -g "$RG_DATA" -n "$SA_ARCH" --query "[0].value" -o tsv)
SAS_F=$(az storage share generate-sas -n partage-lyon --account-name "$SA_FILES" \
  --account-key "$KEY_F" --permissions rl --expiry "$END" --https-only -o tsv)
SAS_B=$(az storage account generate-sas --account-name "$SA_ARCH" --account-key "$KEY_A" \
  --services b --resource-types sco --permissions racwl --expiry "$END" --https-only -o tsv)

# 3. et 4. Copie du partage, de compte à compte, puis contrôle
azcopy copy "https://${SA_FILES}.file.core.windows.net/partage-lyon?${SAS_F}" \
  "https://${SA_ARCH}.blob.core.windows.net/?${SAS_B}" --recursive
azcopy list "https://${SA_ARCH}.blob.core.windows.net/partage-lyon?${SAS_B}" | wc -l

# 5. Synchronisation différentielle
azcopy make "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}"
azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
  | grep -E "Number of Copy Transfers Completed|Final Job Status"
echo "Preuve de livraison 07 - RÉSERVE CLIENT" > "$WORK/pod/pod-007.txt"
azcopy sync "$WORK/pod" "https://${SA_ARCH}.blob.core.windows.net/pod-sync?${SAS_B}" \
  | grep -E "Number of Copy Transfers Completed|Final Job Status"
```
Sortie attendue (fin de chaque commande, version et compteurs variables) :
```
azcopy version 10.30.1
Number of File Transfers: 21
Number of File Transfers Completed: 21
Final Job Status: Completed
21
Successfully created the resource.
Number of Copy Transfers Completed: 20
Final Job Status: Completed
Number of Copy Transfers Completed: 1
Final Job Status: Completed
```

```bash
# 6. Contrôle du changement de niveau fait dans le navigateur de stockage
az storage blob show --account-name "$SA_ARCH" -c partage-lyon -n Qualite/audit-2024.bin \
  --auth-mode key --query properties.blobTier -o tsv
```
Sortie attendue :
```
Cold
```

Observation attendue (étape 6, compte de données) : le navigateur de stockage affiche un message d'accès refusé indiquant que les paramètres réseau du compte bloquent l'accès depuis le poste. Le portail est un client comme un autre : depuis Internet, il passe par le point de terminaison public, désactivé au défi 06.4. La configuration du compte (plan de contrôle, ARM) reste accessible ; ses données (plan de données) ne le sont plus.

Calcul attendu (étape 7) :
- Lien saturé : `40 × 10¹² × 8 / 10⁸ = 3,2 × 10⁶ s ≈ 889 h ≈ 37 jours`.
- À 70 % d'efficacité : `37 / 0,7 ≈ 53 jours`.
- Conclusion : impossible en 3 semaines par le réseau, et le lien serait saturé pour toute l'activité du site. Data Box : commande, copie locale sur le réseau du datacenter, retour et chargement en quelques jours à deux semaines `[À VÉRIFIER]` délais et capacité utile (un seul appareil si sa capacité utile dépasse 40 To). File Sync ou AzCopy `sync` ensuite pour le différentiel.

### Pourquoi
- SAS plutôt qu'Entra ID pour AzCopy dans Cloud Shell : copie de compte à compte avec un partage Azure Files source, dont l'accès Entra ID au plan de données exige une configuration spécifique `[À VÉRIFIER]` prise en charge d'AzCopy pour Azure Files avec Entra ID.
- Destination à la racine du compte : AzCopy crée un conteneur du nom du partage, `partage-lyon` ; une copie vers un conteneur existant y créerait un dossier virtuel `partage-lyon/`.
- Copie côté serveur : les octets transitent entre comptes dans Azure, pas par Cloud Shell ; un fichier de 100 Mio est copié en quelques secondes.
- `azcopy sync` : compare dates de modification et tailles, ne transfère que les différences ; `make` crée le conteneur, `sync` ne le crée pas.
- Compte d'archive avec clé partagée active : compte de transit et de conformité, accès par SAS de courte durée ; le compte de données sensibles, lui, n'accepte plus de clé.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `azcopy: command not found` | Hors de Cloud Shell | Installer AzCopy v10 (binaire unique) ou utiliser Cloud Shell |
| `403 This request is not authorized to perform this operation using this permission` | Permission manquante dans le SAS (`c` pour créer le conteneur, `l` pour lister) | Régénérer `SAS_B` avec `racwl` et `--resource-types sco` |
| `AuthenticationFailed`, `Signature not valid in the specified time frame` | SAS expiré (plus de 2 h) | Regénérer `END` et les SAS |
| Copie dans un dossier `partage-lyon/partage-lyon/` | Destination = conteneur existant au lieu de la racine du compte | Supprimer le conteneur, relancer vers la racine |
| `azcopy sync` : conteneur introuvable | `azcopy make` oublié | Créer le conteneur, relancer |
| Seconde synchronisation : `0` transfert | Fichier modifié hors de `$WORK/pod`, ou même contenu | Vérifier le chemin, modifier le contenu |
| Navigateur de stockage : aucun message pour le compte de données | Défi 06.4 non déployé (accès public encore actif) | Normal ; message attendu après le défi ou le rattrapage |

### Variantes acceptables
- `azcopy login` (Entra ID) pour le compte d'archive, avec le rôle « Storage Blob Data Contributor » : recommandé en production ; nécessite le rôle sur `starveost<NN>arch<SES>`.
- Variable `AZCOPY_AUTO_LOGIN_TYPE=AZCLI` pour réutiliser la session Azure CLI de Cloud Shell `[À VÉRIFIER]` version minimale d'AzCopy.
- Azure Storage Explorer sur le poste : même copie par glisser-déposer entre comptes (AzCopy en arrière-plan).

## Bonus

### 1. Hiérarchisation forcée
```bash
lyon "Import-Module 'C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll'; \$f = 'F:\Partages\Commun\Qualite\audit-2024.bin'; 'AVANT : ' + (Get-Item \$f).Attributes; Invoke-StorageSyncCloudTiering -Path \$f; Start-Sleep 20; 'APRES : ' + (Get-Item \$f).Attributes; 'Volume F: libre (Mo) : ' + [math]::Round((Get-Volume F).SizeRemaining / 1MB)"
lyon "Import-Module 'C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll'; Invoke-StorageSyncFileRecall -Path 'F:\Partages\Commun\Qualite\audit-2024.bin'; 'RAPPEL : ' + (Get-Item 'F:\Partages\Commun\Qualite\audit-2024.bin').Attributes"
```
Sortie attendue (valeurs d'espace libre variables, environ 100 Mo de plus après hiérarchisation) :
```
AVANT : Archive
APRES : Archive, SparseFile, ReparsePoint, Offline
Volume F: libre (Mo) : 32540
RAPPEL : Archive
```
Le fichier hiérarchisé garde sa taille logique (100 Mo dans l'Explorateur) mais n'occupe presque plus d'espace sur le volume : son contenu est dans Azure Files, un point d'analyse le remplace localement. L'attribut `Offline` signale aux applications (et aux antivirus) qu'une lecture déclenchera un téléchargement. Après rappel, le fichier redevient local ; il peut être à nouveau hiérarchisé selon la stratégie.

### 2. Compte de fichiers restreint
```bash
NAT_IP=<IP_SORTIE_LYON>     # communiquée par la formatrice (lyon-nat.sh status)
az storage account update -g "$RG_DATA" -n "$SA_FILES" --default-action Deny --bypass AzureServices -o none
az storage account network-rule add -g "$RG_DATA" --account-name "$SA_FILES" --ip-address "$NAT_IP" -o none
lyon "Set-Content F:\Partages\Commun\RH\test-pare-feu.txt 'Test'; 'OK'"
sleep 120
az storage file list --share-name partage-lyon --account-name "$SA_FILES" --path RH -o none
# Rétablissement
az storage account update -g "$RG_DATA" -n "$SA_FILES" --default-action Allow -o none
```
Résultat attendu : `OK` ; le fichier apparaît dans le partage (contrôle par le portail, depuis un poste dont l'IP serait autorisée, ou après rétablissement) ; la commande `az storage file list` échoue depuis Cloud Shell (`AuthorizationFailure`), son IP n'étant pas autorisée. File Sync reste fonctionnel : l'agent sort par l'IP autorisée du NAT et le service de synchronisation bénéficie de l'exception des services approuvés `[À VÉRIFIER]` exigences réseau documentées d'Azure File Sync.

### 3. Bicep complet
Dans `scripts/catch-up/module-06/main.bicep` : `sss` (`storageSyncServices`), `syncGroup`, `cloudEndpoint` (dépend de l'attribution `syncRole` au principal Microsoft.StorageSync sur le compte de fichiers), `lyonSyncRole` (identité managée du serveur, Contributeur sur le service) et `serverEndpoint`, conditionnel à `registeredServerId`. Règle de réplication d'objets en CLI : ses `policyId` et `ruleId` sont générés par le compte de destination au moment de sa création, puis doivent être recopiés sur la source. Un nom de ressource Bicep doit être calculable au début du déploiement (erreur `BCP120` sinon) ; il faudrait un module recevant l'identifiant en paramètre, plus complexe qu'un appel CLI idempotent.

## QCM — Réponses
1. **C** — Standard v2 prend en charge Blob, Files, Queue et Table ; les comptes Premium sont spécialisés.
2. **C** — RA-GRS ajoute la lecture du secondaire de la région appairée, sans basculement.
3. **B** — Un blob archivé est hors ligne : il faut le réhydrater (changement de niveau ou copie).
4. **B** — Versioning sur les deux comptes et flux de modifications sur la source sont requis.
5. **D** — Le SAS de délégation d'utilisateur est signé par une clé obtenue via Entra ID, pas par la clé du compte.
6. **B** — `Owner` n'inclut aucune action de données : un rôle Storage Blob Data… est nécessaire.
7. **A** — Sans lien de la zone privée au VNet (ou sans groupe de zones), le nom résout vers l'IP publique.
8. **C** — Les changements faits directement dans Azure Files sont détectés par une tâche toutes les 24 h.
9. **B** — La hiérarchisation cloud n'est pas prise en charge sur le volume système.
10. **C** — 40 To à 100 Mbit/s demandent plus d'un mois : transfert hors ligne par Data Box.
