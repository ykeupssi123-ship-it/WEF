#!/bin/bash
# PKI_002 - WEF_PKI_BLD_DIRNEW
# Creation du coffre-fort neutre d'ancrage des cles de l'usine.
set -uo pipefail
source "$VARS_FILE"

echo "[PKI_002] Creation de ${PKI_DIR}..."
mkdir -p "${PKI_DIR}"
chown root:"${CRYPTO_GROUP}" "${PKI_DIR}"
echo "[PKI_002] OK."
exit 0
