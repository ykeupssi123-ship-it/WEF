#!/bin/bash
# ES_038 - WEF_ES_RUN_IDXTPL - Composant de template : parametres d'indexation
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_038] Injection du composant universal_settings..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_component_template/universal_settings" \
  -H "Content-Type: application/json" -d '{
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "index.lifecycle.name": "factory_lifecycle"
      }
    }
  }' -o ${WORK_TMP_DIR}/es038.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es038.json && { echo "[ES_038] OK."; rm -f ${WORK_TMP_DIR}/es038.json; exit 0; }
echo "[ES_038] ERREUR, voir ${WORK_TMP_DIR}/es038.json"; exit 1
