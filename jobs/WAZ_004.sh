#!/bin/bash
# WAZ_004 - WEF_WAZ_BLD_DIRSTRUCT - Repertoires de donnees et d'alertes
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_004] Creation des repertoires..."
mkdir -p /var/ossec /var/lib/wazuh-indexer /etc/wazuh-indexer
echo "[WAZ_004] OK."
exit 0
