# MBW_003 - WEF_MBW_BLD_BININST - Extraction et enregistrement du service Metricbeat
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$TargetDir = "C:\Program Files\Metricbeat"

if (Get-Service -Name "metricbeat" -ErrorAction SilentlyContinue) {
    Write-Host "[MBW_003] Service metricbeat deja installe, ignore."
    Write-Host "[MBW_003] OK."
    exit 0
}

$ZipPath = Join-Path $INSTALL_DIR "metricbeat.zip"
if (-not (Test-Path $ZipPath)) {
    Write-Host "[MBW_003] ERREUR: $ZipPath introuvable (MBW_002 doit avoir tourne)."
    exit 1
}

if (-not (Test-Path $TargetDir)) {
    Write-Host "[MBW_003] Extraction de l'archive vers $TargetDir ..."
    $ExtractTmp = Join-Path $INSTALL_DIR "metricbeat_extract_tmp"
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractTmp -Force
    $ExtractedFolder = Get-ChildItem $ExtractTmp | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    Move-Item -Path $ExtractedFolder.FullName -Destination $TargetDir
    Remove-Item -Path $ExtractTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[MBW_003] Enregistrement du service Windows metricbeat..."
Push-Location $TargetDir
try {
    powershell.exe -ExecutionPolicy Bypass -File ".\install-service-metricbeat.ps1"
} finally {
    Pop-Location
}

if (-not (Get-Service -Name "metricbeat" -ErrorAction SilentlyContinue)) {
    Write-Host "[MBW_003] ERREUR: service metricbeat introuvable apres installation."
    exit 1
}

Write-Host "[MBW_003] OK."
exit 0
