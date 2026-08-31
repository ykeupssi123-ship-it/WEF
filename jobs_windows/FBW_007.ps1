# FBW_007 - WEF_FBW_RUN_VERIFY - Verification et rapport final
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

New-Item -ItemType Directory -Force -Path $STATE_DIR | Out-Null
$Report = Join-Path $STATE_DIR "filebeat_report_$AGENT_NAME.txt"

$svc = Get-Service -Name "filebeat"

$lines = @(
    "=================================================="
    " RAPPORT DE DEPLOIEMENT - FILEBEAT (WINDOWS)"
    "=================================================="
    "Date              : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Projet            : $PROJECT_NAME"
    "Machine           : $AGENT_NAME"
    "Cible Logstash    : ${FACTORY_HOST_IP}:${LS_BEATS_PORT}"
    "Service filebeat  : $($svc.Status)"
    "=================================================="
)

$lines | Set-Content -Path $Report
$lines | ForEach-Object { Write-Host $_ }

Write-Host "[FBW_007] Rapport ecrit dans $Report"
Write-Host "[FBW_007] OK."
exit 0
