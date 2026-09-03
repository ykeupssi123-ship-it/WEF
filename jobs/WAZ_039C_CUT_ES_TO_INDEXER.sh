#!/bin/bash
# WAZ_039C_CUT_ES_TO_INDEXER - WEF_WAZ_RUN_CUTES2IDX
# Coupure reelle inverse : transfert (coupe, non copie) de l'historique
# accumule dans Elasticsearch pendant le mode Kibana -> wazuh-indexer. A
# la fin de ce job, les documents ne subsistent QUE cote wazuh-indexer -
# Kibana doit alors montrer l'index wazuh-alerts-4.x-* comme vide/down
# (preuve indirecte de la coupure reelle, jamais juste supposee).
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md, decoupage du monolithique
# WAZ_039_MODE_SOUVERAIN.sh d'origine). Miroir exact de
# WAZ_035B_CUT_INDEXER_TO_ES (source/destination inversees) - meme
# fonction partagee jobs/lib/cut_migrate.sh.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/es_admin_curl.sh"
source "$PROJECT_ROOT/jobs/lib/cut_migrate.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_039C_CUT_ES_TO_INDEXER] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"

echo "[WAZ_039C_CUT_ES_TO_INDEXER] Verification reelle que wazuh-indexer (destination) est joignable..."
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --cacert "${PKI_DIR}/factory_ca.crt" -u "${WAZ_INDEXER_ADMIN_USER}:${WAZUH_INDEXER_ADMIN_PW}" "https://127.0.0.1:${WAZ_INDEXER_PORT}/_cluster/health" 2>/dev/null)
if [ "$HTTP_CODE" != "200" ]; then
  echo "[WAZ_039C_CUT_ES_TO_INDEXER] ERREUR : wazuh-indexer injoignable ou authentification en echec (HTTP ${HTTP_CODE})." >&2
  exit 1
fi

echo "[WAZ_039C_CUT_ES_TO_INDEXER] Coupure de l'historique (Elasticsearch -> wazuh-indexer)..."
MIGRATION_LOG="$(mktemp)"
cut_migrate_alerts \
  "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" \
  "https://127.0.0.1:${WAZ_INDEXER_PORT}" "${WAZ_INDEXER_ADMIN_USER}" "${WAZUH_INDEXER_ADMIN_PW}" \
  "${PKI_DIR}/factory_ca.crt" "wazuh-alerts-4.x-*" \
  > "$MIGRATION_LOG" 2>&1
CUT_EXIT=$?
cat "$MIGRATION_LOG"
if [ $CUT_EXIT -ne 0 ]; then
  echo "[WAZ_039C_CUT_ES_TO_INDEXER] ERREUR : la coupure de l'historique a echoue (voir sortie ci-dessus)." >&2
  rm -f "$MIGRATION_LOG"
  exit 1
fi
rm -f "$MIGRATION_LOG"

echo "[WAZ_039C_CUT_ES_TO_INDEXER] OK."
exit 0
