#!/bin/bash
# WAZ_035B_CUT_INDEXER_TO_ES - WEF_WAZ_RUN_CUTIDX2ES
# Coupure reelle : transfert (coupe, non copie) de l'historique des
# alertes wazuh-indexer -> Elasticsearch. A la fin de ce job, les
# documents ne subsistent QUE cote Elasticsearch (verifie, jamais
# suppose - voir jobs/lib/cut_migrate.sh pour la sequence exacte :
# jamais de suppression avant confirmation stricte de la copie complete).
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md, decoupage du monolithique
# WAZ_035_MODE_CONVERGENT.sh d'origine). Doit tourner APRES WAZ_035A
# (jobs dependants deja mis en pause) et AVANT WAZ_035D (arret effectif
# de wazuh-indexer) - il faut que l'indexeur soit encore JOIGNABLE pour
# pouvoir en lire le contenu.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/es_admin_curl.sh"
source "$PROJECT_ROOT/jobs/lib/cut_migrate.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_035B_CUT_INDEXER_TO_ES] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"

echo "[WAZ_035B_CUT_INDEXER_TO_ES] Verification reelle qu'Elasticsearch (destination) est joignable et authentifie..."
HTTP_CODE=$(es_admin_curl -o /dev/null -w '%{http_code}' "https://127.0.0.1:${ES_PORT}/_cluster/health" 2>/dev/null)
if [ "$HTTP_CODE" != "200" ]; then
  echo "[WAZ_035B_CUT_INDEXER_TO_ES] ERREUR : Elasticsearch injoignable ou authentification en echec (HTTP ${HTTP_CODE})." >&2
  exit 1
fi

echo "[WAZ_035B_CUT_INDEXER_TO_ES] Verification reelle que wazuh-indexer (source) est joignable..."
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --cacert "${PKI_DIR}/factory_ca.crt" -u "${WAZ_INDEXER_ADMIN_USER}:${WAZUH_INDEXER_ADMIN_PW}" "https://127.0.0.1:${WAZ_INDEXER_PORT}/_cluster/health" 2>/dev/null)
if [ "$HTTP_CODE" != "200" ]; then
  echo "[WAZ_035B_CUT_INDEXER_TO_ES] ERREUR : wazuh-indexer injoignable ou authentification en echec (HTTP ${HTTP_CODE})." >&2
  exit 1
fi

echo "[WAZ_035B_CUT_INDEXER_TO_ES] Coupure de l'historique (wazuh-indexer -> Elasticsearch)..."
MIGRATION_LOG="$(mktemp)"
cut_migrate_alerts \
  "https://127.0.0.1:${WAZ_INDEXER_PORT}" "${WAZ_INDEXER_ADMIN_USER}" "${WAZUH_INDEXER_ADMIN_PW}" \
  "https://127.0.0.1:${ES_PORT}" "elastic" "${ES_BOOTSTRAP_PW}" \
  "${PKI_DIR}/factory_ca.crt" "wazuh-alerts-4.x-*" \
  > "$MIGRATION_LOG" 2>&1
CUT_EXIT=$?
cat "$MIGRATION_LOG"
if [ $CUT_EXIT -ne 0 ]; then
  echo "[WAZ_035B_CUT_INDEXER_TO_ES] ERREUR : la coupure de l'historique a echoue (voir sortie ci-dessus)." >&2
  rm -f "$MIGRATION_LOG"
  exit 1
fi
rm -f "$MIGRATION_LOG"

echo "[WAZ_035B_CUT_INDEXER_TO_ES] OK."
exit 0
