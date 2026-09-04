#!/bin/bash
# ES_035 - WEF_ES_RUN_SOCKETDRPPR - Disjoncteur automatique de logs parasites
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_035] Injection du pipeline noise_control..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/noise_control" \
  -H "Content-Type: application/json" -d '{
    "description": "Filtre debit / suppression bruit - usine",
    "processors": [
      {"drop": {"if": "ctx.message != null && ctx.message.contains(\"HEALTHCHECK_NOISE\")"}},
      {"set": {"field": "factory_pipeline", "value": "noise_control"}}
    ]
  }' -o ${WORK_TMP_DIR}/es035.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es035.json && { echo "[ES_035] OK."; rm -f ${WORK_TMP_DIR}/es035.json; echo "[ES_035] Signal FACTORY_ES_READY emis."; exit 0; }
echo "[ES_035] ERREUR, voir ${WORK_TMP_DIR}/es035.json"; exit 1
