#!/bin/bash
# LS_033 - WEF_LS_RUN_NETRST - Reouverture des vannes de communication
set -uo pipefail
source "$VARS_FILE"
echo "[LS_033] Levee du blocage iptables vers Elasticsearch..."
iptables -D OUTPUT -p tcp --dport ${ES_PORT} -j DROP || true
echo "[LS_033] OK."
exit 0
