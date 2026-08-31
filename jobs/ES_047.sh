#!/bin/bash
# ES_047 - WEF_ES_BLD_LGRTTSETUP - Configuration de la purge automatique OS
set -uo pipefail
source "$VARS_FILE"
echo "[ES_047] Ecriture de la configuration logrotate..."
cat > /etc/logrotate.d/elasticsearch << LOGEOF
/var/log/elasticsearch/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[ES_047] OK."
exit 0
