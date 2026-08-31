# FBW_006 - WEF_FBW_BLD_SVCSTART - Activation et demarrage du service filebeat
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

Write-Host "[FBW_006] Demarrage du service filebeat..."

Set-Service -Name "filebeat" -StartupType Automatic
Restart-Service -Name "filebeat"

Start-Sleep -Seconds 3

$svc = Get-Service -Name "filebeat"
if ($svc.Status -ne "Running") {
    Write-Host "[FBW_006] ERREUR: filebeat n'est pas demarre (statut: $($svc.Status))."
    exit 1
}

Write-Host "[FBW_006] filebeat actif."
Write-Host "[FBW_006] OK."
exit 0
