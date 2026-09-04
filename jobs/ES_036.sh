#!/bin/bash
# ES_036 - WEF_ES_RUN_COMPVFY - Validation fonctionnelle des pipelines
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_036] Simulation de test sur le pipeline json_universal..."
es_admin_curl -X POST "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/json_universal/_simulate" \
  -H "Content-Type: application/json" -d '{
    "docs": [{"_source": {"message": "{\"test\":true}"}}]
  }' -o ${WORK_TMP_DIR}/es036.json
grep -q '"docs"' ${WORK_TMP_DIR}/es036.json && { echo "[ES_036] OK."; rm -f ${WORK_TMP_DIR}/es036.json; exit 0; }
echo "[ES_036] ERREUR, voir ${WORK_TMP_DIR}/es036.json"; exit 1
