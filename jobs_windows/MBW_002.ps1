# MBW_002 - WEF_MBW_BLD_DOWNLOAD - Telechargement de l'archive ZIP Metricbeat
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$ZipPath = Join-Path $INSTALL_DIR "metricbeat.zip"

if (Test-Path $ZipPath) {
    Write-Host "[MBW_002] metricbeat.zip deja present, telechargement ignore."
} else {
    Write-Host "[MBW_002] Telechargement depuis $METRICBEAT_ZIP_URL ..."
    Invoke-WebRequest -Uri $METRICBEAT_ZIP_URL -OutFile $ZipPath
}

Write-Host "[MBW_002] OK."
exit 0
