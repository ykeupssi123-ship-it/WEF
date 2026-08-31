# WAW_003 - WEF_WAW_BLD_BININST - Installation silencieuse de wazuh-agent (MSI)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$MsiPath = Join-Path $INSTALL_DIR "wazuh-agent.msi"

if (Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue) {
    Write-Host "[WAW_003] wazuh-agent deja installe, installation ignoree."
} else {
    Write-Host "[WAW_003] Installation silencieuse de wazuh-agent..."
    $installArgs = "/i `"$MsiPath`" /q WAZUH_MANAGER=`"$WAZUH_MANAGER_IP`" WAZUH_AGENT_NAME=`"$AGENT_NAME`""
    Start-Process msiexec.exe -ArgumentList $installArgs -Wait
}

if (-not (Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue)) {
    Write-Host "[WAW_003] ERREUR: service WazuhSvc introuvable apres installation."
    exit 1
}

Write-Host "[WAW_003] OK."
exit 0
