#!/bin/bash
# PKI_001 - WEF_PKI_BLD_GRPNEW
# Creation du groupe de confiance partage de l'usine (droits de lecture
# communs a Elasticsearch, Logstash, Kibana, Filebeat, Metricbeat, Wazuh).
set -uo pipefail
source "$VARS_FILE"

echo "[PKI_001] Creation du groupe partage ${CRYPTO_GROUP}..."
getent group "${CRYPTO_GROUP}" >/dev/null || groupadd -r "${CRYPTO_GROUP}"
echo "[PKI_001] OK."
exit 0
