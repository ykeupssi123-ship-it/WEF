#!/bin/bash
# FB_008 - WEF_FB_BLD_DYNMCPROBE - Rechargement dynamique des cibles
set -uo pipefail
source "$VARS_FILE"
echo "[FB_008] Activation du rechargement dynamique..."
grep -q "^filebeat.config.inputs.reload.enabled:" /etc/filebeat/filebeat.yml 2>/dev/null || \
  echo "filebeat.config.inputs.reload.enabled: true" >> /etc/filebeat/filebeat.yml
echo "[FB_008] OK."
exit 0
