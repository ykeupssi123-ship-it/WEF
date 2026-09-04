#!/bin/bash
# MB_002 - WEF_MB_BLD_DIRINIT - Repertoires de stockage des modules
set -uo pipefail
source "$VARS_FILE"
echo "[MB_002] Creation des repertoires..."
mkdir -p /var/lib/metricbeat /var/log/metricbeat /etc/metricbeat/modules.d
echo "[MB_002] OK."
exit 0
