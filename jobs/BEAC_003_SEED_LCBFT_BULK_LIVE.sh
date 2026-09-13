#!/bin/bash
# BEAC_003_SEED_LCBFT_BULK_LIVE - WEF_BEAC_RUN_SEEDLCBFTBULK
# Demo "presentation live" (public/etudiant) : ecrit un nombre FIXE de
# detections LCB-FT (LCBFT_DEMO_BULK_COUNT, defaut 50 - jamais aleatoire,
# contrairement a BEAC_001_SEED_LCBFT_LIVE qui simule la variabilite
# business reelle) a intervalle regulier (LCBFT_DEMO_BULK_INTERVAL_SEC,
# defaut 2s - plus lent que le 1s habituel des autres jobs de demo, pour
# laisser le temps de suivre chaque arrivee dans Kibana pendant une
# presentation).
#
# JOUE SUR AGENT_HOST (VM2), meme mecanique que BEAC_001_SEED_LCBFT_LIVE
# (voir son en-tete pour le detail complet du chemin fichier -> Filebeat
# -> Logstash -> Elasticsearch).
#
# AJOUTE LE 2026-09-13 (demande explicite : "je veux qu'on voit 50
# enregistrements ecrits a l'intervalle de 2s" - refuse categoriquement
# de modifier vars.conf a la main pour une simple demo, meme principe
# deja applique ailleurs dans ce projet : WAZ_045A (bulk/test de charge)
# est un job DEDIE, distinct de WAZ_048 (remplissage visible normal),
# jamais un parametre partage a retoucher a chaque usage). JAMAIS dans
# la chaine automatique (IN_COND=WAZ_PURGE_MANUAL_GATE, jamais
# satisfaite ailleurs) - usage EXCLUSIVEMENT volontaire, depuis VM2 :
#   $APP_BIN/order.sh BEAC_003_SEED_LCBFT_BULK_LIVE "demo publique"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/beac_scenario_tools.sh"

SEED_COUNT="${LCBFT_DEMO_BULK_COUNT:-50}"
SEED_INTERVAL="${LCBFT_DEMO_BULK_INTERVAL_SEC:-2}"

echo "[BEAC_003_SEED_LCBFT_BULK_LIVE] Ecriture de ${SEED_COUNT} detections LCB-FT (nombre fixe, 1 toutes les ${SEED_INTERVAL}s) dans ${LCBFT_LOG_FILE}..."
SEED_LOG="$(mktemp)"
seed_lcbft_detections_file "$LCBFT_LOG_FILE" "$SEED_COUNT" "$SEED_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[BEAC_003_SEED_LCBFT_BULK_LIVE] ERREUR : l'ecriture a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[BEAC_003_SEED_LCBFT_BULK_LIVE] OK."
exit 0
