# Module 01 — Exercices

Variables utilisées dans tout le module (à définir au début de chaque session Cloud Shell PowerShell) :
- `<NN>` = numéro de stagiaire sur deux chiffres (ex. `07`)
- `<DOMAINE>` = domaine du tenant (ex. `arveoformation.onmicrosoft.com`)
- `<MDP>` = mot de passe initial choisi pour les utilisateurs de lab (12 caractères minimum, majuscule, minuscule, chiffre, symbole)

```powershell
$NN = "<NN>"
$Domaine = "<DOMAINE>"
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","AdministrativeUnit.ReadWrite.All","AuditLog.Read.All","User.Invite.All" -UseDeviceCode -NoWelcome
$au = Get-MgDirectoryAdministrativeUnit -Filter "displayName eq 'AU-st$NN'"
$au.DisplayName
```
Résultat attendu : `AU-st07` (avec son numéro).

---

## Lab 01.0 ⭐ — Explorer le tenant (guidé)
**Durée** : 5 min · **Objectif** : lire l'organisation du tenant avant d'y écrire
**Contexte** : la nouvelle équipe d'administration Arvéo découvre son tenant.
**Prérequis** : Lab 00.1 terminé

### Étapes
1. Ouvrir https://entra.microsoft.com, menu **Vue d'ensemble**.
   Résultat attendu : nom du tenant, ID du tenant, domaine principal `<DOMAINE>`, licence Microsoft Entra ID P2.
2. Menu **Rôles et administrateurs** > **Administrateur d'utilisateurs** > **Attributions**.
   Résultat attendu : son compte `st<NN>` listé avec le scope `AU-st<NN>`.
3. Afficher son identité en ligne de commande (Cloud Shell Bash).
   ```bash
   az ad signed-in-user show --query "{upn:userPrincipalName, id:id}" -o table
   ```
   Résultat attendu : son UPN `st<NN>@<DOMAINE>` et son ID d'objet.

### Critères de réussite
- [ ] Domaine principal et ID du tenant notés
- [ ] Scope `AU-st<NN>` identifié sur ses rôles Entra

---

## Lab 01.1 ⭐ — Créer l'équipe de direction Arvéo dans le portail (guidé)
**Durée** : 20 min · **Objectif** : créer des utilisateurs avec leurs attributs dans un périmètre délégué
**Contexte** : Arvéo démarre sa migration ; trois personnes clés ont besoin d'un compte cloud.
**Prérequis** : Lab 01.0 terminé

| Utilisateur | Service (`department`) | Poste (`jobTitle`) |
|---|---|---|
| Claire Dubois | Direction | Directrice des opérations |
| Léa Martin | Logistique | Cheffe de quai |
| Karim Haddad | IT | Administrateur systèmes |

### Étapes
1. Portail Entra > **Utilisateurs** > **Tous les utilisateurs** > **Nouvel utilisateur** > **Créer un utilisateur**.
2. Onglet **Informations de base** :
   - Nom d'utilisateur principal : `st<NN>-claire.dubois`, domaine `<DOMAINE>`
   - Nom d'affichage : `Claire Dubois`
   - Mot de passe : généré automatiquement, **le noter**
   - Compte activé : coché
3. Onglet **Propriétés** :
   - Prénom `Claire`, Nom `Dubois`
   - Poste `Directrice des opérations`, Service `Direction`
   - Nom de l'entreprise `Arveo-st<NN>`
   - Emplacement d'utilisation : `France`
4. Onglet **Affectations** > **Ajouter une unité administrative** > `AU-st<NN>` `[À VÉRIFIER]` libellé exact de l'onglet dans l'assistant.
5. **Vérifier + créer** > **Créer**.
   Résultat attendu : notification « Utilisateur créé ».
6. Répéter les étapes 1 à 5 pour Léa Martin (`st<NN>-lea.martin`) et Karim Haddad (`st<NN>-karim.haddad`), noter leurs mots de passe.
7. Vérifier le contenu de l'unité administrative (Cloud Shell PowerShell, variables définies en tête de module).
   ```powershell
   Get-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -All |
     ForEach-Object { $_.AdditionalProperties.userPrincipalName }
   ```
   Résultat attendu :
   ```
   st07-claire.dubois@arveoformation.onmicrosoft.com
   st07-lea.martin@arveoformation.onmicrosoft.com
   st07-karim.haddad@arveoformation.onmicrosoft.com
   ```
8. Tester la délégation dans le portail :
   - Ouvrir `st<NN>-karim.haddad` > **Réinitialiser le mot de passe** : action possible, nouveau mot de passe affiché.
   - Ouvrir un utilisateur d'un autre stagiaire (ex. `st<NN+1>-claire.dubois`) : **Réinitialiser le mot de passe** grisé ou refusé.

