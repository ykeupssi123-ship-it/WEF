#!/bin/bash
# PKI_010 - WEF_PKI_BLD_CLEANCSR
# Evacuation des residus de calcul ephemeres (CSR, fichier serial).
set -uo pipefail
source "$VARS_FILE"
cd "${PKI_DIR}"

echo "[PKI_010] Nettoyage des artefacts temporaires..."
rm -f factory_server.csr factory_ca.srl || true
echo "[PKI_010] OK."
exit 0
