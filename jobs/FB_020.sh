#!/bin/bash
# FB_020 - WEF_FB_BLD_LOGROT - Rotation des diagnostics
set -uo pipefail
source "$VARS_FILE"
echo "[FB_020] Ecriture de la configuration logrotate..."
cat > /etc/logrotate.d/filebeat << LOGEOF
/var/log/filebeat/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[FB_020] OK."
exit 0
