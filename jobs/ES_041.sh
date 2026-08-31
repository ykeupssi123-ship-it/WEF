#!/bin/bash
# ES_041 - WEF_ES_RUN_IDXLIMIT - Disjoncteur cluster : namespaces autorises
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_041] Restriction de creation d'index aux namespaces autorises..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_cluster/settings" \
  -H "Content-Type: application/json" -d '{
    "persistent": {"action.auto_create_index": "log-*,wazuh-*,-*"}
  }' -o ${WORK_TMP_DIR}/es041.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es041.json && { echo "[ES_041] OK."; rm -f ${WORK_TMP_DIR}/es041.json; exit 0; }
echo "[ES_041] ERREUR, voir ${WORK_TMP_DIR}/es041.json"; exit 1
