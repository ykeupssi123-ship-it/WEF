#!/bin/bash
# WAZ_049G_PURGE_CYRIELLEMONEY - WEF_WAZ_RUN_PURGECYRIELLE
# Nettoyage complet du scenario CyrielleMoney : vide l'index
# "${CYRIELLEMONEY_INDEX_PREFIX}-*" dans Elasticsearch ET vide
# CYRIELLEMONEY_LOG_FILE. DESTRUCTEUR ET IRREVERSIBLE - jamais dans la
# chaine automatique.
#
# AJOUTE LE 2026-09-13 (demande explicite utilisateur, meme mecanique
# que WAZ_046/WAZ_047/WAZ_049C/WAZ_049E). IN_COND=WAZ_PURGE_MANUAL_GATE
# (jamais satisfaite ailleurs) - usage EXCLUSIVEMENT volontaire :
#   $APP_BIN/order.sh WAZ_049G_PURGE_CYRIELLEMONEY "fin demo CyrielleMoney"
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_049G_PURGE_CYRIELLEMONEY] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"

echo "[WAZ_049G_PURGE_CYRIELLEMONEY] Purge de ${CYRIELLEMONEY_INDEX_PREFIX}-* dans Elasticsearch..."
PURGE_LOG="$(mktemp)"
purge_index_pattern "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" "${PKI_DIR}/factory_ca.crt" "${CYRIELLEMONEY_INDEX_PREFIX}-*" > "$PURGE_LOG" 2>&1
PURGE_EXIT=$?
cat "$PURGE_LOG"
if [ $PURGE_EXIT -ne 0 ]; then
  echo "[WAZ_049G_PURGE_CYRIELLEMONEY] ERREUR : la purge a echoue (voir sortie ci-dessus)." >&2
  rm -f "$PURGE_LOG"
  exit 1
fi
rm -f "$PURGE_LOG"

if [ -f "$CYRIELLEMONEY_LOG_FILE" ]; then
  echo "[WAZ_049G_PURGE_CYRIELLEMONEY] Vidage de ${CYRIELLEMONEY_LOG_FILE}..."
  : > "$CYRIELLEMONEY_LOG_FILE"
fi

echo "[WAZ_049G_PURGE_CYRIELLEMONEY] OK."
exit 0
