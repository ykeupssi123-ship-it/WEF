#!/bin/bash
# WAZ_035C_REROUTE_PIPELINE_ES - WEF_WAZ_BLD_RRUTPIPES
# Aiguillage : reecrit le pipeline Logstash dedie (WAZ_014B) pour que
# TOUTE alerte FUTURE parte vers Elasticsearch au lieu de wazuh-indexer.
# Ne touche jamais la SOURCE du pipeline (/var/ossec/logs/alerts/
# alerts.json, toujours la meme, WAZ_014B) - uniquement sa DESTINATION.
#
# AJOUTE LE 2026-09-03 (refonte demandee par l'utilisateur, voir
# docs/JOURNAL_TECHNIQUE.md, decoupage du monolithique
# WAZ_035_MODE_CONVERGENT.sh d'origine - logique de reecriture du
# pipeline reprise a l'identique, seulement extraite dans son propre
# job pour etre individuellement gelable via SKIP_JOBS).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

LS_CERTS="/etc/logstash/certs"
PIPELINE_CONF="/etc/logstash/wazuh-alerts.conf"
local_pki_copy "$LS_CERTS" "${LS_USER}:${LS_USER}"

if [ "${ES_AUTH_MODE:-token}" = "password" ]; then
  ES_OUT_AUTH_LINES="    user => \"factory_ingest_user\"
    password => \"\${factory_ingest_password}\""
else
  ES_OUT_AUTH_LINES="    api_key => \"\${factory_ingest_token}\""
fi

echo "[WAZ_035C_REROUTE_PIPELINE_ES] Ecriture de ${PIPELINE_CONF} (destination -> Elasticsearch classique)..."
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
  elasticsearch {
    hosts => ["https://127.0.0.1:${ES_PORT}"]
${ES_OUT_AUTH_LINES}
    ssl_certificate_authorities => ["${LS_CERTS}/factory_ca.crt"]
    index => "wazuh-alerts-4.x-%{+YYYY.MM.dd}"
  }
}
CONFEOF
chown "${LS_USER}:${LS_USER}" "$PIPELINE_CONF"
chmod 640 "$PIPELINE_CONF"

if ! grep -q "127.0.0.1:${ES_PORT}" "$PIPELINE_CONF"; then
  echo "[WAZ_035C_REROUTE_PIPELINE_ES] ERREUR : la reecriture du pipeline a echoue (destination attendue non retrouvee apres ecriture)." >&2
  exit 1
fi

echo "[WAZ_035C_REROUTE_PIPELINE_ES] Redemarrage de logstash (prise en compte de la nouvelle destination)..."
systemctl restart logstash 2>/dev/null || true
if ! wait_for_service_active logstash 120 5; then
  echo "[WAZ_035C_REROUTE_PIPELINE_ES] ERREUR : logstash.service n'a pas redemarre. Diagnostic :" >&2
  journalctl -u logstash -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_035C_REROUTE_PIPELINE_ES] OK."
exit 0
