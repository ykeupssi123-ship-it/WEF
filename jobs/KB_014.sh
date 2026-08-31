#!/bin/bash
# KB_014 - WEF_KB_BLD_TLSENABLE - Raccordement HTTPS de l'UI
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
# Copie locale des certs (voir lib/commun.sh) - meme reflexe de prudence
# que pour Elasticsearch/Logstash, faite avant le test d'idempotence
# ci-dessous pour rester correcte meme si ce job est rejoue seul.
local_pki_copy "/etc/kibana/certs" "${KB_USER}:${KB_USER}"
if grep -q "^server.ssl.enabled:" /etc/kibana/kibana.yml 2>/dev/null; then
  echo "[KB_014] TLS deja configure, ignore."
  echo "[KB_014] OK."
  exit 0
fi
echo "[KB_014] Configuration TLS de l'interface..."
cat >> /etc/kibana/kibana.yml << YMLEOF
server.ssl.enabled: true
server.ssl.certificate: /etc/kibana/certs/factory_fullchain.pem
server.ssl.key: /etc/kibana/certs/factory_server.key
YMLEOF
echo "[KB_014] OK."
exit 0
