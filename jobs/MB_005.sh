#!/bin/bash
# MB_005 - WEF_MB_BLD_CRYPCHK - Controle d'acces au coffre PKI (local a VM2)
# Depend de CA_DISTRIBUTED_OK (DIST_001), meme raison que FB_005.
set -uo pipefail
source "$VARS_FILE"
echo "[MB_005] Verification de presence de la CA d'usine (distribuee par DIST_001)..."
[ -f "${PKI_DIR}/factory_ca.crt" ] || { echo "[MB_005] ERREUR : ${PKI_DIR}/factory_ca.crt absent. DIST_001 doit avoir tourne avant."; exit 1; }
echo "[MB_005] OK."
exit 0
