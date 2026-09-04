#!/bin/bash
# WAZ_017 - WEF_WAZ_BLD_HEALTHCHECK - Vivacite globale de l'ecosysteme
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_017] Verification de l'etat global Wazuh..."
/var/ossec/bin/wazuh-control status
echo "[WAZ_017] OK."
exit 0
