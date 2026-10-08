# Module 00 — Exercises

Variables used in this module:
- `<NN>` = two-digit trainee number, provided by the trainer (e.g. `07`)
- `<DOMAIN>` = training tenant domain, provided by the trainer (e.g. `arveoformation.onmicrosoft.com`)
- `<TEMPORARY_PASSWORD>` = password handed out by the trainer

## Levels and markers

| Marker | Meaning |
|---|---|
| ⭐ | **Guided**: detailed steps, ready-to-use commands |
| ⭐⭐ | **Semi-autonomous**: objective and hints provided, commands to build |
| ⭐⭐⭐ | **Autonomous**: objective only, commands and architecture to design |
| 🔸 **Optional** | The catch-up script shown below the title creates the same resources; complete the exercise independently if you finish early |
| 🚀 **Bonus** | Optional further exploration; does not block any following module |

## Lab 00.1 ⭐ — First sign-in and permission check (guided)
**Duration** : 20 min · **Objective** : sign in to the Azure portal with MFA, open Cloud Shell and check one's scope
**Context** : first day of Arvéo's Azure administration team; accounts were created by the trainer.
**Prerequisites** : smartphone with Microsoft Authenticator installed, recent browser, credentials from the trainer

### Steps
1. Open a private browsing window and go to https://portal.azure.com.
   Sign in with `st<NN>@<DOMAIN>` and `<TEMPORARY_PASSWORD>`.
   Expected result: password change prompt.

2. Set a new password (12 characters minimum, keep it for the 4 days).
   Expected result: "More information required" screen.

3. Follow the registration wizard: add Microsoft Authenticator, scan the QR code, approve the test notification.
   Expected result: Azure portal home page.

4. Open Cloud Shell (`>_` icon in the top bar), choose **Bash**, then the no-storage-account option (ephemeral session) `[TO VERIFY]` exact label of the option.
   Expected result: prompt `st<NN> [ ~ ]$` (or similar).

5. Check the sign-in context.
   ```bash
   az account show --query "{subscription:name, user:user.name, tenant:tenantId}" -o table
   ```
   Expected result:
   ```
   Subscription        User                                     Tenant
   ------------------  ---------------------------------------  ------------------------------------
   <SUBSCRIPTION_NAME> st07@arveoformation.onmicrosoft.com      <TENANT_ID>
   ```

6. List your resource groups.
   ```bash
   NN=<NN>
   az group list --query "[?starts_with(name, 'rg-st${NN}-')].{name:name, region:location}" -o table
   ```
   Expected result (6 lines):
   ```
   Name           Region
   -------------  -------------
   rg-st07-app    francecentral
   rg-st07-data   francecentral
   rg-st07-hub    francecentral
   rg-st07-lyon   francecentral
   rg-st07-shared francecentral
   rg-st07-spoke  francecentral
   ```

7. Check your Azure role assignments.
   ```bash
   az role assignment list --assignee "st${NN}@<DOMAIN>" --all \
     --query "[].{role:roleDefinitionName, scope:scope}" -o table
   ```
   Expected result: 8 lines — 6 × `Owner` on `rg-st<NN>-*`, 1 × `Reader` on the subscription, 1 × `Network Contributor` on `NetworkWatcherRG`.

8. Switch Cloud Shell to **PowerShell** (Cloud Shell toolbar menu), then connect to Microsoft Graph.
   ```powershell
   $NN = "<NN>"
   Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","AdministrativeUnit.ReadWrite.All" -UseDeviceCode -NoWelcome
   ```
   Expected result: a code to enter at https://microsoft.com/devicelogin, then back to the prompt without error.

9. Check your administrative unit.
   ```powershell
   Get-MgDirectoryAdministrativeUnit -Filter "displayName eq 'AU-st$NN'" | Select-Object DisplayName, Id
   ```
   Expected result:
   ```
   DisplayName Id
   ----------- --
   AU-st07     5b0c2e1a-8f3d-4c6b-9a71-2d4e6f8a1b3c
   ```

### Success criteria
- [ ] Azure portal sign-in with MFA working
- [ ] `az account show` displays your own `st<NN>` account
- [ ] 6 resource groups `rg-st<NN>-*` listed
- [ ] 8 Azure role assignments visible
- [ ] `Connect-MgGraph` without an admin approval prompt, `AU-st<NN>` found

---

## Bonus 🚀
Explore the Microsoft Entra admin center (https://entra.microsoft.com): without changing anything, find the tenant's primary domain, the number of Entra ID P2 licences available and your own Entra roles (**Roles and administrators** menu).
