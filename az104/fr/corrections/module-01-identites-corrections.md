# Module 01 — Corrections

Toutes les solutions supposent les variables et la connexion définies en tête du fichier exercices :
```powershell
$NN = "07"                                    # numéro du stagiaire
$Domaine = "arveoformation.onmicrosoft.com"   # domaine du tenant
$Mdp = "<MDP>"                                # mot de passe initial des utilisateurs de lab
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","AdministrativeUnit.ReadWrite.All","AuditLog.Read.All","User.Invite.All" -UseDeviceCode -NoWelcome
$au = Get-MgDirectoryAdministrativeUnit -Filter "displayName eq 'AU-st$NN'"
```

## Lab 01.0 ⭐ — Explorer le tenant

### Solution
Lecture seule : portail Entra > Vue d'ensemble, puis Rôles et administrateurs. Commande de contrôle :
```bash
az ad signed-in-user show --query "{upn:userPrincipalName, id:id}" -o table
```

### Pourquoi
Lire avant d'écrire : dans un tenant partagé, connaître ses rôles ET leur scope évite les erreurs « accès refusé » mal interprétées.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Rôle affiché sans scope | Vue « Rôles et administrateurs » au niveau tenant | Ouvrir le rôle > Attributions : la colonne Scope affiche `AU-st<NN>` |
| Licence P2 absente de la vue d'ensemble | Essai non activé ou non attribué | Formatrice : activer l'essai et relancer le provisioning (attribution des licences) |

---

## Lab 01.1 ⭐ — Créer l'équipe de direction Arvéo dans le portail

### Solution
Étapes de l'énoncé. Équivalent PowerShell (utile si l'assistant du portail ne propose pas l'onglet Affectations) :
```powershell
$equipe = @(
    @{ Login = "claire.dubois"; Prenom = "Claire"; Nom = "Dubois"; Service = "Direction";  Poste = "Directrice des opérations" }
    @{ Login = "lea.martin";    Prenom = "Léa";    Nom = "Martin"; Service = "Logistique"; Poste = "Cheffe de quai" }
    @{ Login = "karim.haddad";  Prenom = "Karim";  Nom = "Haddad"; Service = "IT";         Poste = "Administrateur systèmes" }
)
foreach ($p in $equipe) {
    $body = @{
        "@odata.type"     = "#microsoft.graph.user"
        displayName       = "$($p.Prenom) $($p.Nom)"
        givenName         = $p.Prenom
        surname           = $p.Nom
        userPrincipalName = "st$NN-$($p.Login)@$Domaine"
        mailNickname      = "st$NN-$($p.Login)"
        accountEnabled    = $true
        usageLocation     = "FR"
        department        = $p.Service
        jobTitle          = $p.Poste
        companyName       = "Arveo-st$NN"
        passwordProfile   = @{ password = $Mdp; forceChangePasswordNextSignIn = $true }
    }
    New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter $body | Out-Null
}
Get-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -All |
    ForEach-Object { $_.AdditionalProperties.userPrincipalName }
```
Sortie attendue :
```
st07-claire.dubois@arveoformation.onmicrosoft.com
st07-lea.martin@arveoformation.onmicrosoft.com
st07-karim.haddad@arveoformation.onmicrosoft.com
```

