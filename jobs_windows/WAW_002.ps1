# WAW_002 - WEF_WAW_BLD_DOWNLOAD - Telechargement du package MSI wazuh-agent
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$MsiPath = Join-Path $INSTALL_DIR "wazuh-agent.msi"

if (Test-Path $MsiPath) {
    Write-Host "[WAW_002] wazuh-agent.msi deja present, telechargement ignore."
} else {
    Write-Host "[WAW_002] Telechargement depuis $WAZUH_AGENT_MSI_URL ..."
    Invoke-WebRequest -Uri $WAZUH_AGENT_MSI_URL -OutFile $MsiPath
}

Write-Host "[WAW_002] OK."
exit 0
