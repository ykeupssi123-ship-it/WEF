# MBW_005 - WEF_MBW_BLD_CONFIGURE - metricbeat.yml (modules systeme -> Logstash)
# Reecrit le fichier EN ENTIER a chaque execution (jamais d'ajout par
# accumulation), meme principe que FBW_005.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$ConfigPath = "C:\Program Files\Metricbeat\metricbeat.yml"
$CaPathYaml = $PKI_CA_LOCAL_PATH -replace '\\', '/'

$yaml = @"
metricbeat.modules:
  - module: system
    metricsets:
      - cpu
      - memory
      - network
      - filesystem
      - process
    enabled: true
    period: 10s
    processes: ['.*']

fields:
  wef_agent_name: $AGENT_NAME
fields_under_root: true

output.logstash:
  hosts: ["${FACTORY_HOST_IP}:${LS_BEATS_PORT}"]
  ssl.certificate_authorities: ["$CaPathYaml"]
"@

Write-Host "[MBW_005] Ecriture de $ConfigPath ..."
Set-Content -Path $ConfigPath -Value $yaml -Encoding UTF8

Write-Host "[MBW_005] OK."
exit 0
