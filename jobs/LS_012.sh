#!/bin/bash
# LS_012 - WEF_LS_BLD_CRYPCHK - Controle d'acces au coffre PKI neutre
set -uo pipefail
source "$VARS_FILE"
echo "[LS_012] Verification de presence des ancres PKI partagees..."
[ -f "${PKI_DIR}/factory_ca.crt" ] || { echo "[LS_012] ERREUR : PKI absente (jobs PKI doivent avoir tourne)."; exit 1; }
echo "[LS_012] OK."
exit 0
