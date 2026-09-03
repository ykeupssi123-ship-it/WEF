#!/bin/bash
# WAZ_046_PURGE_INDEXER_DATA - WEF_WAZ_RUN_PURGEIDXDATA
# Vide EN UNE FOIS toutes les alertes (wazuh-alerts-4.x-*) de
# wazuh-indexer - typiquement pour nettoyer apres un essai charge avec
# WAZ_045A_SEED_INDEXER_DATA. DESTRUCTEUR ET IRREVERSIBLE - jamais dans
# la chaine automatique.
#
# AJOUTE LE 2026-09-03 (demande explicite utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md). IN_COND=WAZ_PURGE_MANUAL_GATE (jamais
# satisfaite ailleurs) - usage EXCLUSIVEMENT volontaire :
#   ./forcer_job.sh WAZ_046_PURGE_INDEXER_DATA "nettoyage post-essai"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"

echo "[WAZ_046_PURGE_INDEXER_DATA] Purge de wazuh-alerts-4.x-* dans wazuh-indexer..."
PURGE_LOG="$(mktemp)"
purge_index_pattern "https://127.0.0.1:${WAZ_INDEXER_PORT}" "${WAZ_INDEXER_ADMIN_USER}" "${WAZUH_INDEXER_ADMIN_PW}" "${PKI_DIR}/factory_ca.crt" "wazuh-alerts-4.x-*" > "$PURGE_LOG" 2>&1
PURGE_EXIT=$?
cat "$PURGE_LOG"
if [ $PURGE_EXIT -ne 0 ]; then
  echo "[WAZ_046_PURGE_INDEXER_DATA] ERREUR : la purge a echoue (voir sortie ci-dessus)." >&2
  rm -f "$PURGE_LOG"
  exit 1
fi
rm -f "$PURGE_LOG"

echo "[WAZ_046_PURGE_INDEXER_DATA] OK."
exit 0
