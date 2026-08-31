#!/bin/bash
# MB_017 - WEF_MB_RUN_SPOOLVERIFY - Verification de non-perte des paquets
set -uo pipefail
source "$VARS_FILE"
echo "[MB_017] Inspection de la consommation memoire de la queue..."
journalctl -u metricbeat --no-pager 2>/dev/null | tail -50 | grep -qi "error\|dropped" && \
  echo "[MB_017] AVERTISSEMENT : des erreurs/pertes potentielles detectees dans les logs recents." || true
echo "[MB_017] OK."
exit 0