### Critères de réussite
- [ ] 3 utilisateurs `st<NN>-*` membres de `AU-st<NN>`
- [ ] Attributs `department`, `jobTitle`, `companyName`, `usageLocation` renseignés (vérification : `Get-MgUser -UserId "st$NN-lea.martin@$Domaine" -Property department,jobTitle,companyName,usageLocation | Format-List department,jobTitle,companyName,usageLocation`)
- [ ] Réinitialisation possible sur son AU, refusée hors de son AU

---

## Exercice 01.2 ⭐⭐ — Importer les équipes opérationnelles et créer les groupes (semi-autonome)
**Durée** : 25 min · **Objectif** : créer des utilisateurs en lot et des groupes attribués et dynamiques dans son AU
**Contexte** : la DSI d'Arvéo transmet un export RH de 6 personnes. Le groupe Logistique doit se mettre à jour seul ; le groupe IT est géré manuellement.

**Fichier fourni** : créer `arveo-utilisateurs.csv` dans Cloud Shell avec ce contenu exact.
```powershell
@"
Prenom,Nom,Departement,Poste
hugo,bernard,Logistique,Chef d'equipe quai
sofia,moreau,Logistique,Agente de quai
yanis,lefebvre,Logistique,Cariste
ines,garcia,Exploitation,Planificatrice transport
thomas,roux,IT,Technicien support
camille,fontaine,Finance,Comptable
"@ | Set-Content ./arveo-utilisateurs.csv
```

**Énoncé** :
1. Créer les 6 utilisateurs dans `AU-st<NN>` par script : UPN `st<NN>-prenom.nom@<DOMAINE>`, nom d'affichage avec majuscules (`Hugo Bernard`), `department`, `jobTitle`, `companyName = Arveo-st<NN>`, `usageLocation = FR`, mot de passe `<MDP>` à changer à la première connexion.
2. Créer dans `AU-st<NN>` le groupe de sécurité attribué `st<NN>-GRP-IT` et y ajouter Karim Haddad et Thomas Roux.
3. Créer dans `AU-st<NN>` le groupe de sécurité dynamique `st<NN>-GRP-Logistique` dont la règle retient les utilisateurs du service Logistique de SON entité uniquement.
4. Vérifier les membres des deux groupes.

**Indices** :
- Même méthode que la slide « Créer un utilisateur dans son AU », dans une boucle `Import-Csv | ForEach-Object`.
- `(Get-Culture).TextInfo.ToTitleCase("hugo")` renvoie `Hugo`.
- Un groupe se crée aussi avec `New-MgDirectoryAdministrativeUnitMember`, `"@odata.type" = "#microsoft.graph.group"`.
- Propriétés d'un groupe dynamique : `groupTypes`, `membershipRule`, `membershipRuleProcessingState`.
- Ajout d'un membre : `New-MgGroupMember` ; lecture : `Get-MgGroupMember`.
- Documentation : https://learn.microsoft.com/graph/api/administrativeunit-post-members et https://learn.microsoft.com/entra/identity/users/groups-dynamic-membership

**Critères de réussite** :
- [ ] `Get-MgDirectoryAdministrativeUnitMember` liste 9 utilisateurs et 2 groupes
- [ ] `st<NN>-GRP-IT` contient exactement Karim Haddad et Thomas Roux
- [ ] `st<NN>-GRP-Logistique` contient exactement Léa Martin, Hugo Bernard, Sofia Moreau, Yanis Lefebvre (délai de traitement possible)
- [ ] Aucun utilisateur d'un autre stagiaire dans `st<NN>-GRP-Logistique`
- [ ] Script rejouable conservé (il servira de modèle aux modules suivants)

---

## Lab 01.3 ⭐ — Piloter le SSPR avec Léa Martin (guidé)
**Durée** : 20 min · **Objectif** : inscrire un utilisateur pilote au SSPR et tester la réinitialisation de bout en bout
**Contexte** : Arvéo lance le SSPR sur un groupe pilote avant généralisation. Le paramétrage du tenant est fait par la formatrice ; le stagiaire inscrit ses pilotes en jouant sur un attribut.
**Prérequis** : Lab 01.1 terminé, mot de passe de Léa Martin noté

### Étapes
1. Lire la configuration SSPR (rôle Lecteur général) : portail Entra > **Protection** > **Réinitialisation du mot de passe** > **Propriétés** et **Méthodes d'authentification**.
   Résultat attendu : SSPR activé pour **Sélectionné** = `GRP-SSPR-Pilote` ; méthodes Questions de sécurité et E-mail ; 1 méthode requise.
2. Lire la règle du groupe pilote.
   ```powershell
   $sspr = Get-MgGroup -Filter "displayName eq 'GRP-SSPR-Pilote'" -Property id,membershipRule
   $sspr.MembershipRule
   ```
   Résultat attendu :
   ```
   (user.employeeType -eq "Pilote-SSPR")
   ```
3. Désigner Léa Martin comme pilote.
   ```powershell
   Update-MgUser -UserId "st$NN-lea.martin@$Domaine" -EmployeeType "Pilote-SSPR"
   ```
   Résultat attendu : aucune sortie, aucune erreur.
