#!/bin/bash
# WAZ_049D_SEED_LCBFT_LIVE - WEF_WAZ_RUN_SEEDLCBFT
# Scenario BEAC (stage LCB-FT) : ecrit un nombre ALEATOIRE (entre
# LCBFT_SEED_MIN_COUNT et LCBFT_SEED_MAX_COUNT, vars.conf) de detections
# LCB-FT dans LCBFT_LOG_FILE, une a la fois avec une pause reelle
# (WAZ_DEMO_SEED_INTERVAL_SEC) entre chaque. Logstash (LS_020, entree
# "file") reprend ces lignes en direct et les indexe (LS_024) dans
# "${LCBFT_INDEX_PREFIX}-AAAA.MM.JJ" - AUCUN appel direct a l'API
# Elasticsearch ici, contrairement a WAZ_048/049/049B.
#
# AJOUTE LE 2026-09-13 (demande explicite utilisateur). JAMAIS dans la
# chaine automatique (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite
# ailleurs) - usage EXCLUSIVEMENT volontaire :
#   $APP_BIN/order.sh WAZ_049D_SEED_LCBFT_LIVE "demo LCB-FT"
#
# PREALABLE : LS_020/LS_024 doivent avoir ete (re)joues avec le code du
# 2026-09-13 pour que Logstash connaisse ces entrees/sorties (voir
# docs/GUIDE_EXPLOITATION.md, section scenario BEAC).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/beac_scenario_tools.sh"

SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"

echo "[WAZ_049D_SEED_LCBFT_LIVE] Ecriture de detections LCB-FT (entre ${LCBFT_SEED_MIN_COUNT} et ${LCBFT_SEED_MAX_COUNT}, 1 toutes les ${SEED_INTERVAL}s) dans ${LCBFT_LOG_FILE}..."
SEED_LOG="$(mktemp)"
seed_lcbft_detections_file "$LCBFT_LOG_FILE" "$LCBFT_SEED_MIN_COUNT" "$LCBFT_SEED_MAX_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[WAZ_049D_SEED_LCBFT_LIVE] ERREUR : l'ecriture a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[WAZ_049D_SEED_LCBFT_LIVE] OK."
exit 0
