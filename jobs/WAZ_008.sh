#!/bin/bash
# WAZ_008 - WEF_WAZ_BLD_ACLJOIN - Inclusion au groupe de confiance
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_008] Ajout de wazuh au groupe ${CRYPTO_GROUP}..."
usermod -aG "${CRYPTO_GROUP}" wazuh || true
echo "[WAZ_008] OK."
exit 0