4. Vérifier son entrée dans le groupe pilote (relancer toutes les minutes si vide).
   ```powershell
   Get-MgGroupMember -GroupId $sspr.Id -All |
     Where-Object { $_.AdditionalProperties.userPrincipalName -like "st$NN-*" } |
     ForEach-Object { $_.AdditionalProperties.userPrincipalName }
   ```
   Résultat attendu :
   ```
   st07-lea.martin@arveoformation.onmicrosoft.com
   ```
5. Dans une **nouvelle** fenêtre de navigation privée, ouvrir https://mysignins.microsoft.com/security-info et se connecter en tant que `st<NN>-lea.martin@<DOMAINE>` avec le mot de passe noté au Lab 01.1.
   Résultat attendu : changement de mot de passe imposé, puis demande d'inscription des informations de sécurité.
6. Inscrire les **questions de sécurité** (réponses à retenir), puis se déconnecter.
7. Ouvrir https://passwordreset.microsoftonline.com, saisir l'UPN de Léa et le code anti-robot, répondre aux questions, définir un nouveau mot de passe.
   Résultat attendu : message « Votre mot de passe a été réinitialisé ».
8. Retrouver l'événement dans les journaux d'audit.
   ```powershell
   Get-MgAuditLogDirectoryAudit -Filter "loggedByService eq 'Self-service Password Management'" -Top 50 |
     Where-Object { $_.TargetResources.UserPrincipalName -like "st$NN-*" } |
     Select-Object ActivityDateTime, ActivityDisplayName, Result
   ```
   Résultat attendu (extrait) :
   ```
   ActivityDateTime      ActivityDisplayName              Result
   ----------------      -------------------              ------
   07/10/2026 11:58:12   Reset password (self-service)    success
   ```

### Critères de réussite
- [ ] Léa Martin membre de `GRP-SSPR-Pilote`
- [ ] Réinitialisation en libre-service réussie
- [ ] Événement `Reset password (self-service)` visible dans les journaux d'audit

---

## Défi 01.4 ⭐⭐⭐ — Mobilité, départ et partenaire externe (autonome)
**Durée** : 20 min · **Objectif** : appliquer le cycle de vie Arrivée-Mobilité-Départ et en apporter la preuve
**Contexte** : lundi matin chez Arvéo.
- Hugo Bernard est promu technicien IT au 1er du mois.
- Karim Haddad quitte l'entreprise ce soir dans un contexte conflictuel : son accès doit être coupé immédiatement, mais son compte doit rester récupérable 30 jours.
- Le transporteur partenaire TransAlpes doit accéder aux applications partagées d'Arvéo.

**Énoncé** :
1. **Mobilité** : faire passer Hugo Bernard en IT. Constater sa sortie automatique de `st<NN>-GRP-Logistique` et l'ajouter à `st<NN>-GRP-IT`.
2. **Départ** : écrire un script de départ pour Karim Haddad qui bloque la connexion, révoque les sessions, retire l'utilisateur de ses groupes attribués et définit un mot de passe aléatoire ; puis supprimer le compte.
3. **Erreur RH** : Karim n'est finalement pas parti. Restaurer le compte et constater ce qui est conservé (attributs, appartenance à l'AU, groupes). Noter les constats.
4. **Partenaire** : inviter une adresse e-mail externe dont on dispose (adresse personnelle ou adresse fournie par la formatrice), créer le groupe attribué `st<NN>-GRP-Partenaires` dans son AU et y ajouter l'invité.
5. **Preuve** : exporter en CSV les événements d'audit du jour initiés par son compte `st<NN>` (date, activité, cible, résultat).

**Contraintes** :
- Aucune action sur un objet hors de son périmètre `st<NN>`.
- Étape 2 exécutable en une seule commande (script ou fonction), sans saisie interactive.

**Critères de réussite** :
- [ ] Hugo Bernard : `department = IT`, absent de `st<NN>-GRP-Logistique`, présent dans `st<NN>-GRP-IT`
- [ ] Karim Haddad restauré, compte toujours bloqué (`accountEnabled = false`) jusqu'à décision RH
- [ ] Constats de restauration notés (ce qui revient, ce qui ne revient pas)
- [ ] Invité visible avec `userType = Guest` et membre de `st<NN>-GRP-Partenaires`
- [ ] Fichier `audit-st<NN>.csv` produit, contenant au moins les activités de création, mise à jour, suppression et restauration

---

## Bonus 🚀
Transformer le script de départ en fonction réutilisable `Invoke-ArveoLeaver -UserPrincipalName <UPN> [-WhatIf]` qui :
- prend en charge `-WhatIf` (aucune modification, affichage des actions prévues) ;
- produit un rapport (objet PowerShell) listant chaque action et son résultat ;
- refuse de s'exécuter si l'UPN ne commence pas par `st<NN>-`.
