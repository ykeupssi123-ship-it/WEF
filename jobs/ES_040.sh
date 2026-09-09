#!/bin/bash
# ES_040 - WEF_ES_RUN_IDXPATGEN - Gabarit d'interception ${ES_INDEX_NAME_PREFIX}-*
#
# CORRIGE LE 2026-09-09 (demande explicite : prefixe d'index generique
# configurable) : "log-*" etait en dur - desormais derive de
# ES_INDEX_NAME_PREFIX (vars.conf), MEME variable que celle utilisee par
# LS_024.sh pour construire le nom d'index reellement ecrit - une seule
# source de verite, jamais les deux a corriger separement si l'un des
# deux change.
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
IDX_PREFIX="${ES_INDEX_NAME_PREFIX:-log}"
echo "[ES_040] Injection du template factory_universal_template (${IDX_PREFIX}-*)..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_index_template/factory_universal_template" \
  -H "Content-Type: application/json" -d '{
    "index_patterns": ["'"${IDX_PREFIX}"'-*"],
    "composed_of": ["universal_settings","universal_mappings"],
    "priority": 100
  }' -o ${WORK_TMP_DIR}/es040.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es040.json && { echo "[ES_040] OK."; rm -f ${WORK_TMP_DIR}/es040.json; exit 0; }
echo "[ES_040] ERREUR, voir ${WORK_TMP_DIR}/es040.json"; exit 1
