#!/bin/bash
# MB_007 - WEF_MB_BLD_MODSYSTEM - Surveillance CPU/RAM/IO/FS
set -uo pipefail
source "$VARS_FILE"
echo "[MB_007] Activation du module system..."
/usr/share/metricbeat/bin/metricbeat modules enable system 2>&1 | grep -qi "already enabled" || true
echo "[MB_007] OK."
exit 0
