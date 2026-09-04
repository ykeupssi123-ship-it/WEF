#!/bin/bash
# ES_030 - WEF_ES_RUN_SOCKETCEF - Pipeline decodage Common Event Format
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_030] Injection du pipeline cef_universal..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/cef_universal" \
  -H "Content-Type: application/json" -d '{
    "description": "Decodage CEF (appliances de securite) - usine",
    "processors": [
      {"grok": {"field": "message", "patterns": ["CEF:%{INT:cef_version}\\|%{DATA:cef_vendor}\\|%{DATA:cef_product}\\|%{DATA:cef_product_version}\\|%{DATA:cef_signature_id}\\|%{DATA:cef_name}\\|%{DATA:cef_severity}\\|%{GREEDYDATA:cef_extension}"], "ignore_failure": true}},
      {"set": {"field": "factory_pipeline", "value": "cef_universal"}}
    ]
  }' -o ${WORK_TMP_DIR}/es030.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es030.json && { echo "[ES_030] OK."; rm -f ${WORK_TMP_DIR}/es030.json; exit 0; }
echo "[ES_030] ERREUR, voir ${WORK_TMP_DIR}/es030.json"; exit 1
