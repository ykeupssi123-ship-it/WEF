#!/bin/bash
# MB_018 - WEF_MB_BLD_NETRST - Reouverture des canaux d'exportation
set -uo pipefail
source "$VARS_FILE"
echo "[MB_018] Levee du blocage vers Logstash..."
iptables -D OUTPUT -p tcp --dport ${LS_BEATS_PORT} -j DROP || true
echo "[MB_018] OK."
exit 0
