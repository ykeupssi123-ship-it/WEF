#!/bin/bash
# MB_011 - WEF_MB_BLD_MEMBUF - Calibrage de la memoire de retention
set -uo pipefail
source "$VARS_FILE"
echo "[MB_011] Calibrage de la queue memoire..."
grep -q "^queue.mem.events:" /etc/metricbeat/metricbeat.yml 2>/dev/null || echo "queue.mem.events: 2048" >> /etc/metricbeat/metricbeat.yml
echo "[MB_011] OK."
exit 0
