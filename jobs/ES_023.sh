#!/bin/bash
# ES_023 - WEF_ES_BLD_YMLTARGETCONF
# Isolation stricte sur 127.0.0.1, raccordement PKI, bootstrap.memory_lock.
set -uo pipefail
source "$VARS_FILE"
# Correctif 2026-08-14 : les chemins SSL pointaient directement sur PKI_DIR
# (coffre externe partage). Elasticsearch 8.19 bloque desormais la lecture
# SSL hors de /etc/elasticsearch (systeme "entitlements" du JDK) - voir le
# commentaire detaille dans ES_020.sh, qui copie ces 3 fichiers localement
# dans /etc/elasticsearch/certs avant que ce job n'ecrive le yml ci-dessous.
ES_LOCAL_CERTS="/etc/elasticsearch/certs"
echo "[ES_023] Ecriture de elasticsearch.yml..."
cat > /etc/elasticsearch/elasticsearch.yml << YMLEOF
cluster.name: ${PROJECT_NAME}
node.name: elk-node-1
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 127.0.0.1
http.port: ${ES_PORT}
transport.port: ${ES_TRANSPORT_PORT}
discovery.type: single-node
bootstrap.memory_lock: true
xpack.security.enabled: true
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.key: ${ES_LOCAL_CERTS}/factory_server.key
xpack.security.http.ssl.certificate: ${ES_LOCAL_CERTS}/factory_fullchain.pem
xpack.security.http.ssl.certificate_authorities: ${ES_LOCAL_CERTS}/factory_ca.crt
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.key: ${ES_LOCAL_CERTS}/factory_server.key
xpack.security.transport.ssl.certificate: ${ES_LOCAL_CERTS}/factory_fullchain.pem
xpack.security.transport.ssl.certificate_authorities: ${ES_LOCAL_CERTS}/factory_ca.crt
YMLEOF
chown "${ES_USER}:${ES_USER}" /etc/elasticsearch/elasticsearch.yml
echo "[ES_023] OK."
exit 0
