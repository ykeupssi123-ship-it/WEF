#!/bin/bash
# ES_040 - WEF_ES_RUN_IDXPATGEN - Gabarit d'interception log-*
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_040] Injection du template factory_universal_template..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_index_template/factory_universal_template" \
  -H "Content-Type: application/json" -d '{
    "index_patterns": ["log-*"],
    "composed_of": ["universal_settings","universal_mappings"],
    "priority": 100
  }' -o ${WORK_TMP_DIR}/es040.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es040.json && { echo "[ES_040] OK."; rm -f ${WORK_TMP_DIR}/es040.json; exit 0; }
echo "[ES_040] ERREUR, voir ${WORK_TMP_DIR}/es040.json"; exit 1
