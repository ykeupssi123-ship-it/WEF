#!/bin/bash
# WAZ_045A_SEED_INDEXER_DATA - WEF_WAZ_RUN_SEEDIDXDATA
# Charge WAZ_SEED_COUNT (defaut 50000, voir vars.conf) documents
# d'alertes synthetiques dans wazuh-indexer (index wazuh-alerts-4.x-*),
# pour avoir de quoi tester reellement les jobs de coupure/migration
# (WAZ_035B/WAZ_039C) sans attendre une vraie charge de production.
#
# AJOUTE LE 2026-09-03 (demande explicite utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). JAMAIS dans la chaine automatique
# (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite ailleurs) - usage
# EXCLUSIVEMENT volontaire :
#   ./forcer_job.sh WAZ_045A_SEED_INDEXER_DATA "test de charge migration"
# Chaque document porte "wef_test_seed": true - jamais confondu avec une
# vraie alerte (voir jobs/lib/test_data_tools.sh).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
SEED_COUNT="${WAZ_SEED_COUNT:-50000}"
INDEX_NAME="wazuh-alerts-4.x-$(date +%Y.%m.%d)"

echo "[WAZ_045A_SEED_INDEXER_DATA] Chargement de ${SEED_COUNT} documents de test dans wazuh-indexer (${INDEX_NAME})..."
SEED_LOG="$(mktemp)"
seed_test_alerts "https://127.0.0.1:${WAZ_INDEXER_PORT}" "${WAZ_INDEXER_ADMIN_USER}" "${WAZUH_INDEXER_ADMIN_PW}" "${PKI_DIR}/factory_ca.crt" "$INDEX_NAME" "$SEED_COUNT" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[WAZ_045A_SEED_INDEXER_DATA] ERREUR : le chargement a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[WAZ_045A_SEED_INDEXER_DATA] OK."
exit 0
