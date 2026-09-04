#!/bin/bash
# WAZ_036_KIBANA_INDEX - WEF_WAZ_RUN_KBIDXNEW
# Cree/attache l'index pattern Kibana pour les alertes Wazuh, une fois
# le routage bascule vers Logstash/Elasticsearch (mode convergent).
# Utilise le meme compte superutilisateur 'elastic' + mot de passe
# bootstrap (arme par ES_022) que jobs/lib/es_admin_curl.sh, ici pointe
# vers l'API Kibana au lieu de l'API Elasticsearch.
set -uo pipefail
source "$VARS_FILE"

BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[WAZ_036_KIBANA_INDEX] ERREUR : $BOOTSTRAP_PW_FILE absent (ES_022 doit avoir tourne sur ELK_HOST)."; exit 1; }

echo "[WAZ_036_KIBANA_INDEX] Creation du data view 'wazuh-alerts-*' dans Kibana..."
curl -s -k -u "elastic:$(cat "$BOOTSTRAP_PW_FILE")" \
  -X POST "https://${FACTORY_HOST_IP}:${KB_PORT}/api/data_views/data_view" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d '{"data_view":{"title":"wazuh-alerts-*","name":"Wazuh Alerts","timeFieldName":"@timestamp"}}' \
  -o /dev/null -w "[WAZ_036_KIBANA_INDEX] HTTP %{http_code}\n"
echo "[WAZ_036_KIBANA_INDEX] OK."
exit 0
