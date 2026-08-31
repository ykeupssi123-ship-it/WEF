# FBW_002 - WEF_FBW_BLD_DOWNLOAD - Telechargement de l'archive ZIP Filebeat
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$ZipPath = Join-Path $INSTALL_DIR "filebeat.zip"

if (Test-Path $ZipPath) {
    Write-Host "[FBW_002] filebeat.zip deja present, telechargement ignore."
} else {
    Write-Host "[FBW_002] Telechargement depuis $FILEBEAT_ZIP_URL ..."
    Invoke-WebRequest -Uri $FILEBEAT_ZIP_URL -OutFile $ZipPath
}

Write-Host "[FBW_002] OK."
exit 0
