#!/bin/bash
# BEAC_001_SEED_LCBFT_LIVE - WEF_BEAC_RUN_SEEDLCBFT
# Scenario BEAC (stage LCB-FT) : ecrit un nombre ALEATOIRE (entre
# LCBFT_SEED_MIN_COUNT et LCBFT_SEED_MAX_COUNT, vars.conf) de detections
# LCB-FT dans LCBFT_LOG_FILE, une a la fois avec une pause reelle
# (WAZ_DEMO_SEED_INTERVAL_SEC) entre chaque.
#
# JOUE SUR AGENT_HOST (VM2), PAS ELK_HOST - CORRIGE LE 2026-09-13
# (remarque explicite et juste de l'operateur : la version initiale
# ecrivait ce fichier directement sur ELK_HOST, alors que le principe de
# cette usine est que les donnees naissent sur une machine cliente et
# REMONTENT via Filebeat, jamais l'inverse). ${LCBFT_LOG_FILE} vit sous
# /var/log/ (jamais un sous-repertoire) - deja couvert par le
# prospecteur Filebeat generique existant (FB_007.sh, "/var/log/*.log"),
# aucune config Filebeat supplementaire necessaire. Filebeat (FB_012)
# l'expedie a Logstash exactement comme n'importe quel autre log de
# l'hote ; Logstash (LS_023B_BEAC_FILTER/LS_024) le reconnait par son
# chemin source et le route vers "${LCBFT_INDEX_PREFIX}-AAAA.MM.JJ" -
# AUCUN appel direct a l'API Elasticsearch ici, contrairement a
# WAZ_048/049/049B (qui tournent eux sur ELK_HOST).
#
# AJOUTE LE 2026-09-13 (demande explicite utilisateur). JAMAIS dans la
# chaine automatique (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais satisfaite
# ailleurs) - usage EXCLUSIVEMENT volontaire, depuis VM2 :
#   $APP_BIN/order.sh BEAC_001_SEED_LCBFT_LIVE "demo LCB-FT"
#
# PREALABLE (sur ELK_HOST, une fois) : LS_023B_BEAC_FILTER/LS_024
# doivent avoir ete (re)joues avec le code du 2026-09-13 pour que
# Logstash reconnaisse et route ces evenements (voir
# docs/GUIDE_EXPLOITATION.md, section scenario BEAC).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/beac_scenario_tools.sh"

SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"

echo "[BEAC_001_SEED_LCBFT_LIVE] Ecriture de detections LCB-FT (entre ${LCBFT_SEED_MIN_COUNT} et ${LCBFT_SEED_MAX_COUNT}, 1 toutes les ${SEED_INTERVAL}s) dans ${LCBFT_LOG_FILE}..."
SEED_LOG="$(mktemp)"
seed_lcbft_detections_file "$LCBFT_LOG_FILE" "$LCBFT_SEED_MIN_COUNT" "$LCBFT_SEED_MAX_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[BEAC_001_SEED_LCBFT_LIVE] ERREUR : l'ecriture a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[BEAC_001_SEED_LCBFT_LIVE] OK."
exit 0
