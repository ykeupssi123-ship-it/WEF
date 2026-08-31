#!/bin/bash
# MB_020 - WEF_MB_BLD_PERMLOCK - Droits drastiques sur le keystore
set -uo pipefail
source "$VARS_FILE"
echo "[MB_020] Verrouillage des permissions..."
chmod 600 /etc/metricbeat/metricbeat.yml
chmod -R 600 /var/lib/metricbeat
echo "[MB_020] OK."
exit 0
