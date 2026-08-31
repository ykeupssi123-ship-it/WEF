#!/bin/bash
# KB_016 - WEF_KB_BLD_PROXYREADY - Restriction locale des cibles d'alerting
set -uo pipefail
source "$VARS_FILE"
echo "[KB_016] Verrouillage des webhooks d'alerte au perimetre local..."
grep -q "^xpack.actions.allowedHosts:" /etc/kibana/kibana.yml 2>/dev/null || echo 'xpack.actions.allowedHosts: ["127.0.0.1", "localhost"]' >> /etc/kibana/kibana.yml
echo "[KB_016] OK."
exit 0
