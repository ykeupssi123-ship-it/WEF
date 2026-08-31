#!/bin/bash
# ES_058 - WEF_ES_RUN_SECSURV - Persistance des identifiants maitres
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_058] Verification que le compte elastic repond toujours apres redemarrage..."
es_admin_curl "https://127.0.0.1:${ES_PORT}/_security/_authenticate" -o ${WORK_TMP_DIR}/es058.json
grep -q '"username":"elastic"' ${WORK_TMP_DIR}/es058.json && { echo "[ES_058] OK."; rm -f ${WORK_TMP_DIR}/es058.json; exit 0; }
echo "[ES_058] ERREUR : authentification elastic a echoue apres redemarrage."; exit 1
