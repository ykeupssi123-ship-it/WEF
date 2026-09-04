#!/bin/bash
# MB_021 - WEF_MB_BLD_IMMLOCK - Passage des definitions de sondes en immuable
set -uo pipefail
source "$VARS_FILE"
if lsattr /etc/metricbeat/metricbeat.yml 2>/dev/null | grep -q "^----i"; then
  echo "[MB_021] Configuration deja immuable, ignore."
  echo "[MB_021] OK."
  exit 0
fi
echo "[MB_021] Verrouillage immuable de metricbeat.yml..."
chattr +i /etc/metricbeat/metricbeat.yml
echo "[MB_021] OK."
exit 0
