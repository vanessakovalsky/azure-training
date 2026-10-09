# Module 01 — Solutions

All solutions assume the variables and connection defined at the top of the exercises file:
```powershell
$NN = "07"                                    # trainee number
$Domain = "arveoformation.onmicrosoft.com"    # tenant domain
$InitialPassword = "<PWD>"                                # initial password for lab users
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","AdministrativeUnit.ReadWrite.All","AuditLog.Read.All","User.Invite.All" -UseDeviceCode -NoWelcome
$au = Get-MgDirectoryAdministrativeUnit -Filter "displayName eq 'AU-st$NN'"
```

## Lab 01.0 ⭐ — Explore the tenant

### Solution
Read-only: Entra admin center > Overview, then Roles and administrators. Check command:
```bash
az ad signed-in-user show --query "{upn:userPrincipalName, id:id}" -o table
```

### Why
Read before writing: in a shared tenant, knowing your roles AND their scope avoids misreading "access denied" errors.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Role shown without scope | "Roles and administrators" view at tenant level | Open the role > Assignments: the Scope column shows `AU-st<NN>` |
| No P2 licence in the overview | Trial not activated or not assigned | Trainer: activate the trial and rerun provisioning (licence assignment) |

---

## Lab 01.1 ⭐ — Create Arvéo's management team in the portal

### Solution
Lab steps. PowerShell equivalent (useful if the portal wizard has no Assignments tab):
```powershell
$team = @(
    @{ Login = "claire.dubois"; First = "Claire"; Last = "Dubois"; Dept = "Direction";  Title = "Operations Director" }
    @{ Login = "lea.martin";    First = "Léa";    Last = "Martin"; Dept = "Logistique"; Title = "Dock manager" }
    @{ Login = "karim.haddad";  First = "Karim";  Last = "Haddad"; Dept = "IT";         Title = "Systems administrator" }
)
foreach ($p in $team) {
    $body = @{
        "@odata.type"     = "#microsoft.graph.user"
        displayName       = "$($p.First) $($p.Last)"
        givenName         = $p.First
        surname           = $p.Last
        userPrincipalName = "st$NN-$($p.Login)@$Domain"
        mailNickname      = "st$NN-$($p.Login)"
        accountEnabled    = $true
        usageLocation     = "FR"
        department        = $p.Dept
        jobTitle          = $p.Title
        companyName       = "Arveo-st$NN"
        passwordProfile   = @{ password = $InitialPassword; forceChangePasswordNextSignIn = $true }
    }
    New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter $body | Out-Null
}
Get-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -All |
    ForEach-Object { $_.AdditionalProperties.userPrincipalName }
```
Expected output:
```
st07-claire.dubois@arveoformation.onmicrosoft.com
st07-lea.martin@arveoformation.onmicrosoft.com
st07-karim.haddad@arveoformation.onmicrosoft.com
```

### Why
- `usageLocation` is required to assign a licence: setting it at creation avoids a silent failure later.
- `companyName = Arveo-st<NN>` is the discriminator in dynamic rules (Exercise 01.2): without it, a rule on `department` would capture every trainee's users.
- The out-of-AU reset test demonstrates least privilege: same role, different scope, different result.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| "You do not have permissions" on creation | User created at tenant level, without AU assignment | Add the AU in the Assignments tab, or use the PowerShell method above |
| UPN already in use | `st<NN>` prefix forgotten or another trainee's number | Check `$NN` and the prefix |
| Generated password not noted | Wizard closed too quickly | Reset the password from the user page (delegated role on the AU) |
| Reset allowed on another trainee's user | Role assigned at tenant scope by mistake | Report to the trainer (provisioning anomaly) |

---

## Exercise 01.2 ⭐⭐ — Import the operations teams and create groups

