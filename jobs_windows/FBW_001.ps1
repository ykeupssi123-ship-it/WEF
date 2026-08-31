# FBW_001 - WEF_FBW_BLD_PREREQ - Verification connectivite vers Logstash
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

Write-Host "[FBW_001] Test de connectivite vers Logstash ($FACTORY_HOST_IP`:$LS_BEATS_PORT)..."

$test = Test-NetConnection -ComputerName $FACTORY_HOST_IP -Port $LS_BEATS_PORT -WarningAction SilentlyContinue
if ($test.TcpTestSucceeded) {
    Write-Host "[FBW_001] Logstash joignable."
} else {
    Write-Host "[FBW_001] ERREUR: $FACTORY_HOST_IP`:$LS_BEATS_PORT non joignable (verifiez reseau/pare-feu)."
    exit 1
}

Write-Host "[FBW_001] OK."
exit 0
