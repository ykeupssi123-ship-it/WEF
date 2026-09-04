#!/bin/bash
# WAZ_047_PURGE_ES_DATA - WEF_WAZ_RUN_PURGEESDATA
# Miroir exact de WAZ_046_PURGE_INDEXER_DATA, cote Elasticsearch
# classique. DESTRUCTEUR ET IRREVERSIBLE - jamais dans la chaine
# automatique.
#
# AJOUTE LE 2026-09-03 (demande explicite utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). IN_COND=WAZ_PURGE_MANUAL_GATE (jamais
# satisfaite ailleurs) - usage EXCLUSIVEMENT volontaire :
#   ./bin/order_job.sh WAZ_047_PURGE_ES_DATA "nettoyage post-essai"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_047_PURGE_ES_DATA] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"

echo "[WAZ_047_PURGE_ES_DATA] Purge de wazuh-alerts-4.x-* dans Elasticsearch..."
PURGE_LOG="$(mktemp)"
purge_index_pattern "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" "${PKI_DIR}/factory_ca.crt" "wazuh-alerts-4.x-*" > "$PURGE_LOG" 2>&1
PURGE_EXIT=$?
cat "$PURGE_LOG"
if [ $PURGE_EXIT -ne 0 ]; then
  echo "[WAZ_047_PURGE_ES_DATA] ERREUR : la purge a echoue (voir sortie ci-dessus)." >&2
  rm -f "$PURGE_LOG"
  exit 1
fi
rm -f "$PURGE_LOG"

echo "[WAZ_047_PURGE_ES_DATA] OK."
exit 0
