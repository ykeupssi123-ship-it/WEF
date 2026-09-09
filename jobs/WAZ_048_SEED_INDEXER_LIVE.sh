#!/bin/bash
# WAZ_048_SEED_INDEXER_LIVE - WEF_WAZ_RUN_SEEDIDXLIVE
# Jeu de remplissage VISIBLE : insere WAZ_DEMO_SEED_COUNT (defaut 100,
# voir vars.conf) documents dans wazuh-indexer (index wazuh-alerts-4.x-*),
# UN a la fois avec une pause reelle de WAZ_DEMO_SEED_INTERVAL_SEC
# (defaut 1s) entre chaque - pour regarder les donnees apparaitre en
# direct dans Wazuh Dashboard pendant une demo.
#
# AJOUTE LE 2026-09-09 (demande explicite utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). Distinct de WAZ_045A_SEED_INDEXER_DATA
# (test de CHARGE, bulk instantane) - meme moteur (jobs/lib/test_data_tools.sh),
# fonction differente (seed_test_alerts_live, un document a la fois).
# JAMAIS dans la chaine automatique (IN_COND=WAZ_PURGE_MANUAL_GATE,
# jamais satisfaite ailleurs) - usage EXCLUSIVEMENT volontaire :
#   ./bin/order.sh WAZ_048_SEED_INDEXER_LIVE "demo remplissage visible"
# Chaque document porte "wef_test_seed": true - jamais confondu avec une
# vraie alerte.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
SEED_COUNT="${WAZ_DEMO_SEED_COUNT:-100}"
SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"
INDEX_NAME="wazuh-alerts-4.x-$(date +%Y.%m.%d)"

echo "[WAZ_048_SEED_INDEXER_LIVE] Remplissage visible de ${SEED_COUNT} documents (1 toutes les ${SEED_INTERVAL}s) dans wazuh-indexer (${INDEX_NAME})..."
SEED_LOG="$(mktemp)"
seed_test_alerts_live "https://127.0.0.1:${WAZ_INDEXER_PORT}" "${WAZ_INDEXER_ADMIN_USER}" "${WAZUH_INDEXER_ADMIN_PW}" "${PKI_DIR}/factory_ca.crt" "$INDEX_NAME" "$SEED_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[WAZ_048_SEED_INDEXER_LIVE] ERREUR : le remplissage a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[WAZ_048_SEED_INDEXER_LIVE] OK."
exit 0
