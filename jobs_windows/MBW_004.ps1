# MBW_004 - WEF_MBW_BLD_PKICHECK - Verification presence du certificat CA d'usine
# Meme logique que FBW_004 : aucune generation/telechargement automatique,
# juste une verification claire.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

if (Test-Path $PKI_CA_LOCAL_PATH) {
    Write-Host "[MBW_004] Certificat CA present ($PKI_CA_LOCAL_PATH)."
} else {
    Write-Host "[MBW_004] ERREUR: $PKI_CA_LOCAL_PATH introuvable."
    Write-Host "[MBW_004] Recuperez factory_ca.crt depuis VM1 (dossier PKI_DIR du projet Linux) et deposez-le a cet emplacement, puis relancez."
    exit 1
}

Write-Host "[MBW_004] OK."
exit 0
