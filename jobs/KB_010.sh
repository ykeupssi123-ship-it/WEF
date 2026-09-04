#!/bin/bash
# KB_010 - WEF_KB_BLD_ACLREAD - Inclusion au groupe crypto partage
set -uo pipefail
source "$VARS_FILE"
echo "[KB_010] Ajout de ${KB_USER} au groupe ${CRYPTO_GROUP}..."
usermod -aG "${CRYPTO_GROUP}" "${KB_USER}" || true
echo "[KB_010] OK."
exit 0
