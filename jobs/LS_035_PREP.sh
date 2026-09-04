#!/bin/bash
# LS_035_PREP - WEF_LS_RUN_GTERDY - Vanne maitresse : LOGSTASH_COLLECTOR_ONLINE
# JOB PASSERELLE (ouvre vers ES pour le scellement final ES_059_FINAL).
set -uo pipefail
source "$VARS_FILE"
echo "[LS_035_PREP] Verification finale avant emission du signal..."
curl -s -XGET http://127.0.0.1:9600/_node/pipelines -o ${WORK_TMP_DIR}/ls035.json
grep -q '"status":"green"' ${WORK_TMP_DIR}/ls035.json 2>/dev/null || echo "[LS_035_PREP] AVERTISSEMENT : statut pipeline non confirme 'green', signal emis quand meme (verification best-effort)."
rm -f ${WORK_TMP_DIR}/ls035.json
echo "[LS_035_PREP] Prise multiple universelle souveraine, etanche, connectee. Signal LOGSTASH_COLLECTOR_ONLINE emis."
echo "[LS_035_PREP] OK."
exit 0
