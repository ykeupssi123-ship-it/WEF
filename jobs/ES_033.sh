#!/bin/bash
# ES_033 - WEF_ES_RUN_SOCKETIS8601 - Normalisation temporelle universelle
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_033] Injection du pipeline timestamp_standard..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/timestamp_standard" \
  -H "Content-Type: application/json" -d '{
    "description": "Normalisation horodatage ISO8601 - usine",
    "processors": [
      {"date": {"field": "timestamp", "target_field": "@timestamp", "formats": ["ISO8601","yyyy-MM-dd HH:mm:ss","MMM d HH:mm:ss"], "ignore_failure": true}},
      {"set": {"field": "factory_pipeline", "value": "timestamp_standard"}}
    ]
  }' -o ${WORK_TMP_DIR}/es033.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es033.json && { echo "[ES_033] OK."; rm -f ${WORK_TMP_DIR}/es033.json; exit 0; }
echo "[ES_033] ERREUR, voir ${WORK_TMP_DIR}/es033.json"; exit 1
