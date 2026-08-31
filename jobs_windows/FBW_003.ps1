# FBW_003 - WEF_FBW_BLD_BININST - Extraction et enregistrement du service Filebeat
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$TargetDir = "C:\Program Files\Filebeat"

if (Get-Service -Name "filebeat" -ErrorAction SilentlyContinue) {
    Write-Host "[FBW_003] Service filebeat deja installe, ignore."
    Write-Host "[FBW_003] OK."
    exit 0
}

$ZipPath = Join-Path $INSTALL_DIR "filebeat.zip"
if (-not (Test-Path $ZipPath)) {
    Write-Host "[FBW_003] ERREUR: $ZipPath introuvable (FBW_002 doit avoir tourne)."
    exit 1
}

if (-not (Test-Path $TargetDir)) {
    Write-Host "[FBW_003] Extraction de l'archive vers $TargetDir ..."
    $ExtractTmp = Join-Path $INSTALL_DIR "filebeat_extract_tmp"
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractTmp -Force
    $ExtractedFolder = Get-ChildItem $ExtractTmp | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    Move-Item -Path $ExtractedFolder.FullName -Destination $TargetDir
    Remove-Item -Path $ExtractTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[FBW_003] Enregistrement du service Windows filebeat..."
Push-Location $TargetDir
try {
    powershell.exe -ExecutionPolicy Bypass -File ".\install-service-filebeat.ps1"
} finally {
    Pop-Location
}

if (-not (Get-Service -Name "filebeat" -ErrorAction SilentlyContinue)) {
    Write-Host "[FBW_003] ERREUR: service filebeat introuvable apres installation."
    exit 1
}

Write-Host "[FBW_003] OK."
exit 0
