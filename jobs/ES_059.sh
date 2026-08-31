#!/bin/bash
# ES_059 - WEF_ES_BLD_CFGLOCK - Verrou LOCAL, provisoire (config ES uniquement)
# Empeche toute alteration humaine ou derive de configuration reseau en RUN.
# Distinct de ES_059_FINAL (scellement global du coffre PKI partage, qui
# attend que Logstash confirme ne plus avoir besoin d'y ecrire).
set -uo pipefail
source "$VARS_FILE"
if lsattr /etc/elasticsearch/elasticsearch.yml 2>/dev/null | grep -q "^----i"; then
  echo "[ES_059] elasticsearch.yml deja immuable, ignore."
  echo "[ES_059] OK."
  exit 0
fi
echo "[ES_059] Passage de elasticsearch.yml en mode immuable..."
chattr +i /etc/elasticsearch/elasticsearch.yml
echo "[ES_059] OK."
exit 0
