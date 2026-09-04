#!/bin/bash
# WAZ_029 - WEF_WAZ_BLD_LGRTTMGR - Rotation des alertes et archives
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_029] Ecriture de la configuration logrotate (manager)..."
cat > /etc/logrotate.d/wazuh-manager << LOGEOF
/var/ossec/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[WAZ_029] OK."
exit 0
