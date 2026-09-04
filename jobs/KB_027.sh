#!/bin/bash
# KB_027 - WEF_KB_BLD_LOGROT - Rotation des journaux d'acces web
set -uo pipefail
source "$VARS_FILE"
echo "[KB_027] Ecriture de la configuration logrotate..."
cat > /etc/logrotate.d/kibana << LOGEOF
/var/log/kibana/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[KB_027] OK."
exit 0
