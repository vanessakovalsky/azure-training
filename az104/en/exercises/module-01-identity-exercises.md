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

## Lab 01.0 ⭐ — Explore the tenant (guided)
**Duration** : 5 min · **Objective** : read how the tenant is organized before writing to it
**Context** : Arvéo's new administration team discovers its tenant.
**Prerequisites** : Lab 00.1 completed

### Steps
1. Open https://entra.microsoft.com, **Overview** menu.
   Expected result: tenant name, tenant ID, primary domain `<DOMAIN>`, Microsoft Entra ID P2 licence.
2. **Roles and administrators** > **User Administrator** > **Assignments**.
   Expected result: your `st<NN>` account listed with scope `AU-st<NN>`.
3. Display your identity from the command line (Cloud Shell Bash).
   ```bash
   az ad signed-in-user show --query "{upn:userPrincipalName, id:id}" -o table
   ```
   Expected result: your UPN `st<NN>@<DOMAIN>` and object ID.

### Success criteria
- [ ] Primary domain and tenant ID noted
- [ ] `AU-st<NN>` scope identified on your Entra roles

---

## Lab 01.1 ⭐ — Create Arvéo's management team in the portal (guided)
**Duration** : 20 min · **Objective** : create users with their attributes within a delegated scope
**Context** : Arvéo starts its migration; three key people need a cloud account.
**Prerequisites** : Lab 01.0 completed

| User | Department (`department`) | Job title (`jobTitle`) |
|---|---|---|
| Claire Dubois | Direction | Operations Director |
| Léa Martin | Logistique | Dock manager |
| Karim Haddad | IT | Systems administrator |

The `department` values stay in French: they are used by dynamic rules shared with the French version of the course.

### Steps
1. Entra admin center > **Users** > **All users** > **New user** > **Create new user**.
2. **Basics** tab:
   - User principal name: `st<NN>-claire.dubois`, domain `<DOMAIN>`
   - Display name: `Claire Dubois`
   - Password: auto-generated, **write it down**
   - Account enabled: checked
3. **Properties** tab:
   - First name `Claire`, Last name `Dubois`
   - Job title `Operations Director`, Department `Direction`
   - Company name `Arveo-st<NN>`
   - Usage location: `France`
4. **Assignments** tab > **Add administrative unit** > `AU-st<NN>` `[TO VERIFY]` exact tab label in the wizard.
5. **Review + create** > **Create**.
   Expected result: "User created" notification.
6. Repeat steps 1 to 5 for Léa Martin (`st<NN>-lea.martin`) and Karim Haddad (`st<NN>-karim.haddad`), write down their passwords.
7. Check the administrative unit content (Cloud Shell PowerShell, variables defined at the top of the module).
   ```powershell
   Get-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId $au.Id -All |
     ForEach-Object { $_.AdditionalProperties.userPrincipalName }
   ```
   Expected result:
   ```
   st07-claire.dubois@arveoformation.onmicrosoft.com
   st07-lea.martin@arveoformation.onmicrosoft.com
   st07-karim.haddad@arveoformation.onmicrosoft.com
   ```
8. Test the delegation in the portal:
   - Open `st<NN>-karim.haddad` > **Reset password**: allowed, new password displayed.
   - Open another trainee's user (e.g. `st<NN+1>-claire.dubois`): **Reset password** greyed out or denied.

### Success criteria
- [ ] 3 users `st<NN>-*` members of `AU-st<NN>`
- [ ] Attributes `department`, `jobTitle`, `companyName`, `usageLocation` filled in (check: `Get-MgUser -UserId "st$NN-lea.martin@$Domain" -Property department,jobTitle,companyName,usageLocation | Format-List department,jobTitle,companyName,usageLocation`)
- [ ] Password reset allowed in your AU, denied outside it

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
1. Create the 6 users in `AU-st<NN>` by script: UPN `st<NN>-firstname.lastname@<DOMAIN>`, capitalized display name (`Hugo Bernard`), `department`, `jobTitle`, `companyName = Arveo-st<NN>`, `usageLocation = FR`, password `<PWD>` to be changed at first sign-in.
2. Create in `AU-st<NN>` the assigned security group `st<NN>-GRP-IT` and add Karim Haddad and Thomas Roux.
3. Create in `AU-st<NN>` the dynamic security group `st<NN>-GRP-Logistique` whose rule keeps only users of the Logistique department of YOUR entity.
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
