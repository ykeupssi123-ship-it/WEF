# MBW_006 - WEF_MBW_BLD_SVCSTART - Activation et demarrage du service metricbeat
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

Write-Host "[MBW_006] Demarrage du service metricbeat..."

Set-Service -Name "metricbeat" -StartupType Automatic
Restart-Service -Name "metricbeat"

Start-Sleep -Seconds 3

$svc = Get-Service -Name "metricbeat"
if ($svc.Status -ne "Running") {
    Write-Host "[MBW_006] ERREUR: metricbeat n'est pas demarre (statut: $($svc.Status))."
    exit 1
}

Write-Host "[MBW_006] metricbeat actif."
Write-Host "[MBW_006] OK."
exit 0