### Pourquoi
- `usageLocation` est obligatoire pour attribuer une licence : le renseigner à la création évite un échec silencieux plus tard.
- `companyName = Arveo-st<NN>` sert de discriminant dans les règles dynamiques (Exercice 01.2) : sans lui, une règle sur `department` capturerait les utilisateurs de tous les stagiaires.
- Le test de réinitialisation hors AU démontre le moindre privilège : même rôle, scope différent, résultat différent.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| « Vous n'avez pas les autorisations » à la création | Utilisateur créé au niveau tenant, sans affectation à l'AU | Ajouter l'AU dans l'onglet Affectations, ou utiliser la méthode PowerShell ci-dessus |
| UPN déjà utilisé | Préfixe `st<NN>` oublié ou numéro d'un autre stagiaire | Vérifier `$NN` et le préfixe |
| Mot de passe généré non noté | Assistant fermé trop vite | Réinitialiser le mot de passe depuis la fiche utilisateur (rôle délégué sur l'AU) |
| Réinitialisation possible sur l'utilisateur d'un autre stagiaire | Rôle attribué au scope tenant par erreur | Signaler à la formatrice (anomalie de provisioning) |

---

## Exercice 01.2 ⭐⭐ — Importer les équipes opérationnelles et créer les groupes

### Solution
```powershell
# 1. Utilisateurs depuis le CSV (rejouable : ignore les comptes existants)
$ti = (Get-Culture).TextInfo
Import-Csv ./arveo-utilisateurs.csv | ForEach-Object {
    $login = "st$NN-$($_.Prenom).$($_.Nom)"
    if (Get-MgUser -Filter "userPrincipalName eq '$login@$Domaine'") {
        Write-Host "Existe déjà : $login"
        return
    }
    $body = @{
        "@odata.type"     = "#microsoft.graph.user"
        displayName       = "$($ti.ToTitleCase($_.Prenom)) $($ti.ToTitleCase($_.Nom))"
        givenName         = $ti.ToTitleCase($_.Prenom)
        surname           = $ti.ToTitleCase($_.Nom)
        userPrincipalName = "$login@$Domaine"
        mailNickname      = $login
        accountEnabled    = $true
        usageLocation     = "FR"
        department        = $_.Departement
        jobTitle          = $_.Poste
        companyName       = "Arveo-st$NN"
        passwordProfile   = @{ password = $Mdp; forceChangePasswordNextSignIn = $true }
    }
    New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter $body | Out-Null
    Write-Host "Créé : $login"
}

# 2. Groupe attribué st<NN>-GRP-IT
$it = New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter @{
    "@odata.type"   = "#microsoft.graph.group"
    displayName     = "st$NN-GRP-IT"
    description     = "Arvéo - équipe IT (appartenance attribuée)"
    mailEnabled     = $false
    mailNickname    = "st$NN-grp-it"
    securityEnabled = $true
}
foreach ($login in "karim.haddad", "thomas.roux") {
    $u = Get-MgUser -UserId "st$NN-$login@$Domaine"
    New-MgGroupMember -GroupId $it.Id -DirectoryObjectId $u.Id
}

# 3. Groupe dynamique st<NN>-GRP-Logistique
New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter @{
    "@odata.type"                 = "#microsoft.graph.group"
    displayName                   = "st$NN-GRP-Logistique"
    description                   = "Arvéo - service Logistique (appartenance dynamique)"
    mailEnabled                   = $false
    mailNickname                  = "st$NN-grp-logistique"
    securityEnabled               = $true
    groupTypes                    = @("DynamicMembership")
    membershipRule                = "(user.department -eq `"Logistique`") -and (user.companyName -eq `"Arveo-st$NN`")"
    membershipRuleProcessingState = "On"
} | Out-Null

# 4. Vérification
foreach ($name in "st$NN-GRP-IT", "st$NN-GRP-Logistique") {
    $g = Get-MgGroup -Filter "displayName eq '$name'"
    "== $name"
    Get-MgGroupMember -GroupId $g.Id -All | ForEach-Object { $_.AdditionalProperties.displayName }
}
```
Sortie attendue (après traitement de la règle dynamique, quelques minutes) :
```
Créé : st07-hugo.bernard
Créé : st07-sofia.moreau
Créé : st07-yanis.lefebvre
Créé : st07-ines.garcia
Créé : st07-thomas.roux
Créé : st07-camille.fontaine
== st07-GRP-IT
Karim Haddad
Thomas Roux
== st07-GRP-Logistique
Léa Martin
Hugo Bernard
Sofia Moreau
Yanis Lefebvre
```
L'ordre des membres peut varier.

### Pourquoi
- La création DANS l'AU (`/administrativeUnits/{id}/members`) est la seule voie ouverte à un administrateur délégué : l'objet naît dans son périmètre.
- Le groupe dynamique filtre sur `department` ET `companyName` : la règle s'évalue sur tout le tenant, pas seulement sur l'AU.
- Script rejouable (test d'existence) : principe d'idempotence repris en M3 avec Bicep.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `Insufficient privileges to complete the operation` | `New-MgUser` utilisé au lieu de la création dans l'AU | Utiliser `New-MgDirectoryAdministrativeUnitMember` avec `@odata.type` |
| `Another object with the same value for property userPrincipalName already exists` | Script relancé sans test d'existence | Conserver le test `Get-MgUser -Filter` |
| Groupe dynamique vide | Traitement asynchrone en cours | Attendre ; portail > groupe > état de traitement de l'appartenance |
| Groupe dynamique avec 40 membres | Règle sans `companyName` : capture les autres stagiaires | Corriger `membershipRule` avec `Update-MgGroup` |
| Guillemets de la règle mal interprétés | Guillemets non échappés dans une chaîne PowerShell | Échapper avec l'accent grave `` `" `` ou utiliser des apostrophes externes |
| Mot de passe refusé | Complexité ou longueur insuffisante | 12 caractères minimum, 4 types de caractères |

