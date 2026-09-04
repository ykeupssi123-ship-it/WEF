#!/bin/bash
# ES_031 - WEF_ES_RUN_SOCKETCSV - Pipeline fichiers plats CSV
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_031] Injection du pipeline csv_universal..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/csv_universal" \
  -H "Content-Type: application/json" -d '{
    "description": "Traitement CSV brut - usine",
    "processors": [
      {"csv": {"field": "message", "target_fields": ["col1","col2","col3","col4","col5"], "ignore_missing": true, "trim": true}},
      {"set": {"field": "factory_pipeline", "value": "csv_universal"}}
    ]
  }' -o ${WORK_TMP_DIR}/es031.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es031.json && { echo "[ES_031] OK."; rm -f ${WORK_TMP_DIR}/es031.json; exit 0; }
echo "[ES_031] ERREUR, voir ${WORK_TMP_DIR}/es031.json"; exit 1
