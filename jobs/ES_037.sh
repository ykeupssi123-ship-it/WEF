#!/bin/bash
# ES_037 - WEF_ES_RUN_ILMPOLGEN - Politique ILM (purge/rollover)
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_037] Injection de la politique ILM factory_lifecycle..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ilm/policy/factory_lifecycle" \
  -H "Content-Type: application/json" -d '{
    "policy": {
      "phases": {
        "hot": {"min_age": "0ms", "actions": {"rollover": {"max_age": "1d", "max_primary_shard_size": "10gb"}}},
        "warm": {"min_age": "3d", "actions": {"shrink": {"number_of_shards": 1}}},
        "delete": {"min_age": "30d", "actions": {"delete": {}}}
      }
    }
  }' -o ${WORK_TMP_DIR}/es037.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es037.json && { echo "[ES_037] OK."; rm -f ${WORK_TMP_DIR}/es037.json; exit 0; }
echo "[ES_037] ERREUR, voir ${WORK_TMP_DIR}/es037.json"; exit 1
