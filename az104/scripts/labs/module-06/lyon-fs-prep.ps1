# lyon-fs-prep.ps1 — préparation du serveur de fichiers de Lyon (module 6)
# Exécuté SUR vm-stNN-lyon-fs par une commande d'exécution managée (lyon-fs-prep.sh),
# en tant que SYSTEM, sans interaction. Idempotent : chaque étape vérifie son état.
#   1. Disque de données initialisé en F: (étiquette « Partages »)
#   2. Arborescence F:\Partages\Commun (contenu fictif du serveur de fichiers de Lyon)
#      et partage SMB « Commun »
#   3. Agent Azure File Sync (téléchargement depuis Microsoft, installation silencieuse)
#   4. Modules PowerShell Az.Accounts et Az.StorageSync (inscription du serveur)
# Prérequis : accès Internet sortant HTTPS (passerelle NAT natgw-lyon, lyon-nat.sh).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- 1. Disque de données ----------
if (-not (Get-Volume -DriveLetter F -ErrorAction SilentlyContinue)) {
  $disk = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Select-Object -First 1
  if (-not $disk) { throw 'Aucun disque RAW : disque de données non attaché' }
  Initialize-Disk -Number $disk.Number -PartitionStyle GPT
  New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter F |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Partages' -Confirm:$false | Out-Null
}
Write-Output "Volume F: $([math]::Round((Get-Volume -DriveLetter F).Size / 1GB)) Go"

# ---------- 2. Contenu du serveur de fichiers ----------
$root = 'F:\Partages\Commun'
foreach ($d in 'Exploitation', 'Qualite', 'RH') {
  New-Item -ItemType Directory -Force -Path (Join-Path $root $d) | Out-Null
}
1..12 | ForEach-Object {
  $f = Join-Path $root ('Exploitation\tournee-{0:d2}.csv' -f $_)
  if (-not (Test-Path $f)) {
    Set-Content -Path $f -Value "date;chauffeur;tournee;colis`n2026-09-$('{0:d2}' -f $_);CH$_;T$_;$(40 + $_)"
  }
}
1..5 | ForEach-Object {
  $f = Join-Path $root ('Qualite\procedure-{0:d2}.txt' -f $_)
  if (-not (Test-Path $f)) { Set-Content -Path $f -Value "Procédure qualité Arvéo n°$_" }
}
$f = Join-Path $root 'RH\organigramme-lyon.txt'
if (-not (Test-Path $f)) { Set-Content -Path $f -Value 'Organigramme du site de Lyon' }
# Fichier volumineux (100 Mo) : démonstration de la hiérarchisation cloud
$big = Join-Path $root 'Qualite\audit-2024.bin'
if (-not (Test-Path $big)) {
  $bytes = New-Object byte[] (1MB)
  (New-Object Random 42).NextBytes($bytes)
  $fs = [IO.File]::Create($big)
  1..100 | ForEach-Object { $fs.Write($bytes, 0, $bytes.Length) }
  $fs.Close()
}
if (-not (Get-SmbShare -Name Commun -ErrorAction SilentlyContinue)) {
  New-SmbShare -Name Commun -Path $root -FullAccess 'BUILTIN\Administrators' | Out-Null
}
$n = (Get-ChildItem $root -Recurse -File).Count
Write-Output "Partage \\$env:COMPUTERNAME\Commun : $n fichiers"

# ---------- 3. Agent Azure File Sync ----------
$dll = 'C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll'
if (-not (Test-Path $dll)) {
  $msi = Join-Path $env:TEMP 'StorageSyncAgent.msi'
  # Lien de téléchargement par version de Windows Server [À VÉRIFIER] sur la page de déploiement
  Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/afs/agent/Server2022' -OutFile $msi
  $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
  if ($p.ExitCode -notin 0, 3010) { throw "Installation de l'agent : code $($p.ExitCode)" }
}
$ver = (Get-ItemProperty 'C:\Program Files\Azure\StorageSyncAgent\StorageSync.Management.ServerCmdlets.dll').VersionInfo.FileVersion
Write-Output "Agent Azure File Sync : $ver"

# ---------- 4. Modules PowerShell ----------
if (-not (Get-Module -ListAvailable Az.StorageSync)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  Install-Module -Name Az.Accounts, Az.StorageSync -Scope AllUsers -Force -AllowClobber
}
$m = Get-Module -ListAvailable Az.StorageSync | Sort-Object Version -Descending | Select-Object -First 1
Write-Output "Module Az.StorageSync : $($m.Version)"
Write-Output 'PREPARATION TERMINEE'
