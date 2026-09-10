#!/bin/bash
# WAZ_049C_PURGE_ANKRRWEF - WEF_WAZ_RUN_PURGEANKRRWEF
# Vide EN UNE FOIS toutes les transactions de demo de l'index
# "AnkrrWEF" dans Elasticsearch. DESTRUCTEUR ET IRREVERSIBLE - jamais
# dans la chaine automatique.
#
# AJOUTE LE 2026-09-10 (demande explicite utilisateur, pendant AnkrrWEF
# : nettoyage apres demo, meme mecanique que WAZ_046/WAZ_047).
# IN_COND=WAZ_PURGE_MANUAL_GATE (jamais satisfaite ailleurs) - usage
# EXCLUSIVEMENT volontaire :
#   $APP_BIN/order.sh WAZ_049C_PURGE_ANKRRWEF "fin demo AnkrrWEF"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_049C_PURGE_ANKRRWEF] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"

echo "[WAZ_049C_PURGE_ANKRRWEF] Purge de l'index AnkrrWEF dans Elasticsearch..."
PURGE_LOG="$(mktemp)"
purge_index_pattern "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" "${PKI_DIR}/factory_ca.crt" "AnkrrWEF" > "$PURGE_LOG" 2>&1
PURGE_EXIT=$?
cat "$PURGE_LOG"
if [ $PURGE_EXIT -ne 0 ]; then
  echo "[WAZ_049C_PURGE_ANKRRWEF] ERREUR : la purge a echoue (voir sortie ci-dessus)." >&2
  rm -f "$PURGE_LOG"
  exit 1
fi
rm -f "$PURGE_LOG"

echo "[WAZ_049C_PURGE_ANKRRWEF] OK."
exit 0
