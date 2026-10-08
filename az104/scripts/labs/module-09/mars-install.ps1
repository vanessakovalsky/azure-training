# mars-install.ps1 — exécuté SUR vm-stNN-lyon-fs (commande d'exécution managée « mars-install »,
# compte SYSTEM), lancé par mars-lyon.sh. Ne pas exécuter à la main.
#   1. Dossier F:\Compta : 6 exports comptables (dossier NON synchronisé par Azure File Sync)
#   2. Téléchargement et installation silencieuse de l'agent MARS (sortie Internet : natgw-lyon)
#   3. Modules Az.Accounts et Az.RecoveryServices (connexion par l'identité managée du serveur)
#   4. Identifiants du coffre générés par l'identité managée (rôle Contributeur de sauvegarde
#      sur le coffre), inscription du serveur, phrase secrète de chiffrement
# Idempotent : agent installé et serveur inscrit conservés (marqueur C:\Arveo\mars\inscrit.txt).
param(
  [Parameter(Mandatory = $true)][string]$SubscriptionId,
  [Parameter(Mandatory = $true)][string]$ResourceGroup,
  [Parameter(Mandatory = $true)][string]$VaultName,
  [Parameter(Mandatory = $true)][string]$Passphrase
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$work   = 'C:\Arveo\mars'
$agent  = 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\cbengine.exe'
$module = 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'
$marker = Join-Path $work 'inscrit.txt'
New-Item -ItemType Directory -Force -Path $work, 'F:\Compta', 'F:\Restauration' | Out-Null

# 1. Exports comptables de l'ancienne application de Lyon
foreach ($jour in 25..30) {
  $f = "F:\Compta\export-2026-09-$jour.csv"
  if (-not (Test-Path $f)) {
    $lignes = @(
      'date;compte;libelle;debit;credit',
      "2026-09-$jour;411000;Tournees Lyon Est;$(1000 + $jour * 37);0",
      "2026-09-$jour;706000;Prestations transport;0;$(1000 + $jour * 37)"
    )
    Set-Content -Path $f -Value $lignes -Encoding UTF8
  }
}

# 2. Agent MARS (lien de téléchargement officiel [À VÉRIFIER] : https://aka.ms/azurebackup_agent)
if (-not (Test-Path $agent)) {
  $setup = Join-Path $work 'MARSAgentInstaller.exe'
  Invoke-WebRequest -Uri 'https://aka.ms/azurebackup_agent' -OutFile $setup -UseBasicParsing
  # /q : silencieux ; /nu : pas de recherche de mises à jour Microsoft Update
  $p = Start-Process -FilePath $setup -ArgumentList '/q', '/nu' -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "Installation de l'agent MARS : code de sortie $($p.ExitCode)" }
}

# 3. Modules Az (fournisseur NuGet déjà présent depuis le module 6, réinstallé si besoin)
foreach ($m in 'Az.Accounts', 'Az.RecoveryServices') {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }
    Install-Module -Name $m -Scope AllUsers -Force -AllowClobber -Repository PSGallery
  }
}

# 4. Inscription auprès du coffre
if (-not (Test-Path $marker)) {
  Import-Module Az.Accounts, Az.RecoveryServices
  Connect-AzAccount -Identity -Subscription $SubscriptionId | Out-Null
  $vault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroup -Name $VaultName
  # Identifiants du coffre (fichier .VaultCredentials, valable 10 jours, usage unique ici)
  $cred = Get-AzRecoveryServicesVaultSettingsFile -Backup -Vault $vault -Path $work
  Import-Module $module
  Start-OBRegistration -VaultCredentials $cred.FilePath -Confirm:$false | Out-Null
  $secure = ConvertTo-SecureString -String $Passphrase -AsPlainText -Force
  # [À VÉRIFIER] paramètre -SecurityPin exigé ou non selon la version de l'agent
  Set-OBMachineSetting -EncryptionPassphrase $secure | Out-Null
  Remove-Item -Path $cred.FilePath -Force
  Set-Content -Path $marker -Value $VaultName
}

# Compte rendu (lu par « mars-lyon.sh <NN> --status »)
Write-Output "Dossier F:\Compta : $((Get-ChildItem F:\Compta -File).Count) fichiers"
Write-Output "Agent MARS : $((Get-Item $agent).VersionInfo.FileVersion)"
Write-Output "Inscription : $(Get-Content $marker)"
Write-Output 'MARS PRET'
