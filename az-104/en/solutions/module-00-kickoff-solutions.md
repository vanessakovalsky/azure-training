# Module 00 — Solutions

## Lab 00.1 ⭐ — First sign-in and permission check

### Solution
The commands in the lab are the solution. Summary of checks:

```bash
NN=07
az account show --query "{subscription:name, user:user.name}" -o table
az group list --query "[?starts_with(name, 'rg-st${NN}-')].name" -o tsv | wc -l
```
Expected output:
```
Subscription        User
------------------  -----------------------------------
<SUBSCRIPTION_NAME> st07@arveoformation.onmicrosoft.com
6
```

```powershell
$NN = "07"
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","AdministrativeUnit.ReadWrite.All" -UseDeviceCode -NoWelcome
(Get-MgContext).Scopes
```
Expected output: a list containing at least `User.ReadWrite.All`, `Group.ReadWrite.All`, `AdministrativeUnit.ReadWrite.All`.

### Why
- The **Reader** role on the subscription is why `az group list` also returns other trainees' resource groups: the JMESPath `starts_with` filter isolates your own scope.
- The admin consent granted by the trainer (provisioning script) avoids the "Admin approval required" screen on `Connect-MgGraph`.
- Actual permissions remain those of the trainee's Entra roles: the `User.ReadWrite.All` consent only allows changes to users in `AU-st<NN>`.

### Common errors
| Symptom | Cause | Fix |
|---|---|---|
| Sign-in loop | Another Microsoft account session in the browser | Private browsing window |
| "More information required" cannot be completed | No smartphone or Authenticator not installed | Install Authenticator; otherwise SMS if allowed by the trainer |
| `az group list` empty | Wrong default subscription or RBAC assignment not yet replicated | `az account set --subscription "<SUBSCRIPTION_NAME>"`, wait 5 min, `az login` again |
| "Need admin approval" on `Connect-MgGraph` | Graph consent not granted in the tenant | Trainer: rerun `provision-stagiaires.ps1` (consent section) |
| `Get-MgDirectoryAdministrativeUnit` empty | Wrong `$NN` value (e.g. `7` instead of `07`) | `$NN = "07"` with the leading zero |
| Cloud Shell asks for a storage account | Ephemeral session option not selected | Choose the no-storage option, or create the storage in `rg-st<NN>-shared` |
