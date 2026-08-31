#!/bin/bash
# ES_039 - WEF_ES_RUN_MAPTPL - Composant de template : mapping dynamique
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_039] Injection du composant universal_mappings..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_component_template/universal_mappings" \
  -H "Content-Type: application/json" -d '{
    "template": {
      "mappings": {
        "dynamic": true,
        "dynamic_templates": [
          {"strings_as_keyword": {"match_mapping_type": "string", "mapping": {"type": "keyword", "ignore_above": 1024}}}
        ]
      }
    }
  }' -o ${WORK_TMP_DIR}/es039.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es039.json && { echo "[ES_039] OK."; rm -f ${WORK_TMP_DIR}/es039.json; exit 0; }
echo "[ES_039] ERREUR, voir ${WORK_TMP_DIR}/es039.json"; exit 1
