#!/bin/bash
# BEAC_002_SEED_CYRIELLEMONEY_LIVE - WEF_BEAC_RUN_SEEDCYRIELLE
# Scenario BEAC : ecrit WAZ_DEMO_SEED_COUNT evenements de transfert
# CyrielleMoney (national/international, journaux au format Glassfish)
# dans CYRIELLEMONEY_LOG_FILE, un a la fois avec une pause reelle
# (WAZ_DEMO_SEED_INTERVAL_SEC) entre chaque.
#
# JOUE SUR AGENT_HOST (VM2), PAS ELK_HOST - meme correction et meme
# principe que BEAC_001_SEED_LCBFT_LIVE.sh (voir son en-tete pour le
# detail complet) : ${CYRIELLEMONEY_LOG_FILE} vit sous /var/log/, deja
# couvert par le prospecteur Filebeat generique existant (FB_007.sh),
# expedie a Logstash (FB_012) comme n'importe quel autre log de l'hote,
# reconnu par son chemin source et route (LS_023B_BEAC_FILTER/LS_024)
# vers "${CYRIELLEMONEY_INDEX_PREFIX}-AAAA.MM.JJ" - AUCUN appel direct a
# l'API Elasticsearch ici (voir jobs/lib/beac_scenario_tools.sh).
#
# AJOUTE LE 2026-09-13 (demande explicite utilisateur). JAMAIS dans la
# chaine automatique (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite
# ailleurs) - usage EXCLUSIVEMENT volontaire, depuis VM2 :
#   $APP_BIN/order.sh BEAC_002_SEED_CYRIELLEMONEY_LIVE "demo CyrielleMoney"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/beac_scenario_tools.sh"

SEED_COUNT="${WAZ_DEMO_SEED_COUNT:-100}"
SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"

echo "[BEAC_002_SEED_CYRIELLEMONEY_LIVE] Ecriture de ${SEED_COUNT} transferts CyrielleMoney (1 toutes les ${SEED_INTERVAL}s) dans ${CYRIELLEMONEY_LOG_FILE}..."
SEED_LOG="$(mktemp)"
seed_cyriellemoney_transfers_file "$CYRIELLEMONEY_LOG_FILE" "$SEED_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[BEAC_002_SEED_CYRIELLEMONEY_LIVE] ERREUR : l'ecriture a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[BEAC_002_SEED_CYRIELLEMONEY_LIVE] OK."
exit 0
