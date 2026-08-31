#!/bin/bash
# KB_012 - WEF_KB_BLD_SERVERBIND - Liaison sur toutes les interfaces locales
set -uo pipefail
source "$VARS_FILE"
echo "[KB_012] Configuration de l'ecoute reseau..."
grep -q '^server.host:' /etc/kibana/kibana.yml 2>/dev/null && sed -i 's/^server.host:.*/server.host: "0.0.0.0"/' /etc/kibana/kibana.yml || echo 'server.host: "0.0.0.0"' >> /etc/kibana/kibana.yml
echo "[KB_012] OK."
exit 0
