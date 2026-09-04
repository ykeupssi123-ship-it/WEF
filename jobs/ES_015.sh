#!/bin/bash
# ES_015 - WEF_ES_BLD_FWAPPLY - Application a chaud des regles pare-feu
set -uo pipefail
source "$VARS_FILE"
echo "[ES_015] Rechargement de firewalld..."
firewall-cmd --reload
echo "[ES_015] OK."
exit 0