### Solution
```powershell
# 1. Users from the CSV (replayable: skips existing accounts)
$ti = (Get-Culture).TextInfo
Import-Csv ./arveo-users.csv | ForEach-Object {
    $login = "st$NN-$($_.FirstName).$($_.LastName)"
    if (Get-MgUser -Filter "userPrincipalName eq '$login@$Domain'") {
        Write-Host "Already exists: $login"
        return
    }
    $body = @{
        "@odata.type"     = "#microsoft.graph.user"
        displayName       = "$($ti.ToTitleCase($_.FirstName)) $($ti.ToTitleCase($_.LastName))"
        givenName         = $ti.ToTitleCase($_.FirstName)
        surname           = $ti.ToTitleCase($_.LastName)
        userPrincipalName = "$login@$Domain"
        mailNickname      = $login
        accountEnabled    = $true
        usageLocation     = "FR"
        department        = $_.Department
        jobTitle          = $_.JobTitle
        companyName       = "Arveo-st$NN"
        passwordProfile   = @{ password = $InitialPassword; forceChangePasswordNextSignIn = $true }
    }
    New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter $body | Out-Null
    Write-Host "Created: $login"
}

# 2. Assigned group st<NN>-GRP-IT
$it = New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter @{
    "@odata.type"   = "#microsoft.graph.group"
    displayName     = "st$NN-GRP-IT"
    description     = "Arvéo - IT team (assigned membership)"
    mailEnabled     = $false
    mailNickname    = "st$NN-grp-it"
    securityEnabled = $true
}
foreach ($login in "karim.haddad", "thomas.roux") {
    $u = Get-MgUser -UserId "st$NN-$login@$Domain"
    New-MgGroupMember -GroupId $it.Id -DirectoryObjectId $u.Id
}

# 3. Dynamic group st<NN>-GRP-Logistique
New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter @{
    "@odata.type"                 = "#microsoft.graph.group"
    displayName                   = "st$NN-GRP-Logistique"
    description                   = "Arvéo - Logistics department (dynamic membership)"
    mailEnabled                   = $false
    mailNickname                  = "st$NN-grp-logistique"
    securityEnabled               = $true
    groupTypes                    = @("DynamicMembership")
    membershipRule                = "(user.department -eq `"Logistique`") -and (user.companyName -eq `"Arveo-st$NN`")"
    membershipRuleProcessingState = "On"
} | Out-Null

# 4. Check
foreach ($name in "st$NN-GRP-IT", "st$NN-GRP-Logistique") {
    $g = Get-MgGroup -Filter "displayName eq '$name'"
    "== $name"
    Get-MgGroupMember -GroupId $g.Id -All | ForEach-Object { $_.AdditionalProperties.displayName }
}
```
Expected output (after the dynamic rule is processed, a few minutes):
```
Created: st07-hugo.bernard
Created: st07-sofia.moreau
Created: st07-yanis.lefebvre
Created: st07-ines.garcia
Created: st07-thomas.roux
Created: st07-camille.fontaine
== st07-GRP-IT
Karim Haddad
Thomas Roux
== st07-GRP-Logistique
Léa Martin
Hugo Bernard
Sofia Moreau
Yanis Lefebvre
```
Member order may vary.

### Why
- Creation INSIDE the AU (`/administrativeUnits/{id}/members`) is the only path open to a delegated admin: the object is born within their scope.
- The dynamic group filters on `department` AND `companyName`: the rule is evaluated across the whole tenant, not only the AU.
- Replayable script (existence test): idempotence principle, revisited in M3 with Bicep.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| `Insufficient privileges to complete the operation` | `New-MgUser` used instead of creation inside the AU | Use `New-MgDirectoryAdministrativeUnitMember` with `@odata.type` |
| `Another object with the same value for property userPrincipalName already exists` | Script rerun without existence test | Keep the `Get-MgUser -Filter` test |
| Empty dynamic group | Asynchronous processing in progress | Wait; portal > group > membership processing status |
| Dynamic group with 40 members | Rule without `companyName`: captures other trainees | Fix `membershipRule` with `Update-MgGroup` |
| Rule quotes misinterpreted | Unescaped quotes in a PowerShell string | Escape with backtick `` `" `` or use outer single quotes |
| Password rejected | Insufficient complexity or length | 12 characters minimum, 4 character types |

### Acceptable variants
- Group creation in the portal (AU-st<NN> > Groups) if direct creation is offered there `[TO VERIFY]`.
- Rule `(user.department -eq "Logistique") -and (user.userPrincipalName -startsWith "st07-")`: works, but relies on a naming convention rather than a business attribute.
- `Invoke-MgGraphRequest -Method POST -Uri "v1.0/directory/administrativeUnits/$($au.Id)/members"` with a JSON body: low-level equivalent.

---

## Lab 01.3 ⭐ — Pilot SSPR with Léa Martin

### Solution
Lab steps. Checkpoint:
```powershell
(Get-MgUser -UserId "st$NN-lea.martin@$Domain" -Property employeeType).EmployeeType
```
Expected output:
```
Pilote-SSPR
```

### Why
- "Selected" SSPR accepts only ONE group: a dynamic group on an attribute lets each trainee enrol pilots without any right on that group.
- Same mechanism in the enterprise: pilot enrolment follows an HR attribute, not a manual request.
- Administrator accounts have a separate SSPR policy, always on and stricter (two methods, no security questions): do not test SSPR with your `st<NN>` account.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Léa not in `GRP-SSPR-Pilote` after 10 min | Slow dynamic processing, or `employeeType` misspelled | Check the exact value `Pilote-SSPR`; continue the lab, come back to step 5 later |
| No registration prompt when Léa signs in | Léa not yet in the pilot group | Wait for membership, sign in again |
| "Your account is not enabled for password reset" | Same | Same |
| Authenticator required for Léa | Conditional Access policy enforced (not report-only) | Trainer: set the demo policy back to Report-only |
| Empty audit log | Ingestion delay (up to 15 min) or different service label `[TO VERIFY]` | Wait; filter in the portal on category "UserManagement" |

