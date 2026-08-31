# FBW_005 - WEF_FBW_BLD_CONFIGURE - filebeat.yml (Journal Windows -> Logstash)
# Reecrit le fichier EN ENTIER a chaque execution (jamais d'ajout par
# accumulation) : rejouer ce job apres un changement de vars.ps1 ne
# laisse jamais de bloc d'une configuration precedente.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$ConfigPath = "C:\Program Files\Filebeat\filebeat.yml"
$CaPathYaml = $PKI_CA_LOCAL_PATH -replace '\\', '/'

$yaml = @"
filebeat.inputs:
  - type: winlog
    name: Application
    channel: Application
    enabled: true
  - type: winlog
    name: System
    channel: System
    enabled: true
  - type: winlog
    name: Security
    channel: Security
    enabled: true

fields:
  wef_agent_name: $AGENT_NAME
fields_under_root: true

output.logstash:
  hosts: ["${FACTORY_HOST_IP}:${LS_BEATS_PORT}"]
  ssl.certificate_authorities: ["$CaPathYaml"]
"@

Write-Host "[FBW_005] Ecriture de $ConfigPath ..."
Set-Content -Path $ConfigPath -Value $yaml -Encoding UTF8

Write-Host "[FBW_005] OK."
exit 0
