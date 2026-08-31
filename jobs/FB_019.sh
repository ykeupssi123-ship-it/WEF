#!/bin/bash
# FB_019 - WEF_FB_BLD_NETRST - Reouverture des vannes de communication
set -uo pipefail
source "$VARS_FILE"
echo "[FB_019] Levee du blocage vers Logstash..."
iptables -D OUTPUT -p tcp --dport ${LS_BEATS_PORT} -j DROP || true
echo "[FB_019] OK."
exit 0
