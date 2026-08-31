#!/bin/bash
# MB_006 - WEF_MB_BLD_ACLREAD - Inclusion au groupe crypto partage
set -uo pipefail
source "$VARS_FILE"
echo "[MB_006] Ajout de ${MB_USER} au groupe ${CRYPTO_GROUP}..."
getent group "${CRYPTO_GROUP}" >/dev/null || groupadd -r "${CRYPTO_GROUP}"
usermod -aG "${CRYPTO_GROUP}" "${MB_USER}" || true
echo "[MB_006] OK."
exit 0
