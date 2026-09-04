#!/bin/bash
# WAZ_045B_SEED_ES_DATA - WEF_WAZ_RUN_SEEDESDATA
# Miroir exact de WAZ_045A_SEED_INDEXER_DATA, cote Elasticsearch
# classique (index wazuh-alerts-4.x-*) au lieu de wazuh-indexer.
#
# AJOUTE LE 2026-09-03 (demande explicite utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). JAMAIS dans la chaine automatique
# (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite ailleurs) :
#   ./bin/order_job.sh WAZ_045B_SEED_ES_DATA "test de charge migration"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_045B_SEED_ES_DATA] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"
SEED_COUNT="${WAZ_SEED_COUNT:-50000}"
INDEX_NAME="wazuh-alerts-4.x-$(date +%Y.%m.%d)"

echo "[WAZ_045B_SEED_ES_DATA] Chargement de ${SEED_COUNT} documents de test dans Elasticsearch (${INDEX_NAME})..."
SEED_LOG="$(mktemp)"
seed_test_alerts "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" "${PKI_DIR}/factory_ca.crt" "$INDEX_NAME" "$SEED_COUNT" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[WAZ_045B_SEED_ES_DATA] ERREUR : le chargement a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[WAZ_045B_SEED_ES_DATA] OK."
exit 0
