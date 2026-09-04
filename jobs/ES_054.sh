#!/bin/bash
# ES_054 - WEF_ES_RUN_PIPESURV - Persistance des pipelines apres crash
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_054] Verification de la persistance des pipelines dans le cluster state..."
es_admin_curl "https://127.0.0.1:${ES_PORT}/_ingest/pipeline" -o ${WORK_TMP_DIR}/es054.json
for p in json_universal syslog_universal cef_universal csv_universal windows_xml timestamp_standard gdpr_masking noise_control; do
  grep -q "\"$p\"" ${WORK_TMP_DIR}/es054.json || { echo "[ES_054] ERREUR : pipeline $p manquant apres crash."; exit 1; }
done
echo "[ES_054] Tous les pipelines ont survecu au crash."
rm -f ${WORK_TMP_DIR}/es054.json
echo "[ES_054] OK."
exit 0
