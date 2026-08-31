#!/bin/bash
# LS_034 - WEF_LS_BLD_LGRTTCONF - Rotation des logs internes
set -uo pipefail
source "$VARS_FILE"
echo "[LS_034] Ecriture de la configuration logrotate..."
cat > /etc/logrotate.d/logstash << LOGEOF
/var/log/logstash/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[LS_034] OK."
exit 0
