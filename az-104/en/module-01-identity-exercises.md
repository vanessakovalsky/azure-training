# Module 01 — Exercises

Variables used throughout the module (define them at the start of each Cloud Shell PowerShell session):
- `<NN>` = two-digit trainee number (e.g. `07`)
- `<DOMAIN>` = tenant domain (e.g. `arveoformation.onmicrosoft.com`)
- `<PWD>` = initial password chosen for lab users (12 characters minimum, upper case, lower case, digit, symbol)

```powershell
$NN = "<NN>"
$Domain = "<DOMAIN>"
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","AdministrativeUnit.ReadWrite.All","AuditLog.Read.All","User.Invite.All" -UseDeviceCode -NoWelcome
$au = Get-MgDirectoryAdministrativeUnit -Filter "displayName eq 'AU-st$NN'"
$au.DisplayName
```
Expected result: `AU-st07` (with your number).

---

## Lab 01.1 ⭐ — Create Arvéo's management team inside your AU (guided)
**Duration** : 20 min · **Objective** : create users with their attributes within a delegated scope
**Context** : Arvéo starts its migration; three key people need a cloud account.
**Prerequisites** : Lab 01.0 completed, Cloud Shell PowerShell with the variables defined at the top of the module (`$NN`, `$Domain`, `Connect-MgGraph`, `$au`)

| User | UPN prefix | Department (`department`) | Job title (`jobTitle`) |
|---|---|---|---|
| Claire Dubois | `st<NN>-claire.dubois` | Direction | Operations Director |
| Léa Martin | `st<NN>-lea.martin` | Logistique | Dock manager |
| Karim Haddad | `st<NN>-karim.haddad` | IT | Systems administrator |

The `department` values stay in French: they are used by dynamic rules shared with the French version of the course.

> ℹ️ **Why PowerShell and not the portal wizard?** Your account is User Administrator **scoped to `AU-st<NN>`**. The portal wizard (*New user* > *Assignments* > *Add administrative unit*) creates the user first, then **adds an existing user** to the AU in a second call. Adding an existing object to an AU requires Privileged Role Administrator: the second call is denied. Microsoft Graph can **create the user directly inside the AU** in a single call (`POST /directory/administrativeUnits/{id}/members` with a full user object): this is what a delegated administrator is allowed to do.

### Steps
1. Check the AU variable from the top of the module.
   ```powershell
   $au.DisplayName
   $Domain = "Kovalibre635.onmicrosoft.com"
   $NN = "NN"   # le numéro du stagiaire, sur deux chiffres
   ```
   Expected result: `AU-st07` (with your number). If empty, rerun the block at the top of the module.

