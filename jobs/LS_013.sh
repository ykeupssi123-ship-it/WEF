#!/bin/bash
# LS_013 - WEF_LS_BLD_ACLREAD - Inclusion au groupe crypto partage
set -uo pipefail
source "$VARS_FILE"
echo "[LS_013] Ajout de ${LS_USER} au groupe ${CRYPTO_GROUP}..."
usermod -aG "${CRYPTO_GROUP}" "${LS_USER}" || true
echo "[LS_013] OK."
exit 0
