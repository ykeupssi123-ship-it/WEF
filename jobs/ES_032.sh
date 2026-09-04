#!/bin/bash
# ES_032 - WEF_ES_RUN_SOCKETW7XML - Pipeline structures XML Windows
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_032] Injection du pipeline windows_xml..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/windows_xml" \
  -H "Content-Type: application/json" -d '{
    "description": "Decodage evenements XML Windows - usine",
    "processors": [
      {"gsub": {"field": "message", "pattern": "<[^>]+>", "replacement": " ", "ignore_failure": true}},
      {"set": {"field": "factory_pipeline", "value": "windows_xml"}}
    ]
  }' -o ${WORK_TMP_DIR}/es032.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es032.json && { echo "[ES_032] OK."; rm -f ${WORK_TMP_DIR}/es032.json; exit 0; }
echo "[ES_032] ERREUR, voir ${WORK_TMP_DIR}/es032.json"; exit 1
