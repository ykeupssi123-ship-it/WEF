#!/bin/bash
# WAZ_030 - WEF_WAZ_BLD_LGRTTIDX - Rotation des historiques indexer
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_030] Ecriture de la configuration logrotate (indexer)..."
cat > /etc/logrotate.d/wazuh-indexer << LOGEOF
/var/log/wazuh-indexer/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[WAZ_030] OK."
exit 0
