# WAW_004 - WEF_WAW_BLD_CONFIGURE - Configuration adresse manager + nom agent
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$OssecConf = "C:\Program Files (x86)\ossec-agent\ossec.conf"

Write-Host "[WAW_004] Configuration de $OssecConf ..."

if (-not (Test-Path $OssecConf)) {
    Write-Host "[WAW_004] ERREUR: $OssecConf introuvable. wazuh-agent est-il installe (WAW_003) ?"
    exit 1
}

[xml]$xml = Get-Content $OssecConf

$serverNode = $xml.ossec_config.client.server.address
if ($serverNode) {
    $xml.ossec_config.client.server.address = $WAZUH_MANAGER_IP
}

$xml.Save($OssecConf)

Write-Host "[WAW_004] Manager = $WAZUH_MANAGER_IP, Agent name = $AGENT_NAME"
Write-Host "[WAW_004] OK."
exit 0
