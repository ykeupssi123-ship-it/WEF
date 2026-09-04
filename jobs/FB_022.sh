#!/bin/bash
# FB_022 - WEF_FB_BLD_IMMLOCK - Passage de la configuration en mode immuable
set -uo pipefail
source "$VARS_FILE"
if lsattr /etc/filebeat/filebeat.yml 2>/dev/null | grep -q "^----i"; then
  echo "[FB_022] Configuration deja immuable, ignore."
  echo "[FB_022] OK."
  exit 0
fi
echo "[FB_022] Verrouillage immuable de filebeat.yml..."
chattr +i /etc/filebeat/filebeat.yml
echo "[FB_022] OK."
exit 0
