#!/bin/bash
# ES_028 - WEF_ES_RUN_SOCKETJSON - Pipeline d'ingestion brute JSON
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_028] Injection du pipeline json_universal..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/json_universal" \
  -H "Content-Type: application/json" -d '{
    "description": "Ingestion JSON brute - usine",
    "processors": [
      {"json": {"field": "message", "target_field": "payload", "ignore_failure": true}},
      {"set": {"field": "factory_pipeline", "value": "json_universal"}}
    ]
  }' -o ${WORK_TMP_DIR}/es028.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es028.json && { echo "[ES_028] OK."; rm -f ${WORK_TMP_DIR}/es028.json; exit 0; }
echo "[ES_028] ERREUR, voir ${WORK_TMP_DIR}/es028.json"; exit 1
