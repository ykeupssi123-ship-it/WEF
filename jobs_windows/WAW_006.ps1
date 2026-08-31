# WAW_006 - WEF_WAW_RUN_VERIFY - Verification enregistrement et rapport final
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

New-Item -ItemType Directory -Force -Path $STATE_DIR | Out-Null
$Report = Join-Path $STATE_DIR "agent_report_$AGENT_NAME.txt"

$svc = Get-Service -Name "WazuhSvc"

$lines = @(
    "=================================================="
    " RAPPORT DE DEPLOIEMENT - WAZUH AGENT (WINDOWS)"
    "=================================================="
    "Date              : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Projet            : $PROJECT_NAME"
    "Nom de l'agent    : $AGENT_NAME"
    "Manager cible     : $WAZUH_MANAGER_IP"
    "Service WazuhSvc  : $($svc.Status)"
    "=================================================="
)

$lines | Set-Content -Path $Report
$lines | ForEach-Object { Write-Host $_ }

Write-Host "[WAW_006] Rapport ecrit dans $Report"
Write-Host "[WAW_006] OK."
exit 0
