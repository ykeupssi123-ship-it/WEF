#!/bin/bash
# WAZ_031 - WEF_WAZ_BLD_LGRTTDSH - Rotation des logs d'acces UI
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_031] Ecriture de la configuration logrotate (dashboard)..."
cat > /etc/logrotate.d/wazuh-dashboard << LOGEOF
/var/log/wazuh-dashboard/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[WAZ_031] OK."
exit 0
