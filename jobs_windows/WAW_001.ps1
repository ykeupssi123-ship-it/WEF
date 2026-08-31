# WAW_001 - WEF_WAW_BLD_PREREQ - Verification connectivite vers le manager
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

Write-Host "[WAW_001] Test de connectivite vers le manager ($WAZUH_MANAGER_IP)..."

if (Test-Connection -ComputerName $WAZUH_MANAGER_IP -Count 2 -Quiet) {
    Write-Host "[WAW_001] Manager joignable."
} else {
    Write-Host "[WAW_001] ERREUR: manager $WAZUH_MANAGER_IP non joignable (verifiez reseau/pare-feu port 1514/1515)."
    exit 1
}

Write-Host "[WAW_001] OK."
exit 0
