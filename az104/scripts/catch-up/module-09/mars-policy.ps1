# mars-policy.ps1 — rattrapage du lab 09.3, exécuté SUR vm-stNN-lyon-fs (run-command, SYSTEM)
# Stratégie MARS : F:\Compta, du lundi au vendredi à 21:00, rétention 30 jours ; sauvegarde
# immédiate. Prérequis : agent inscrit (mars-lyon.sh <NN> --wait). Idempotent.
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'

$existante = $null
try { $existante = Get-OBPolicy } catch { $existante = $null }
if (-not $existante) {
  $p = New-OBPolicy
  Add-OBFileSpec -Policy $p -FileSpec (New-OBFileSpec -FileSpec @('F:\Compta')) | Out-Null
  $jours = 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'
  Set-OBSchedule -Policy $p -Schedule (New-OBSchedule -DaysOfWeek $jours -TimesOfDay 21:00) | Out-Null
  Set-OBRetentionPolicy -Policy $p -RetentionPolicy (New-OBRetentionPolicy -RetentionDays 30) | Out-Null
  Set-OBPolicy -Policy $p -Confirm:$false | Out-Null
  Write-Output 'Strategie MARS creee : F:\Compta, lundi-vendredi 21:00, 30 jours'
} else {
  Write-Output 'Strategie MARS deja presente : conservee'
}
Get-OBPolicy | Start-OBBackup | Out-Null
Get-OBJob -Previous 1 | Format-List   # [À VÉRIFIER] propriétés affichées selon la version