2. Create the three users.
   ```powershell
   $NN = "01"; $Domain = "Kovalibre635.onmicrosoft.com"
   $team = @(
     @{ Nick="claire.dubois"; First="Claire"; Last="Dubois"; Dept="Direction";  Title="Operations Director" }
     @{ Nick="lea.martin";    First="Léa";    Last="Martin"; Dept="Logistique"; Title="Dock manager" }
     @{ Nick="karim.haddad";  First="Karim";  Last="Haddad"; Dept="IT";         Title="Systems administrator" }
   )
   foreach ($p in $team) {
     $upn = "st$NN-$($p.Nick)@$Domain"; $pw = "Arv-" + (Get-Random -Min 100000 -Max 999999) + "-Lab!"
     Invoke-MgGraphRequest -Method POST -Uri "v1.0/users" -Body @{
       accountEnabled=$true; displayName="$($p.First) $($p.Last)"; givenName=$p.First; surname=$p.Last
       mailNickname="st$NN-$($p.Nick)"; userPrincipalName=$upn; jobTitle=$p.Title; department=$p.Dept
       companyName="Arveo-st$NN"; usageLocation="FR"
       passwordProfile=@{ password=$pw; forceChangePasswordNextSignIn=$true } } | Out-Null
     Write-Host "$upn  password: $pw"
   }
   ```
   Expected result: three lines `st07-…@<DOMAIN>  password: Arv-…-Lab!`. **Write down the three passwords** (Léa Martin's is used in Lab 01.3).

4. Check the user exist.
   ```powershell
     (Invoke-MgGraphRequest -Method GET -Uri "v1.0/users?`$filter=startswith(userPrincipalName,'st$NN-')&`$select=displayName,userPrincipalName,department,jobTitle,companyName,usageLocation").value |
     ForEach-Object { [pscustomobject]$_ } |
     Format-Table displayName, userPrincipalName, department, jobTitle, companyName, usageLocation
   ```
   Expected result:
   ```
   st07-claire.dubois@arveoformation.onmicrosoft.com
   st07-lea.martin@arveoformation.onmicrosoft.com
   st07-karim.haddad@arveoformation.onmicrosoft.com
   ```

5. Find the users in the portal: Entra admin center > **Identity** > **Roles & admins** > **Admin units** > `AU-st<NN>` > **Users**. Open `Claire Dubois` > **Properties** and check job title, department, company name and usage location.

6. Observe the portal limitation: in `AU-st<NN>` > **Users**, the **Add member** button is greyed out. Explain why in one sentence (hint: the ℹ️ note above).

7. Test the delegation in the portal:
   - Open `st<NN>-karim.haddad` > **Reset password**: allowed, new password displayed.
   - Open another trainee's user (e.g. `st<NN+1>-claire.dubois`): **Reset password** greyed out or denied.

   > ⚠️ If the trainer granted you User Administrator at **tenant** scope for this session, the second reset is **allowed**: the tenant-wide role overrides the AU boundary. Discuss with the group what this means for least privilege.

### Success criteria
- [ ] 3 users `st<NN>-*` members of `AU-st<NN>`
- [ ] Attributes `department`, `jobTitle`, `companyName`, `usageLocation` filled in, check:
  ```powershell
  Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/st$NN-lea.martin@$Domain`?`$select=department,jobTitle,companyName,usageLocation"
  ```
- [ ] Password reset allowed in your AU, denied outside it (unless tenant-wide role, see ⚠️)
- [ ] You can explain why **Add member** is greyed out for a delegated AU administrator
---

## Exercise 01.2 ⭐⭐ — Import the operations teams and create groups (semi-autonomous)
**Duration** : 25 min · **Objective** : bulk-create users and create assigned and dynamic groups in your AU
**Context** : Arvéo's IT department sends an HR export of 6 people. The Logistique group must update itself; the IT group is managed manually.

**Provided file** : create `arveo-users.csv` in Cloud Shell with this exact content.
```powershell
@"
FirstName,LastName,Department,JobTitle
hugo,bernard,Logistique,Dock team leader
sofia,moreau,Logistique,Dock operator
yanis,lefebvre,Logistique,Forklift driver
ines,garcia,Exploitation,Transport planner
thomas,roux,IT,Support technician
camille,fontaine,Finance,Accountant
"@ | Set-Content ./arveo-users.csv
```

**Task** :
1. Create the 6 users in `AU-st<NN>` by script:
```powershell
$PWD_LAB = "Arv-Import-2026!"
$tc = (Get-Culture).TextInfo
Import-Csv ./arveo-users.csv | ForEach-Object {
  $nick = "st$NN-$($_.FirstName).$($_.LastName)"
  Invoke-MgGraphRequest -Method POST -Uri "v1.0/users" -Body @{
    accountEnabled=$true
    displayName="$($tc.ToTitleCase($_.FirstName)) $($tc.ToTitleCase($_.LastName))"
    givenName=$tc.ToTitleCase($_.FirstName); surname=$tc.ToTitleCase($_.LastName)
    mailNickname=$nick; userPrincipalName="$nick@$Domain"
    department=$_.Department; jobTitle=$_.JobTitle
    companyName="Arveo-st$NN"; usageLocation="FR"
    passwordProfile=@{ password=$PWD_LAB; forceChangePasswordNextSignIn=$true }
  } | Out-Null
  Write-Host "+ $nick"
}
```
2. Create in `AU-st<NN>` the assigned security group `st<NN>-GRP-IT` and add Karim Haddad and Thomas Roux.
```powershell
$it = Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups" -Body @{
  displayName="st$NN-GRP-IT"; mailNickname="st$NN-GRP-IT"
  securityEnabled=$true; mailEnabled=$false }

foreach ($n in "karim.haddad","thomas.roux") {
  $u = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/st$NN-$n@$Domain"
  Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$($it.id)/members/`$ref" `
    -Body @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($u.id)" }
  Write-Host "+ $n -> st$NN-GRP-IT"
}
```

3. Create in `AU-st<NN>` the dynamic security group `st<NN>-GRP-Logistique` whose rule keeps only users of the Logistique department of YOUR entity.
```powershell
Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups" -Body @{
  displayName="st$NN-GRP-Logistique"; mailNickname="st$NN-GRP-Logistique"
  securityEnabled=$true; mailEnabled=$false
  groupTypes=@("DynamicMembership")
  membershipRule="(user.department -eq `"Logistique`") and (user.companyName -eq `"Arveo-st$NN`")"
  membershipRuleProcessingState="On" } | Out-Null
