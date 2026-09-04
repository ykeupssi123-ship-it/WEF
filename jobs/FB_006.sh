#!/bin/bash
# FB_006 - WEF_FB_BLD_ACLREAD - Inclusion au groupe crypto partage
set -uo pipefail
source "$VARS_FILE"
echo "[FB_006] Ajout de ${FB_USER} au groupe ${CRYPTO_GROUP}..."
getent group "${CRYPTO_GROUP}" >/dev/null || groupadd -r "${CRYPTO_GROUP}"
usermod -aG "${CRYPTO_GROUP}" "${FB_USER}" || true
echo "[FB_006] OK."
exit 0