---

## Challenge 01.4 ⭐⭐⭐ — Mover, leaver and external partner

### Solution
```powershell
# 1. Mover: Hugo Bernard moves to IT
$hugo = Get-MgUser -UserId "st$NN-hugo.bernard@$Domain"
Update-MgUser -UserId $hugo.Id -Department "IT" -JobTitle "IT technician"
$it = Get-MgGroup -Filter "displayName eq 'st$NN-GRP-IT'"
New-MgGroupMember -GroupId $it.Id -DirectoryObjectId $hugo.Id
# Check after dynamic processing
$log = Get-MgGroup -Filter "displayName eq 'st$NN-GRP-Logistique'"
(Get-MgGroupMember -GroupId $log.Id -All).Id -contains $hugo.Id    # expected: False
```

```powershell
# 2. Leaver: Karim Haddad
$karim = Get-MgUser -UserId "st$NN-karim.haddad@$Domain"
$karimId = $karim.Id                                       # kept for the restore
Update-MgUser -UserId $karimId -AccountEnabled:$false
Revoke-MgUserSignInSession -UserId $karimId | Out-Null
Get-MgUserMemberOf -UserId $karimId -All |
    Where-Object {
        $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' -and
        $_.AdditionalProperties.groupTypes -notcontains 'DynamicMembership'
    } |
    ForEach-Object { Remove-MgGroupMemberByRef -GroupId $_.Id -DirectoryObjectId $karimId }
$random = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
Update-MgUser -UserId $karimId -PasswordProfile @{ password = $random; forceChangePasswordNextSignIn = $true }
Remove-MgUser -UserId $karimId
```

