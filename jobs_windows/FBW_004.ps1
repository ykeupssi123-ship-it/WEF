# FBW_004 - WEF_FBW_BLD_PKICHECK - Verification presence du certificat CA d'usine
# Aucun canal automatique depuis ce kit vers VM1 : le certificat doit
# etre depose ici manuellement au prealable (voir vars.ps1). Ce job ne
# genere/telecharge rien lui-meme - il verifie et arrete clairement si
# absent, plutot que d'improviser (meme logique que PKI_MODE=external
# cote Linux).
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

if (Test-Path $PKI_CA_LOCAL_PATH) {
    Write-Host "[FBW_004] Certificat CA present ($PKI_CA_LOCAL_PATH)."
} else {
    Write-Host "[FBW_004] ERREUR: $PKI_CA_LOCAL_PATH introuvable."
    Write-Host "[FBW_004] Recuperez factory_ca.crt depuis VM1 (dossier PKI_DIR du projet Linux) et deposez-le a cet emplacement, puis relancez."
    exit 1
}

Write-Host "[FBW_004] OK."
exit 0
