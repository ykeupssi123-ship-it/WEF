#!/bin/bash
# FB_005 - WEF_FB_BLD_CRYPCHK - Controle d'acces au coffre PKI (local a VM2)
# Depend desormais de CA_DISTRIBUTED_OK (job DIST_001) en plus de FB_BIN_OK :
# sur VM2, ce coffre n'existe que parce que DIST_001 l'a copie depuis VM1.
set -uo pipefail
source "$VARS_FILE"
echo "[FB_005] Verification de presence de la CA d'usine (distribuee par DIST_001)..."
[ -f "${PKI_DIR}/factory_ca.crt" ] || { echo "[FB_005] ERREUR : ${PKI_DIR}/factory_ca.crt absent. DIST_001 doit avoir tourne avant."; exit 1; }
echo "[FB_005] OK."
exit 0
