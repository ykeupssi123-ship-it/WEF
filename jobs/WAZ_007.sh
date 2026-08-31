#!/bin/bash
# WAZ_007 - WEF_WAZ_BLD_PKICHECK - Presence des ancres PKI de l'usine
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_007] Verification de presence de la CA d'usine..."
[ -f "${PKI_DIR}/factory_ca.crt" ] || { echo "[WAZ_007] ERREUR : PKI absente."; exit 1; }
echo "[WAZ_007] OK."
exit 0
