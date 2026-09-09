#!/bin/bash
# WAZ_049_SEED_ES_LIVE - WEF_WAZ_RUN_SEEDESLIVE
# Miroir exact de WAZ_048_SEED_INDEXER_LIVE, cote Elasticsearch
# classique (index wazuh-alerts-4.x-*) au lieu de wazuh-indexer.
#
# AJOUTE LE 2026-09-09 (demande explicite utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). JAMAIS dans la chaine automatique
# (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite ailleurs) :
#   ./bin/order.sh WAZ_049_SEED_ES_LIVE "demo remplissage visible"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_049_SEED_ES_LIVE] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"
SEED_COUNT="${WAZ_DEMO_SEED_COUNT:-100}"
SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"
INDEX_NAME="wazuh-alerts-4.x-$(date +%Y.%m.%d)"

echo "[WAZ_049_SEED_ES_LIVE] Remplissage visible de ${SEED_COUNT} documents (1 toutes les ${SEED_INTERVAL}s) dans Elasticsearch (${INDEX_NAME})..."
SEED_LOG="$(mktemp)"
seed_test_alerts_live "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" "${PKI_DIR}/factory_ca.crt" "$INDEX_NAME" "$SEED_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[WAZ_049_SEED_ES_LIVE] ERREUR : le remplissage a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[WAZ_049_SEED_ES_LIVE] OK."
exit 0
