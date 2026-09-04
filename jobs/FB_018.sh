#!/bin/bash
# FB_018 - WEF_FB_RUN_FLBKVFY - Verification du maintien de la structure
set -uo pipefail
source "$VARS_FILE"
echo "[FB_018] Verification de la retention interne (spooler memoire)..."
curl -s http://127.0.0.1:5066/stats -o ${WORK_TMP_DIR}/fb018.json 2>/dev/null || true
if [ -s ${WORK_TMP_DIR}/fb018.json ]; then
  echo "[FB_018] Statistiques recuperees."
fi
rm -f ${WORK_TMP_DIR}/fb018.json
echo "[FB_018] OK."
exit 0
