# WAW_005 - WEF_WAW_BLD_SVCSTART - Activation et demarrage du service WazuhSvc
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

Write-Host "[WAW_005] Demarrage du service WazuhSvc..."

Set-Service -Name "WazuhSvc" -StartupType Automatic
Restart-Service -Name "WazuhSvc"

Start-Sleep -Seconds 3

$svc = Get-Service -Name "WazuhSvc"
if ($svc.Status -ne "Running") {
    Write-Host "[WAW_005] ERREUR: WazuhSvc n'est pas demarre (statut: $($svc.Status))."
    exit 1
}

Write-Host "[WAW_005] WazuhSvc actif."
Write-Host "[WAW_005] OK."
exit 0