```
4. Check the members of both groups.

**Hints** :
- Same method as the "Create a user inside your AU" slide, inside an `Import-Csv | ForEach-Object` loop.
- `(Get-Culture).TextInfo.ToTitleCase("hugo")` returns `Hugo`.
- A group is also created with `New-MgDirectoryAdministrativeUnitMember`, `"@odata.type" = "#microsoft.graph.group"`.
- Dynamic group properties: `groupTypes`, `membershipRule`, `membershipRuleProcessingState`.
- Add a member: `New-MgGroupMember`; read: `Get-MgGroupMember`.
- Documentation: https://learn.microsoft.com/graph/api/administrativeunit-post-members and https://learn.microsoft.com/entra/identity/users/groups-dynamic-membership

**Success criteria** :
- [ ] `Get-MgDirectoryAdministrativeUnitMember` lists 9 users and 2 groups
- [ ] `st<NN>-GRP-IT` contains exactly Karim Haddad and Thomas Roux
- [ ] `st<NN>-GRP-Logistique` contains exactly Léa Martin, Hugo Bernard, Sofia Moreau, Yanis Lefebvre (processing delay possible)
- [ ] No other trainee's user in `st<NN>-GRP-Logistique`
- [ ] Replayable script kept (it will be the template for later modules)

---

## Lab 01.3 ⭐ — Pilot SSPR with Léa Martin (guided)
**Duration** : 20 min · **Objective** : enrol a pilot user in SSPR and test the reset end to end
**Context** : Arvéo rolls out SSPR to a pilot group before generalizing. Tenant settings are configured by the trainer; trainees enrol their pilots by setting an attribute.
**Prerequisites** : Lab 01.1 completed, Léa Martin's password noted

### Steps
1. Read the SSPR configuration (Global Reader role): Entra admin center > **Protection** > **Password reset** > **Properties** and **Authentication methods**.
   Expected result: SSPR enabled for **Selected** = `GRP-SSPR-Pilote`; methods Security questions and Email; 1 method required.
2. Read the pilot group rule.
   ```powershell
   $sspr = Get-MgGroup -Filter "displayName eq 'GRP-SSPR-Pilote'" -Property id,membershipRule
   $sspr.MembershipRule
   ```
   Expected result:
   ```
   (user.employeeType -eq "Pilote-SSPR")
   ```
3. Designate Léa Martin as a pilot.
   ```powershell
   Update-MgUser -UserId "st$NN-lea.martin@$Domain" -EmployeeType "Pilote-SSPR"
   ```
   Expected result: no output, no error.
4. Check her membership of the pilot group (rerun every minute if empty).
   ```powershell
   Get-MgGroupMember -GroupId $sspr.Id -All |
     Where-Object { $_.AdditionalProperties.userPrincipalName -like "st$NN-*" } |
     ForEach-Object { $_.AdditionalProperties.userPrincipalName }
   ```
   Expected result:
   ```
   st07-lea.martin@arveoformation.onmicrosoft.com
   ```
5. In a **new** private browsing window, open https://mysignins.microsoft.com/security-info and sign in as `st<NN>-lea.martin@<DOMAIN>` with the password noted in Lab 01.1.
   Expected result: forced password change, then a prompt to register security info.
6. Register **security questions** (remember the answers), then sign out.
7. Open https://passwordreset.microsoftonline.com, enter Léa's UPN and the captcha, answer the questions, set a new password.
   Expected result: "Your password has been reset" message.
8. Find the event in the audit logs.
   ```powershell
   Get-MgAuditLogDirectoryAudit -Filter "loggedByService eq 'Self-service Password Management'" -Top 50 |
     Where-Object { $_.TargetResources.UserPrincipalName -like "st$NN-*" } |
     Select-Object ActivityDateTime, ActivityDisplayName, Result
   ```
   Expected result (excerpt):
   ```
   ActivityDateTime      ActivityDisplayName              Result
   ----------------      -------------------              ------
   10/07/2026 11:58:12   Reset password (self-service)    success
   ```

### Success criteria
- [ ] Léa Martin member of `GRP-SSPR-Pilote`
- [ ] Self-service reset successful
- [ ] `Reset password (self-service)` event visible in the audit logs

---

## Challenge 01.4 ⭐⭐⭐ — Mover, leaver and external partner (autonomous)
**Duration** : 20 min · **Objective** : apply the Joiner-Mover-Leaver lifecycle and provide evidence
**Context** : Monday morning at Arvéo.
- Hugo Bernard is promoted to IT technician on the 1st of the month.
- Karim Haddad leaves the company tonight in a conflict situation: his access must be cut immediately, but his account must remain recoverable for 30 days.
- The partner carrier TransAlpes needs access to Arvéo's shared applications.

**Task** :
1. **Mover** : move Hugo Bernard to IT. Observe his automatic removal from `st<NN>-GRP-Logistique` and add him to `st<NN>-GRP-IT`.
2. **Leaver** : write a leaver script for Karim Haddad that blocks sign-in, revokes sessions, removes the user from assigned groups and sets a random password; then delete the account.
3. **HR mistake** : Karim is not leaving after all. Restore the account and observe what is kept (attributes, AU membership, groups). Write down your observations.
4. **Partner** : invite an external email address you have access to (personal address or one provided by the trainer), create the assigned group `st<NN>-GRP-Partenaires` in your AU and add the guest.
5. **Evidence** : export to CSV today's audit events initiated by your `st<NN>` account (date, activity, target, result).

**Constraints** :
- No action on any object outside your `st<NN>` scope.
- Step 2 runs in a single command (script or function), with no interactive input.

**Success criteria** :
- [ ] Hugo Bernard: `department = IT`, absent from `st<NN>-GRP-Logistique`, present in `st<NN>-GRP-IT`
- [ ] Karim Haddad restored, account still blocked (`accountEnabled = false`) pending HR decision
- [ ] Restore observations written down (what comes back, what does not)
- [ ] Guest visible with `userType = Guest` and member of `st<NN>-GRP-Partenaires`
- [ ] `audit-st<NN>.csv` file produced, containing at least creation, update, deletion and restore activities

---

## Bonus 🚀
Turn the leaver script into a reusable function `Invoke-ArveoLeaver -UserPrincipalName <UPN> [-WhatIf]` that:
- supports `-WhatIf` (no change, planned actions displayed);
- returns a report (PowerShell objects) listing each action and its result;
- refuses to run if the UPN does not start with `st<NN>-`.
