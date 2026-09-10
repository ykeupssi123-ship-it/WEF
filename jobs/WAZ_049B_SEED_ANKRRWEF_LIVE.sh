#!/bin/bash
# WAZ_049B_SEED_ANKRRWEF_LIVE - WEF_WAZ_RUN_SEEDANKRRWEF
# Demo : remplissage visible (1 transaction/s) de l'index "AnkrrWEF"
# dans Elasticsearch - simule une application METIER distincte de Wazuh
# (transfert d'argent : microservices remittance/billpay sur
# Glassfish/Tomcat), pour montrer ELK supervisant une vraie application
# cliente plutot que de la securite.
#
# AJOUTE LE 2026-09-10 (demande explicite utilisateur) : distinct de
# WAZ_049_SEED_ES_LIVE (qui simule de FAUSSES alertes Wazuh dans
# Elasticsearch) - ici, aucune alerte, uniquement des evenements de
# transaction (jobs/lib/test_data_tools.sh, seed_ankrrwef_transactions_live).
# JAMAIS dans la chaine automatique (IN_COND=WAZ_PURGE_MANUAL_GATE,
# jamais satisfaite ailleurs) - usage EXCLUSIVEMENT volontaire :
#   $APP_BIN/order.sh WAZ_049B_SEED_ANKRRWEF_LIVE "demo AnkrrWEF"
# Chaque document porte "wef_test_seed": true - jamais confondu avec un
# vrai evenement.
#
# LIMITE HONNETE : l'index "AnkrrWEF" est fixe (pas de rotation
# quotidienne comme "log-*"/ES_INDEX_NAME_PREFIX) - creez le Data View
# Kibana "AnkrrWEF" manuellement au premier essai (Kibana ne le propose
# qu'une fois l'index cree, donc apres le premier document insere).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_049B_SEED_ANKRRWEF_LIVE] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"
SEED_COUNT="${WAZ_DEMO_SEED_COUNT:-100}"
SEED_INTERVAL="${WAZ_DEMO_SEED_INTERVAL_SEC:-1}"
INDEX_NAME="AnkrrWEF"

echo "[WAZ_049B_SEED_ANKRRWEF_LIVE] Remplissage visible de ${SEED_COUNT} transactions (1 toutes les ${SEED_INTERVAL}s) dans Elasticsearch (${INDEX_NAME})..."
SEED_LOG="$(mktemp)"
seed_ankrrwef_transactions_live "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" "${PKI_DIR}/factory_ca.crt" "$INDEX_NAME" "$SEED_COUNT" "$SEED_INTERVAL" > "$SEED_LOG" 2>&1
SEED_EXIT=$?
cat "$SEED_LOG"
if [ $SEED_EXIT -ne 0 ]; then
  echo "[WAZ_049B_SEED_ANKRRWEF_LIVE] ERREUR : le remplissage a echoue (voir sortie ci-dessus)." >&2
  rm -f "$SEED_LOG"
  exit 1
fi
rm -f "$SEED_LOG"

echo "[WAZ_049B_SEED_ANKRRWEF_LIVE] OK."
exit 0
