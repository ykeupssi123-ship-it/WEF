#!/bin/bash
# ES_034 - WEF_ES_RUN_SOCKETANONYM - Suppresseur universel de donnees sensibles
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_034] Injection du pipeline gdpr_masking..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/gdpr_masking" \
  -H "Content-Type: application/json" -d '{
    "description": "Masquage RGPD/PCI (cartes, donnees nominatives) - usine",
    "processors": [
      {"gsub": {"field": "message", "pattern": "\\b(?:\\d[ -]*?){13,16}\\b", "replacement": "[MASKED_PAN]", "ignore_failure": true}},
      {"gsub": {"field": "message", "pattern": "password=\\S+", "replacement": "password=[MASKED]", "ignore_failure": true}},
      {"set": {"field": "factory_pipeline", "value": "gdpr_masking"}}
    ]
  }' -o ${WORK_TMP_DIR}/es034.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es034.json && { echo "[ES_034] OK."; rm -f ${WORK_TMP_DIR}/es034.json; exit 0; }
echo "[ES_034] ERREUR, voir ${WORK_TMP_DIR}/es034.json"; exit 1