```powershell
# 3. Restore
Restore-MgDirectoryDeletedItem -DirectoryObjectId $karimId | Out-Null
Get-MgUser -UserId $karimId -Property userPrincipalName,accountEnabled,department |
    Format-List UserPrincipalName, AccountEnabled, Department
Get-MgUserMemberOf -UserId $karimId -All | ForEach-Object { $_.AdditionalProperties.displayName }
```
Expected output (excerpt):
```
UserPrincipalName : st07-karim.haddad@arveoformation.onmicrosoft.com
AccountEnabled    : False
Department        : IT
```
If `$karimId` is lost: `Get-MgDirectoryDeletedItemAsUser -All | Where-Object UserPrincipalName -like "*st$NN-karim.haddad*"` (a deleted user's UPN is prefixed with its ID).

Expected observations:
- Attributes, UPN and blocked state: restored as they were.
- Assigned groups: none, they were removed BEFORE deletion (deliberate choice, traceable in the audit log).
- Dynamic groups: recalculated from attributes.
- `AU-st<NN>` membership and restore right for a delegated admin: `[TO VERIFY]` during the D-1 test. If the restored user is no longer in the AU, the trainee can no longer manage it: the trainer re-adds it. Teaching point: delegation depends on AU membership.

```powershell
# 4. TransAlpes partner
$invite = New-MgInvitation -InvitedUserEmailAddress "<EXTERNAL_EMAIL>" `
    -InvitedUserDisplayName "TransAlpes - Contact st$NN" `
    -InviteRedirectUrl "https://myapplications.microsoft.com" -SendInvitationMessage:$true
$part = New-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -BodyParameter @{
    "@odata.type"   = "#microsoft.graph.group"
    displayName     = "st$NN-GRP-Partenaires"
    description     = "Arvéo - external partners (B2B)"
    mailEnabled     = $false
    mailNickname    = "st$NN-grp-partenaires"
    securityEnabled = $true
}
New-MgGroupMember -GroupId $part.Id -DirectoryObjectId $invite.InvitedUser.Id
Get-MgUser -UserId $invite.InvitedUser.Id -Property userType,displayName | Format-List DisplayName, UserType
```
Expected output:
```
DisplayName : TransAlpes - Contact st07
UserType    : Guest
```

```powershell
# 5. Evidence: export today's audit
$me = (Get-MgContext).Account
$day = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Get-MgAuditLogDirectoryAudit -All `
    -Filter "initiatedBy/user/userPrincipalName eq '$me' and activityDateTime ge ${day}T00:00:00Z" |
    Select-Object ActivityDateTime, ActivityDisplayName,
        @{ n = 'Target'; e = { ($_.TargetResources | ForEach-Object { $_.UserPrincipalName ?? $_.DisplayName }) -join ';' } },
        Result |
    Export-Csv "./audit-st$NN.csv" -NoTypeInformation -Encoding utf8
Import-Csv "./audit-st$NN.csv" | Group-Object ActivityDisplayName | Select-Object Count, Name
```
Expected output (excerpt):
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

### Why
- Block and revoke first: deletion alone does not immediately invalidate tokens already issued; `Revoke-MgUserSignInSession` invalidates refresh tokens.
- Remove assigned groups before deletion: avoids a restore with rights the person should no longer have.
- Restore keeps the blocked state: re-enabling is an explicit decision, not a side effect.
- The audit export provides the evidence required by an auditor or HR.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Hugo still in `st<NN>-GRP-Logistique` | Dynamic processing in progress | Wait, rerun the check |
| `Remove-MgGroupMemberByRef` fails on a group | Attempt on a dynamic group or a group outside the AU | Filter out dynamic groups (see script) |
| `Restore-MgDirectoryDeletedItem` denied | Restore right not covered by the AU scope `[TO VERIFY]` | Restore by the trainer, observation noted |
| Invitation denied | Restrictive external collaboration settings | Check the tenant's invitation settings with the trainer |
| Empty audit export | Ingestion delay or date filter in local time | Use UTC (see script), wait 15 min |

### Acceptable variants
- Block and delete from the portal: accepted if the order block → revoke → remove → delete is respected (**Revoke sessions** button on the user page).
- Audit export from the portal (Audit logs > Download) filtered on "Initiated by".

---

## Bonus

```powershell
function Invoke-ArveoLeaver {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [string]$Prefix = "st$NN-"
    )
    if (-not $UserPrincipalName.StartsWith($Prefix)) {
        throw "Refused: $UserPrincipalName outside scope $Prefix"
    }
    $report = [System.Collections.Generic.List[object]]::new()
    $user = Get-MgUser -UserId $UserPrincipalName
    $steps = [ordered]@{
        'Block sign-in'        = { Update-MgUser -UserId $user.Id -AccountEnabled:$false }
        'Revoke sessions'      = { Revoke-MgUserSignInSession -UserId $user.Id | Out-Null }
        'Remove from groups'   = {
            Get-MgUserMemberOf -UserId $user.Id -All |
                Where-Object {
                    $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' -and
                    $_.AdditionalProperties.groupTypes -notcontains 'DynamicMembership'
                } |
                ForEach-Object { Remove-MgGroupMemberByRef -GroupId $_.Id -DirectoryObjectId $user.Id }
        }
        'Random password'      = {
            $p = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
            Update-MgUser -UserId $user.Id -PasswordProfile @{ password = $p; forceChangePasswordNextSignIn = $true }
        }
    }
    foreach ($name in $steps.Keys) {
        if ($PSCmdlet.ShouldProcess($UserPrincipalName, $name)) {
            try   { & $steps[$name]; $status = 'OK' }
            catch { $status = "FAILED: $($_.Exception.Message)" }
        }
        else { $status = 'Simulated (WhatIf)' }
        $report.Add([pscustomobject]@{ User = $UserPrincipalName; Action = $name; Status = $status })
    }
    $report
}

Invoke-ArveoLeaver -UserPrincipalName "st$NN-camille.fontaine@$Domain" -WhatIf
```
Expected output (excerpt, one line per action):
```
What if: Performing the operation "Block sign-in" on target "st07-camille.fontaine@arveoformation.onmicrosoft.com".
```
Then a 4-line report whose `Status` column is `Simulated (WhatIf)`.

Deletion deliberately stays outside the function: a separate decision, after HR approval.

---

## Quiz (QCM) — Answers
1. **A** — A subscription trusts a single tenant; a tenant can hold several subscriptions.
2. **B** — Microsoft Entra Domain Services provides managed LDAP, Kerberos and NTLM; Entra ID uses OAuth 2.0, OIDC and SAML.
3. **B** — Dynamic user groups require Entra ID P1 (or P2, which includes it).
4. **B** — For a synchronized user, AD DS remains the source of authority: the change in Entra ID is denied or overwritten.
5. **B** — The role is limited to the AU-st07 scope; creating an AU or changing SSPR requires tenant-scoped roles.
6. **B** — VMs fall under Azure RBAC (Owner, Contributor); Entra roles cover identities.
7. **B** — Blocking and revoking cuts access immediately; deleting alone does not revoke tokens already issued.
8. **B** — Report-only mode evaluates and logs the policy without enforcing it.