### Variantes acceptables
- Création des groupes via le portail (AU-st<NN> > Groupes) si l'option de création directe y est proposée `[À VÉRIFIER]`.
- Règle `(user.department -eq "Logistique") -and (user.userPrincipalName -startsWith "st07-")` : fonctionne, mais dépend d'une convention de nommage plutôt que d'un attribut métier.
- `Invoke-MgGraphRequest -Method POST -Uri "v1.0/directory/administrativeUnits/$($au.Id)/members"` avec un corps JSON : équivalent bas niveau.

---

## Lab 01.3 ⭐ — Piloter le SSPR avec Léa Martin

### Solution
Étapes de l'énoncé. Points de contrôle :
```powershell
(Get-MgUser -UserId "st$NN-lea.martin@$Domaine" -Property employeeType).EmployeeType
```
Sortie attendue :
```
Pilote-SSPR
```

### Pourquoi
- Le SSPR « Sélectionné » n'accepte qu'UN groupe : un groupe dynamique sur un attribut permet à chaque stagiaire d'inscrire ses pilotes sans droit sur ce groupe.
- Même mécanisme en entreprise : l'inscription au pilote suit un attribut RH, pas une demande manuelle.
- Les comptes administrateurs ont une stratégie SSPR distincte, toujours active et plus stricte (deux méthodes, pas de questions de sécurité) : ne pas tester le SSPR avec son compte `st<NN>`.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Léa absente de `GRP-SSPR-Pilote` après 10 min | Traitement dynamique lent, ou `employeeType` mal orthographié | Vérifier la valeur exacte `Pilote-SSPR` ; poursuivre le lab, revenir à l'étape 5 plus tard |
| Pas de demande d'inscription à la connexion de Léa | Léa pas encore dans le groupe pilote | Attendre l'appartenance, se reconnecter |
| « Votre compte n'est pas activé pour la réinitialisation » | Idem | Idem |
| Demande d'Authenticator pour Léa | Stratégie d'accès conditionnel active (et non en rapport uniquement) | Formatrice : repasser la stratégie de démonstration en Rapport uniquement |
| Journal d'audit vide | Délai d'ingestion (jusqu'à 15 min) ou libellé du service différent `[À VÉRIFIER]` | Attendre ; filtrer dans le portail sur la catégorie « UserManagement » |

---

## Défi 01.4 ⭐⭐⭐ — Mobilité, départ et partenaire externe

### Solution
```powershell
# 1. Mobilité : Hugo Bernard passe en IT
$hugo = Get-MgUser -UserId "st$NN-hugo.bernard@$Domaine"
Update-MgUser -UserId $hugo.Id -Department "IT" -JobTitle "Technicien IT"
$it = Get-MgGroup -Filter "displayName eq 'st$NN-GRP-IT'"
New-MgGroupMember -GroupId $it.Id -DirectoryObjectId $hugo.Id
# Vérification après traitement dynamique
$log = Get-MgGroup -Filter "displayName eq 'st$NN-GRP-Logistique'"
(Get-MgGroupMember -GroupId $log.Id -All).Id -contains $hugo.Id    # attendu : False
```

```powershell
# 2. Départ de Karim Haddad
$karim = Get-MgUser -UserId "st$NN-karim.haddad@$Domaine"
$karimId = $karim.Id                                       # conservé pour la restauration
Update-MgUser -UserId $karimId -AccountEnabled:$false
Revoke-MgUserSignInSession -UserId $karimId | Out-Null
Get-MgUserMemberOf -UserId $karimId -All |
    Where-Object {
        $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' -and
        $_.AdditionalProperties.groupTypes -notcontains 'DynamicMembership'
    } |
    ForEach-Object { Remove-MgGroupMemberByRef -GroupId $_.Id -DirectoryObjectId $karimId }
$aleatoire = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
Update-MgUser -UserId $karimId -PasswordProfile @{ password = $aleatoire; forceChangePasswordNextSignIn = $true }
Remove-MgUser -UserId $karimId
```

```powershell
# 3. Restauration
Restore-MgDirectoryDeletedItem -DirectoryObjectId $karimId | Out-Null
Get-MgUser -UserId $karimId -Property userPrincipalName,accountEnabled,department |
    Format-List UserPrincipalName, AccountEnabled, Department
Get-MgUserMemberOf -UserId $karimId -All | ForEach-Object { $_.AdditionalProperties.displayName }
```
Sortie attendue (extrait) :
```
UserPrincipalName : st07-karim.haddad@arveoformation.onmicrosoft.com
AccountEnabled    : False
Department        : IT
```
Si `$karimId` est perdu : `Get-MgDirectoryDeletedItemAsUser -All | Where-Object UserPrincipalName -like "*st$NN-karim.haddad*"` (l'UPN d'un utilisateur supprimé est préfixé par son ID).

Constats attendus :
- Attributs, UPN et état bloqué : restaurés à l'identique.
- Groupes attribués : aucun, ils ont été retirés AVANT la suppression (choix volontaire, traçable dans l'audit).
- Groupes dynamiques : recalculés selon les attributs.
- Appartenance à `AU-st<NN>` et droit de restauration par un administrateur délégué : `[À VÉRIFIER]` lors du test J-1. Si l'utilisateur restauré n'est plus dans l'AU, le stagiaire ne peut plus le gérer : la formatrice le rattache. Constat pédagogique : la délégation dépend de l'appartenance à l'AU.

```powershell
# 4. Partenaire TransAlpes
$invite = New-MgInvitation -InvitedUserEmailAddress "<EMAIL_EXTERNE>" `
    -InvitedUserDisplayName "TransAlpes - Contact st$NN" `
    -InviteRedirectUrl "https://myapplications.microsoft.com" -SendInvitationMessage:$true
$part = New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter @{
    "@odata.type"   = "#microsoft.graph.group"
    displayName     = "st$NN-GRP-Partenaires"
    description     = "Arvéo - partenaires externes (B2B)"
    mailEnabled     = $false
    mailNickname    = "st$NN-grp-partenaires"
    securityEnabled = $true
}
New-MgGroupMember -GroupId $part.Id -DirectoryObjectId $invite.InvitedUser.Id
Get-MgUser -UserId $invite.InvitedUser.Id -Property userType,displayName | Format-List DisplayName, UserType
```
Sortie attendue :
```
DisplayName : TransAlpes - Contact st07
UserType    : Guest
```

```powershell
# 5. Preuve : export de l'audit du jour
$moi = (Get-MgContext).Account
$jour = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Get-MgAuditLogDirectoryAudit -All `
    -Filter "initiatedBy/user/userPrincipalName eq '$moi' and activityDateTime ge ${jour}T00:00:00Z" |
    Select-Object ActivityDateTime, ActivityDisplayName,
        @{ n = 'Cible'; e = { ($_.TargetResources | ForEach-Object { $_.UserPrincipalName ?? $_.DisplayName }) -join ';' } },
        Result |
    Export-Csv "./audit-st$NN.csv" -NoTypeInformation -Encoding utf8
Import-Csv "./audit-st$NN.csv" | Group-Object ActivityDisplayName | Select-Object Count, Name
```
Sortie attendue (extrait, libellés d'activité en anglais quelle que soit la langue du portail) :
```
Count Name
----- ----
   10 Add user
    3 Add group
    6 Add member to group
    4 Update user
    1 Delete user
    1 Restore user
    1 Invite external user
```

### Pourquoi
- Bloquer et révoquer d'abord : la suppression seule ne coupe pas immédiatement les jetons déjà émis ; `Revoke-MgUserSignInSession` invalide les jetons d'actualisation.
- Retirer les groupes attribués avant suppression : évite une restauration avec des droits que la personne ne devrait plus avoir.
- La restauration conserve l'état bloqué : réactivation = décision explicite, pas un effet de bord.
- L'export d'audit fournit la preuve exigée par un auditeur ou la DRH.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Hugo toujours dans `st<NN>-GRP-Logistique` | Traitement dynamique en cours | Attendre, relancer la vérification |
| `Remove-MgGroupMemberByRef` échoue sur un groupe | Tentative sur un groupe dynamique ou hors AU | Filtrer les groupes dynamiques (voir script) |
| `Restore-MgDirectoryDeletedItem` refusé | Droit de restauration non couvert par le scope AU `[À VÉRIFIER]` | Restauration par la formatrice, constat noté |
| Invitation refusée | Paramètres de collaboration externe restrictifs | Vérifier avec la formatrice les paramètres d'invitation du tenant |
| Export d'audit vide | Délai d'ingestion ou filtre de date en heure locale | Utiliser l'heure UTC (voir script), attendre 15 min |

### Variantes acceptables
- Blocage et suppression depuis le portail : acceptés si l'ordre bloquer → révoquer → retirer → supprimer est respecté (bouton **Révoquer les sessions** de la fiche utilisateur).
- Export d'audit depuis le portail (Journaux d'audit > Télécharger) filtré sur « Initié par ».

---

## Bonus

```powershell
function Invoke-ArveoLeaver {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [string]$Prefixe = "st$NN-"
    )
    if (-not $UserPrincipalName.StartsWith($Prefixe)) {
        throw "Refus : $UserPrincipalName hors du périmètre $Prefixe"
    }
    $rapport = [System.Collections.Generic.List[object]]::new()
    $user = Get-MgUser -UserId $UserPrincipalName
    $etapes = [ordered]@{
        'Blocage de la connexion'  = { Update-MgUser -UserId $user.Id -AccountEnabled:$false }
        'Révocation des sessions'  = { Revoke-MgUserSignInSession -UserId $user.Id | Out-Null }
        'Retrait des groupes'      = {
            Get-MgUserMemberOf -UserId $user.Id -All |
                Where-Object {
                    $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' -and
                    $_.AdditionalProperties.groupTypes -notcontains 'DynamicMembership'
                } |
                ForEach-Object { Remove-MgGroupMemberByRef -GroupId $_.Id -DirectoryObjectId $user.Id }
        }
        'Mot de passe aléatoire'   = {
            $p = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
            Update-MgUser -UserId $user.Id -PasswordProfile @{ password = $p; forceChangePasswordNextSignIn = $true }
        }
    }
    foreach ($nom in $etapes.Keys) {
        if ($PSCmdlet.ShouldProcess($UserPrincipalName, $nom)) {
            try   { & $etapes[$nom]; $statut = 'OK' }
            catch { $statut = "ÉCHEC : $($_.Exception.Message)" }
        }
        else { $statut = 'Simulé (WhatIf)' }
        $rapport.Add([pscustomobject]@{ Utilisateur = $UserPrincipalName; Action = $nom; Statut = $statut })
    }
    $rapport
}

Invoke-ArveoLeaver -UserPrincipalName "st$NN-camille.fontaine@$Domaine" -WhatIf
```
Sortie attendue (extrait, une ligne par action) :
```
What if: Performing the operation "Blocage de la connexion" on target "st07-camille.fontaine@arveoformation.onmicrosoft.com".
```
Puis un rapport de 4 lignes dont la colonne `Statut` vaut `Simulé (WhatIf)`.

La suppression reste volontairement hors de la fonction : décision distincte, après validation RH.

---

## QCM — Réponses
1. **A** — Un abonnement fait confiance à un seul tenant ; un tenant peut porter plusieurs abonnements.
2. **B** — Microsoft Entra Domain Services fournit LDAP, Kerberos et NTLM managés ; Entra ID utilise OAuth 2.0, OIDC et SAML.
3. **B** — Les groupes dynamiques d'utilisateurs nécessitent Entra ID P1 (ou P2, qui l'inclut).
4. **B** — Pour un utilisateur synchronisé, AD DS reste la source d'autorité : la modification dans Entra ID est refusée ou écrasée.
5. **B** — Le rôle est limité au scope AU-st07 ; créer une AU ou modifier le SSPR relève de rôles au scope tenant.
6. **B** — Les VMs relèvent du RBAC Azure (Propriétaire, Contributeur) ; les rôles Entra portent sur les identités.
7. **B** — Bloquer et révoquer coupe l'accès immédiatement ; supprimer seul ne révoque pas les jetons déjà émis.
8. **B** — Le mode Rapport uniquement évalue et journalise la stratégie sans l'appliquer.
