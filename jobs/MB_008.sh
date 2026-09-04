#!/bin/bash
# MB_008 - WEF_MB_BLD_DYNMCMOD - Rechargement dynamique des sondes
set -uo pipefail
source "$VARS_FILE"
echo "[MB_008] Activation du rechargement dynamique..."
grep -q "^metricbeat.config.modules.reload.enabled:" /etc/metricbeat/metricbeat.yml 2>/dev/null || \
  echo "metricbeat.config.modules.reload.enabled: true" >> /etc/metricbeat/metricbeat.yml
echo "[MB_008] OK."
exit 0
