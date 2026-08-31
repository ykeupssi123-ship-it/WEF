#!/bin/bash
# KB_009 - WEF_KB_BLD_CRYPCHK - Controle d'acces au coffre PKI neutre
set -uo pipefail
source "$VARS_FILE"
echo "[KB_009] Verification de presence des cles de la CA d'usine..."
[ -f "${PKI_DIR}/factory_ca.crt" ] || { echo "[KB_009] ERREUR : PKI absente."; exit 1; }
echo "[KB_009] OK."
exit 0
