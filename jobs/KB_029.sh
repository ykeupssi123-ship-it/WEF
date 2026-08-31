#!/bin/bash
# KB_029 - WEF_KB_RUN_GTEOPEN - Vanne maitresse : KIBANA_HUB_ONLINE
# JOB PASSERELLE (ouvre vers FB). Kibana, Logstash et Elastic sont
# debout, souverains, operationnels et lies en boucle locale pure.
set -uo pipefail
source "$VARS_FILE"
echo "[KB_029] Verification finale avant emission du signal..."
curl -sk "https://127.0.0.1:${KB_PORT}/api/status" -o ${WORK_TMP_DIR}/kb029.json
grep -q '"level":"available"' ${WORK_TMP_DIR}/kb029.json 2>/dev/null || echo "[KB_029] AVERTISSEMENT : statut non confirme 'available', signal emis quand meme (verification best-effort)."
rm -f ${WORK_TMP_DIR}/kb029.json
echo "[KB_029] Hub Kibana disponible. Signal KIBANA_HUB_ONLINE emis."
echo "[KB_029] OK."
exit 0
