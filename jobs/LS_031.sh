#!/bin/bash
# LS_031 - WEF_LS_RUN_FLBKVFY - Verification du stockage dans la PQ
set -uo pipefail
source "$VARS_FILE"
echo "[LS_031] Verification de la Persistent Queue..."
QSIZE=$(du -s /var/lib/logstash/queue/ 2>/dev/null | awk '{print $1}')
if [ -z "$QSIZE" ] || [ "$QSIZE" -le 0 ]; then
  echo "[LS_031] ERREUR : la PQ est vide, les donnees semblent avoir ete perdues."
  exit 1
fi
echo "[LS_031] PQ occupee (${QSIZE}), la charge est bien encaissee."
echo "[LS_031] OK."
exit 0
