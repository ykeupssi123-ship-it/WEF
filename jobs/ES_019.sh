#!/bin/bash
# ES_019 - WEF_ES_BLD_ACLREAD - Ajout au groupe crypto partage
set -uo pipefail
source "$VARS_FILE"
echo "[ES_019] Ajout de ${ES_USER} au groupe ${CRYPTO_GROUP}..."
usermod -aG "${CRYPTO_GROUP}" "${ES_USER}" || true
echo "[ES_019] OK."
exit 0
