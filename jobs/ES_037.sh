#!/bin/bash
# ES_037 - WEF_ES_RUN_ILMPOLGEN - Politique ILM (purge/rollover)
#
# CORRIGE LE 2026-09-09 (demande explicite : pouvoir regler le seuil de
# rotation pour une demo, sans toucher au code) : les 4 seuils etaient
# en dur - desormais pilotes par vars.conf (ES_ILM_ROLLOVER_MAX_AGE/
# MAX_SIZE, ES_ILM_WARM_MIN_AGE, ES_ILM_DELETE_MIN_AGE). Rejouable a
# tout moment (bin/order.sh ES_037 "nouveau seuil demo") pour appliquer
# un changement.
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_037] Injection de la politique ILM factory_lifecycle (rollover: ${ES_ILM_ROLLOVER_MAX_AGE:-1d}/${ES_ILM_ROLLOVER_MAX_SIZE:-10gb}, warm: ${ES_ILM_WARM_MIN_AGE:-3d}, delete: ${ES_ILM_DELETE_MIN_AGE:-30d})..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ilm/policy/factory_lifecycle" \
  -H "Content-Type: application/json" -d '{
    "policy": {
      "phases": {
        "hot": {"min_age": "0ms", "actions": {"rollover": {"max_age": "'"${ES_ILM_ROLLOVER_MAX_AGE:-1d}"'", "max_primary_shard_size": "'"${ES_ILM_ROLLOVER_MAX_SIZE:-10gb}"'"}}},
        "warm": {"min_age": "'"${ES_ILM_WARM_MIN_AGE:-3d}"'", "actions": {"shrink": {"number_of_shards": 1}}},
        "delete": {"min_age": "'"${ES_ILM_DELETE_MIN_AGE:-30d}"'", "actions": {"delete": {}}}
      }
    }
  }' -o ${WORK_TMP_DIR}/es037.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es037.json && { echo "[ES_037] OK."; rm -f ${WORK_TMP_DIR}/es037.json; exit 0; }
echo "[ES_037] ERREUR, voir ${WORK_TMP_DIR}/es037.json"; exit 1
