#!/bin/bash
# WAZ_039B_REROUTE_PIPELINE_INDEXER - WEF_WAZ_BLD_RRUTPIPIDX
# Aiguillage : reecrit le pipeline Logstash dedie (WAZ_014B) pour que
# TOUTE alerte FUTURE reparte vers wazuh-indexer (destination d'origine)
# au lieu d'Elasticsearch. Miroir exact de WAZ_035C_REROUTE_PIPELINE_ES.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md, decoupage du monolithique
# WAZ_039_MODE_SOUVERAIN.sh d'origine - logique de reecriture du
# pipeline reprise a l'identique).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9200}"
LS_CERTS="/etc/logstash/certs"
PIPELINE_CONF="/etc/logstash/wazuh-alerts.conf"
local_pki_copy "$LS_CERTS" "${LS_USER}:${LS_USER}"

echo "[WAZ_039B_REROUTE_PIPELINE_INDEXER] Ecriture de ${PIPELINE_CONF} (destination -> wazuh-indexer, etat d'origine)..."
cat > "$PIPELINE_CONF" << CONFEOF
input {
  file {
    path => "/var/ossec/logs/alerts/alerts.json"
    start_position => "beginning"
    sincedb_path => "/var/lib/logstash/sincedb_wazuh_alerts"
    codec => "json"
  }
}
output {
  http {
    url => "https://127.0.0.1:${WAZ_INDEXER_PORT}/wazuh-alerts-4.x-%{+YYYY.MM.dd}/_doc"
    http_method => "post"
    format => "json"
    user => "${WAZ_INDEXER_ADMIN_USER}"
    password => "\${wazuh_indexer_admin_password}"
    cacert => "${LS_CERTS}/factory_ca.crt"
    retry_non_idempotent => true
  }
}
CONFEOF
chown "${LS_USER}:${LS_USER}" "$PIPELINE_CONF"
chmod 640 "$PIPELINE_CONF"

if ! grep -q "127.0.0.1:${WAZ_INDEXER_PORT}" "$PIPELINE_CONF"; then
  echo "[WAZ_039B_REROUTE_PIPELINE_INDEXER] ERREUR : la reecriture du pipeline a echoue (destination attendue non retrouvee apres ecriture)." >&2
  exit 1
fi

echo "[WAZ_039B_REROUTE_PIPELINE_INDEXER] Redemarrage de logstash (prise en compte de la destination d'origine)..."
systemctl restart logstash 2>/dev/null || true
if ! wait_for_service_active logstash 120 5; then
  echo "[WAZ_039B_REROUTE_PIPELINE_INDEXER] ERREUR : logstash.service n'a pas redemarre. Diagnostic :" >&2
  journalctl -u logstash -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_039B_REROUTE_PIPELINE_INDEXER] OK."
exit 0
