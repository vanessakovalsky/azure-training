# Module 02 — Exercices

**Environnement commun à tous les labs**
- Azure Cloud Shell en mode **Bash** (Azure CLI préinstallée), connecté avec le compte `stNN@<DOMAINE>`
- Droits : Propriétaire sur les six groupes `rg-stNN-*`, Lecteur sur l'abonnement, Lecteur général sur le tenant
- Objets issus du module 01 (ou du script `scripts/catch-up/module-01`) :

| Objet | Type | Membres attendus |
|---|---|---|
| `stNN-GRP-AdminsReseau` | Groupe de sécurité | Administrateurs réseau Arvéo |
| `stNN-GRP-Exploitation` | Groupe de sécurité | Équipe d'exploitation |
| `stNN-GRP-Logistique` | Groupe de sécurité | Dont `stNN-lea.martin` |

Variables à définir au début de CHAQUE session Cloud Shell :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<DOMAINE>` = domaine du tenant de formation (ex. `arveoformation.onmicrosoft.com`)

```bash
ST="st<NN>"
DOMAINE="<DOMAINE>"
SUB_ID=$(az account show --query id --output tsv)
echo "Stagiaire : $ST · Abonnement : $SUB_ID"
```
Résultat attendu : `Stagiaire : st07 · Abonnement : 1a2b3c4d-…` (identifiant propre au tenant de formation).

---

## Lab 02.1 ⭐ — Organiser et taguer la landing zone Arvéo (guidé)
**Durée** : 25 min · **Objectif** : 2 (structurer l'environnement, tags, budget)
**Contexte** : la direction financière d'Arvéo veut refacturer les coûts Azure au centre de coût informatique `CC-IT-1042` et être alertée avant tout dépassement sur le réseau hub (pare-feu et passerelle VPN, déployés aux modules 4 et 5).
**Prérequis** : six groupes de ressources `rg-stNN-*` vides, Cloud Shell ouvert, variables définies.

### Étapes
1. Repérer la place de l'abonnement dans la hiérarchie.
   - Portail : **Abonnements** → abonnement de formation → **Vue d'ensemble** → champ **Groupe d'administration parent**.
   - Puis lister les groupes de ressources du stagiaire :
   ```bash
   az group list --query "[?starts_with(name,'rg-${ST}-')].{nom:name, region:location}" \
     --output table
   ```
   Résultat attendu (6 lignes, ordre variable) :
   ```
   Nom             Region
   --------------  -------------
   rg-st07-shared  francecentral
   rg-st07-hub     francecentral
   rg-st07-spoke   francecentral
   rg-st07-data    francecentral
   rg-st07-app     francecentral
   rg-st07-lyon    westeurope
   ```

2. Taguer `rg-stNN-hub` depuis le portail.
   - **Groupes de ressources** → `rg-stNN-hub` → **Étiquettes**.
   - Ajouter : `Proprietaire` = `stNN`, `CentreDeCout` = `CC-IT-1042`, `Environnement` = `Prod`, `Application` = `Socle`.
   - **Appliquer**.
   Résultat attendu : la **Vue d'ensemble** du groupe affiche les quatre étiquettes.

3. Taguer les cinq autres groupes en CLI (fusion, sans écraser).
   ```bash
   declare -A APP=( [shared]=Socle [spoke]=Socle [data]=Donnees \
                    [app]=PortailClient [lyon]=SiteLyon )
   for R in "${!APP[@]}"; do
     ENV=Prod; [ "$R" = "lyon" ] && ENV=HorsProd
     RG_ID=$(az group show --name "rg-${ST}-${R}" --query id --output tsv)
     az tag update --resource-id "$RG_ID" --operation Merge --output none \
       --tags Proprietaire=$ST CentreDeCout=CC-IT-1042 Environnement=$ENV \
              Application=${APP[$R]}
   done
   ```
   Résultat attendu : aucune sortie, aucun message d'erreur.

4. Vérifier la taxonomie complète.
   ```bash
   az group list --tag Proprietaire=$ST \
     --query "[].{RG:name, App:tags.Application, Env:tags.Environnement, CC:tags.CentreDeCout}" \
     --output table
   ```
   Résultat attendu (ordre variable) :
   ```
   RG              App            Env       CC
   --------------  -------------  --------  ----------
   rg-st07-shared  Socle          Prod      CC-IT-1042
   rg-st07-hub     Socle          Prod      CC-IT-1042
   rg-st07-spoke   Socle          Prod      CC-IT-1042
   rg-st07-data    Donnees        Prod      CC-IT-1042
   rg-st07-app     PortailClient  Prod      CC-IT-1042
   rg-st07-lyon    SiteLyon       HorsProd  CC-IT-1042
   ```

5. Créer un budget sur `rg-stNN-hub` (portail).
   - `rg-stNN-hub` → **Budgets** (section Gestion des coûts) → **+ Ajouter**.
   - Nom : `bud-stNN-hub` · Période de réinitialisation : **Mensuelle** · Date d'expiration : fin de l'année en cours.
   - Montant : `<MONTANT_BUDGET>` (valeur annoncée par la formatrice).
   - **Suivant** → conditions d'alerte :
     - Type **Réel**, seuil **80 %**
     - Type **Prévu**, seuil **100 %**
   - Destinataires : `<COURRIEL_STAGIAIRE>` (adresse personnelle, le compte `stNN` n'a pas de boîte aux lettres) · Langue : **Français**.
   - **Créer**.
   Résultat attendu : le budget `bud-stNN-hub` apparaît dans la liste avec un montant consommé de 0 ou proche de 0.

6. Contrôler le budget en CLI (groupe de commandes `az consumption` en préversion).
   ```bash
   az consumption budget list --resource-group "rg-${ST}-hub" \
     --query "[].{nom:name, montant:amount, periode:timeGrain}" --output table
   ```
   Résultat attendu :
   ```
   Nom           Montant    Periode
   ------------  ---------  ---------
   bud-st07-hub  100.0      Monthly
   ```
   Si la commande échoue, vérifier dans le portail (étape 5) : la vérification portail fait foi.

7. Consulter les recommandations de coût Azure Advisor.
   ```bash
   az advisor recommendation list --category Cost --output table
   ```
   Résultat attendu : liste vide ou recommandations sur d'autres ressources de l'abonnement (aucune ressource déployée par le stagiaire à ce stade).

8. Explorer l'analyse des coûts par tag.
   - `rg-stNN-hub` → **Analyse des coûts** → **Regrouper par** → **Étiquette** → `CentreDeCout`.
   Résultat attendu : graphique vide ou quasi vide (aucune ressource payante), structure de regroupement disponible pour les modules suivants.

### Critères de réussite
- [ ] Six groupes `rg-stNN-*` portent les quatre tags de la taxonomie (commande de l'étape 4)
- [ ] `rg-stNN-lyon` porte `Environnement=HorsProd`, les cinq autres `Prod`
- [ ] Budget `bud-stNN-hub` mensuel avec deux alertes (80 % réel, 100 % prévu)
- [ ] Explication orale : pourquoi le budget n'arrêtera PAS la passerelle VPN en cas de dépassement

---

## Exercice 02.2 ⭐⭐ — Garde-fous de région et de taille de VM (semi-autonome)
**Durée** : 25 min · **Objectif** : 2 (appliquer une Azure Policy refusant une ressource non conforme)
**Contexte** : le RSSI d'Arvéo impose la localisation des données en France. Seul le site de Lyon simulé (`rg-stNN-lyon`) reste en West Europe. Pour maîtriser le budget, seules les tailles de VM de la gamme B validées par la DSI sont autorisées.

**Énoncé** : obtenir les garde-fous suivants, uniquement avec des stratégies intégrées.

| Exigence | Scope | Paramètre |
|---|---|---|
| Régions autorisées | `rg-stNN-shared`, `-hub`, `-spoke`, `-data`, `-app` | `francecentral` |
| Régions autorisées | `rg-stNN-lyon` | `westeurope` |
| Tailles de VM autorisées | `rg-stNN-app`, `rg-stNN-lyon` | `Standard_B2s_v2`, `Standard_B2als_v2`, `Standard_B2ats_v2` |

Conventions de nommage des affectations :
- `pa-stNN-loc-<suffixe>` (ex. `pa-st07-loc-hub`)
- `pa-stNN-vmsku-<suffixe>` (ex. `pa-st07-vmsku-app`)

Preuves attendues :
1. Création d'un groupe de sécurité réseau `nsg-stNN-test` en **West Europe** dans `rg-stNN-hub` : **refusée**.
2. Création du même NSG en **France Central** : **acceptée**, puis suppression du NSG.
3. Résumé de conformité de `rg-stNN-hub` après une analyse à la demande.

**Indices**
- Stratégies intégrées : « Allowed locations » et « Allowed virtual machine size SKUs ».
- Paramètres : `listOfAllowedLocations` et `listOfAllowedSKUs`.
- `az policy definition list --query "[?displayName=='…'].name"` retourne le nom (GUID) d'une définition.
- `az policy assignment create` accepte `--resource-group` comme scope et `--params` en JSON.
- Une boucle `for` sur les suffixes `shared hub spoke data app lyon` évite six commandes.
- Prise d'effet d'une affectation : attendre quelques minutes avant le test de refus.
- `az policy state trigger-scan` puis `az policy state summarize`.

**Critères de réussite**
- [ ] Huit affectations visibles :
  ```bash
  for R in shared hub spoke data app lyon; do
    az policy assignment list --resource-group "rg-${ST}-${R}" \
      --query "[?starts_with(name,'pa-${ST}-')].name" --output tsv
  done
  ```
- [ ] Message `RequestDisallowedByPolicy` lors de la création en West Europe
- [ ] NSG de test en France Central créé puis supprimé (aucun `nsg-stNN-test` restant)
- [ ] Explication : pourquoi un réseau virtuel dans `rg-stNN-lyon` en West Europe reste autorisé

---

## Exercice 02.3 ⭐⭐ — Matrice des accès Arvéo et verrou (semi-autonome)
**Durée** : 15 min · **Objectif** : 3 (attribuer des rôles RBAC au bon scope)
**Contexte** : la DSI d'Arvéo formalise la délégation des droits avant le déploiement du réseau (module 4) et des VM (module 7). Les ressources partagées (journalisation, coffre de clés à venir) ne doivent jamais être supprimées par erreur.

**Énoncé**

1. Appliquer la matrice d'accès suivante, en attribuant les rôles à des **groupes** :

| Groupe | Rôle intégré | Scope |
|---|---|---|
| `stNN-GRP-AdminsReseau` | Contributeur de réseau (Network Contributor) | `rg-stNN-hub`, `rg-stNN-spoke` |
| `stNN-GRP-Exploitation` | Contributeur de machines virtuelles (Virtual Machine Contributor) | `rg-stNN-app` |
| `stNN-GRP-Logistique` | Lecteur (Reader) | `rg-stNN-app` |

2. Vérifier les accès effectifs de `stNN-lea.martin` (membre de `stNN-GRP-Logistique`) :
   - en CLI ;
   - dans le portail, avec **Contrôle d'accès (IAM)** → **Vérifier l'accès**.
3. Poser un verrou `CanNotDelete` nommé `lock-stNN-shared` sur `rg-stNN-shared`.
4. Prouver l'effet du verrou : créer le NSG `nsg-stNN-verrou` (France Central) dans `rg-stNN-shared`, puis tenter de le supprimer.

**Indices**
- `az ad group show --group <NOM> --query id --output tsv` : ID d'objet d'un groupe (lecture autorisée par le rôle Lecteur général).
- `az role assignment create` : préférer `--assignee-object-id` + `--assignee-principal-type Group`.
- `az role assignment list --assignee <UPN> --all --include-groups` : attributions directes ET via les groupes.
- `az lock create`, `az lock list`.
- Le NSG `nsg-stNN-verrou` est conservé (gratuit) : il est supprimé au nettoyage de fin de formation.

**Critères de réussite**
- [ ] Quatre attributions de rôle visibles :
  ```bash
  for R in hub spoke app; do
    az role assignment list --resource-group "rg-${ST}-${R}" \
      --query "[?principalType=='Group'].{groupe:principalName, role:roleDefinitionName}" \
      --output table
  done
  ```
- [ ] `stNN-lea.martin` : Lecteur sur `rg-stNN-app` uniquement (hors droits hérités de l'abonnement)
- [ ] Suppression de `nsg-stNN-verrou` refusée avec un message `ScopeLocked`
- [ ] Explication : pourquoi le stagiaire, propriétaire du groupe, est lui aussi bloqué

---

## Défi 02.4 ⭐⭐⭐ — Rôle personnalisé « Opérateur VM » (autonome)
**Durée** : 10 min · **Objectif** : 3 (créer un rôle personnalisé, moindre privilège)
**Contexte** : l'audit interne d'Arvéo relève que l'équipe d'exploitation, avec le rôle Contributeur de machines virtuelles, peut SUPPRIMER ou redimensionner les VM du portail client. Son besoin réel se limite aux opérations d'astreinte.

**Énoncé** : remplacer l'attribution Contributeur de machines virtuelles de `stNN-GRP-Exploitation` par un rôle personnalisé respectant ces contraintes :
- Nom : `stNN-Operateur-VM-Arveo` (unique dans le tenant).
- Autorisé : consulter les VM, leur état d'exécution, leurs disques et leurs interfaces réseau ; démarrer, arrêter, désallouer et redémarrer les VM.
- Interdit : créer, modifier, redimensionner ou supprimer une ressource.
- Attribuable uniquement sur `rg-stNN-app`.
- Aucun caractère générique (`*`) dans les actions.
- À justifier : chaque action retenue, à partir de la liste des opérations du fournisseur `Microsoft.Compute`.

Question à traiter par écrit : un verrou `ReadOnly` sur `rg-stNN-app` est-il compatible avec le travail de cette équipe ? Justifier.

**Critères de réussite**
- [ ] `az role definition list --custom-role-only true --scope <ID_RG_APP>` affiche le rôle avec un seul scope attribuable
- [ ] Aucune action `write`, `delete` ni `*` dans la définition
- [ ] `stNN-GRP-Exploitation` : rôle personnalisé sur `rg-stNN-app`, plus aucune attribution Contributeur de machines virtuelles
- [ ] Réponse argumentée sur le verrou `ReadOnly`

---

## Bonus 🚀 — Héritage automatique du centre de coût
**Contexte** : les tags posés sur les groupes de ressources ne sont pas hérités par les ressources. La direction financière veut que chaque ressource déployée aux modules suivants porte automatiquement `CentreDeCout` et `Environnement`.

**Énoncé**
1. Affecter la stratégie intégrée « Inherit a tag from the resource group if missing » sur `rg-stNN-app` et `rg-stNN-spoke`, une affectation par tag (`CentreDeCout`, `Environnement`), nommées `pa-stNN-tag-<tag>-<suffixe>`.
2. Doter chaque affectation d'une identité managée affectée par le système (région `francecentral`) avec le rôle prévu dans la définition, limité au groupe de ressources.
3. Créer un NSG `nsg-stNN-tagtest` dans `rg-stNN-app` SANS tag, vérifier les tags hérités, puis supprimer le NSG.
4. Expliquer le rôle d'une tâche de correction (remediation) pour les ressources créées AVANT l'affectation.

**Indices**
- `az policy definition show --name <GUID> --query "policyRule.then.details.roleDefinitionIds"` : rôle requis par la définition.
- `az policy assignment create … --mi-system-assigned --location francecentral --role <RÔLE> --identity-scope <ID_RG>`.
- `az policy remediation create --policy-assignment <NOM> --resource-group <RG>`.
