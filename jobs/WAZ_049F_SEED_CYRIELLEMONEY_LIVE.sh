#!/bin/bash
# WAZ_049F_SEED_CYRIELLEMONEY_LIVE - WEF_WAZ_RUN_SEEDCYRIELLE
# Scenario BEAC : ecrit WAZ_DEMO_SEED_COUNT evenements de transfert
# CyrielleMoney (national/international, journaux au format Glassfish)
# dans CYRIELLEMONEY_LOG_FILE, un a la fois avec une pause reelle
# (WAZ_DEMO_SEED_INTERVAL_SEC) entre chaque. Logstash (LS_020/LS_024)
# reprend ces lignes en direct et les indexe dans
# "${CYRIELLEMONEY_INDEX_PREFIX}-AAAA.MM.JJ" - AUCUN appel direct a
# l'API Elasticsearch ici (voir jobs/lib/beac_scenario_tools.sh).
#
# AJOUTE LE 2026-09-13 (demande explicite utilisateur). JAMAIS dans la
# chaine automatique (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite
# ailleurs) - usage EXCLUSIVEMENT volontaire :
#   $APP_BIN/order.sh WAZ_049F_SEED_CYRIELLEMONEY_LIVE "demo CyrielleMoney"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/beac_scenario_tools.sh"

SEED_COUNT="${WAZ_DEMO_SEED_COUNT:-100}"
SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"

echo "[WAZ_049F_SEED_CYRIELLEMONEY_LIVE] Ecriture de ${SEED_COUNT} transferts CyrielleMoney (1 toutes les ${SEED_INTERVAL}s) dans ${CYRIELLEMONEY_LOG_FILE}..."
SEED_LOG="$(mktemp)"
seed_cyriellemoney_transfers_file "$CYRIELLEMONEY_LOG_FILE" "$SEED_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[WAZ_049F_SEED_CYRIELLEMONEY_LIVE] ERREUR : l'ecriture a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[WAZ_049F_SEED_CYRIELLEMONEY_LIVE] OK."
exit 0
