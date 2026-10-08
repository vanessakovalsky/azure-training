# Module 00 — Exercices

Variables utilisées dans ce module :
- `<NN>` = numéro de stagiaire sur deux chiffres, fourni par la formatrice (ex. `07`)
- `<DOMAINE>` = domaine du tenant de formation, fourni par la formatrice (ex. `arveoformation.onmicrosoft.com`)
- `<MOT_DE_PASSE_TEMPORAIRE>` = mot de passe remis par la formatrice

## Lab 00.1 ⭐ — Première connexion et vérification des droits (guidé)
**Durée** : 20 min · **Objectif** : se connecter au portail Azure avec MFA, ouvrir Cloud Shell et vérifier son périmètre
**Contexte** : premier jour de l'équipe d'administration Azure d'Arvéo ; les comptes ont été créés par la formatrice.
**Prérequis** : smartphone avec Microsoft Authenticator installé, navigateur récent, identifiants remis par la formatrice

### Étapes
1. Ouvrir une fenêtre de navigation privée et aller sur https://portal.azure.com.
   Se connecter avec `st<NN>@<DOMAINE>` et `<MOT_DE_PASSE_TEMPORAIRE>`.
   Résultat attendu : demande de changement de mot de passe.

2. Définir un nouveau mot de passe (12 caractères minimum, à conserver pour les 4 jours).
   Résultat attendu : écran « Plus d'informations requises ».

3. Suivre l'assistant d'enregistrement : ajouter Microsoft Authenticator, scanner le QR code, valider la notification de test.
   Résultat attendu : arrivée sur la page d'accueil du portail Azure.

4. Ouvrir Cloud Shell (icône `>_` dans la barre supérieure), choisir **Bash**, puis l'option sans compte de stockage (session éphémère) `[À VÉRIFIER]` libellé exact de l'option.
   Résultat attendu : invite `st<NN> [ ~ ]$` (ou équivalent).

5. Vérifier le contexte de connexion.
   ```bash
   az account show --query "{abonnement:name, utilisateur:user.name, tenant:tenantId}" -o table
   ```
   Résultat attendu :
   ```
   Abonnement          Utilisateur                              Tenant
   ------------------  ---------------------------------------  ------------------------------------
   <NOM_ABONNEMENT>    st07@arveoformation.onmicrosoft.com      <ID_TENANT>
   ```

6. Lister ses groupes de ressources.
   ```bash
   NN=<NN>
   az group list --query "[?starts_with(name, 'rg-st${NN}-')].{nom:name, region:location}" -o table
   ```
   Résultat attendu (6 lignes) :
   ```
   Nom            Region
   -------------  -------------
   rg-st07-app    francecentral
   rg-st07-data   francecentral
   rg-st07-hub    francecentral
   rg-st07-lyon   westeurope
   rg-st07-shared francecentral
   rg-st07-spoke  francecentral
   ```

7. Vérifier ses attributions de rôles Azure.
   ```bash
   az role assignment list --assignee "st${NN}@<DOMAINE>" --all \
     --query "[].{role:roleDefinitionName, scope:scope}" -o table
   ```
   Résultat attendu : 8 lignes — 6 × `Owner` sur `rg-st<NN>-*`, 1 × `Reader` sur l'abonnement, 1 × `Network Contributor` sur `NetworkWatcherRG`.

8. Basculer Cloud Shell en **PowerShell** (menu de la barre Cloud Shell), puis se connecter à Microsoft Graph.
   ```powershell
   $NN = "<NN>"
   Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","AdministrativeUnit.ReadWrite.All" -UseDeviceCode -NoWelcome
   ```
   Résultat attendu : un code à saisir sur https://microsoft.com/devicelogin, puis retour à l'invite sans erreur.

9. Vérifier son unité administrative.
   ```powershell
   Get-MgDirectoryAdministrativeUnit -Filter "displayName eq 'AU-st$NN'" | Select-Object DisplayName, Id
   ```
   Résultat attendu :
   ```
   DisplayName Id
   ----------- --
   AU-st07     5b0c2e1a-8f3d-4c6b-9a71-2d4e6f8a1b3c
   ```

### Critères de réussite
- [ ] Connexion au portail Azure avec MFA fonctionnelle
- [ ] `az account show` affiche son propre compte `st<NN>`
- [ ] 6 groupes de ressources `rg-st<NN>-*` listés
- [ ] 8 attributions de rôles Azure visibles
- [ ] `Connect-MgGraph` sans demande d'approbation administrateur, AU `AU-st<NN>` trouvée

---

## Bonus 🚀
Explorer le portail Microsoft Entra (https://entra.microsoft.com) : repérer, sans rien modifier, le domaine principal du tenant, le nombre de licences Entra ID P2 disponibles et ses propres rôles Entra (menu **Rôles et administrateurs**).
