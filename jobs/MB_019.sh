#!/bin/bash
# MB_019 - WEF_MB_BLD_LOGROT - Rotation des diagnostics internes
set -uo pipefail
source "$VARS_FILE"
echo "[MB_019] Ecriture de la configuration logrotate..."
cat > /etc/logrotate.d/metricbeat << LOGEOF
/var/log/metricbeat/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGEOF
echo "[MB_019] OK."
exit 0
