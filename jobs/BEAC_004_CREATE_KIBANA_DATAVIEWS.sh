#!/bin/bash
# BEAC_004_CREATE_KIBANA_DATAVIEWS - WEF_BEAC_BLD_KBDATAVIEWS
#
# Cree automatiquement, dans Kibana, un Data View par prefixe d'index
# autorise dans ES_DEMO_INDEX_PREFIXES (vars.conf) - sans ce job, un
# index cree cote Elasticsearch (ex: ambargo-2026.09.13) n'apparait PAS
# tout seul dans le selecteur "Data view" de Discover : Kibana a besoin
# d'un objet dedie (Data View, ex-"index pattern"), jamais cree
# automatiquement par un simple envoi Logstash/Elasticsearch.
#
# Ajoute le 2026-09-13, suite a une capture d'ecran reelle montrant que
# seuls "All logs" et "Wazuh Alerts" apparaissaient dans le selecteur,
# malgre des documents deja presents dans ambargo-*.
#
# Generique et non code en dur : lit ES_DEMO_INDEX_PREFIXES (la meme
# liste blanche que jobs/ES_041.sh) et cree un data view par prefixe -
# tout nouveau prefixe ajoute a cette ligne de vars.conf devient donc
# visible dans Kibana sans toucher a ce script.
#
# Idempotent : un "id" deterministe par prefixe + "override":true
# evitent toute erreur si le job est rejoue (ex: apres l'ajout d'un
# nouveau prefixe).
set -uo pipefail
source "$VARS_FILE"

BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[BEAC_004_CREATE_KIBANA_DATAVIEWS] ERREUR : $BOOTSTRAP_PW_FILE absent (ES_022 doit avoir tourne sur ELK_HOST)."; exit 1; }
BOOTSTRAP_PW="$(cat "$BOOTSTRAP_PW_FILE")"

if [ -z "${ES_DEMO_INDEX_PREFIXES:-}" ]; then
  echo "[BEAC_004_CREATE_KIBANA_DATAVIEWS] ES_DEMO_INDEX_PREFIXES est vide : rien a creer (normal sur une installation sans scenario metier actif)."
  exit 0
fi

FAILED=0
IFS=',' read -ra PREFIXES <<< "$ES_DEMO_INDEX_PREFIXES"
for raw_prefix in "${PREFIXES[@]}"; do
  prefix="$(echo "$raw_prefix" | xargs)"
  [ -z "$prefix" ] && continue

  echo "[BEAC_004_CREATE_KIBANA_DATAVIEWS] Data view '${prefix}-*'..."
  RESP_FILE="$(mktemp)"
  HTTP_CODE=$(curl -sk -u "elastic:${BOOTSTRAP_PW}" \
    -X POST "https://127.0.0.1:${KB_PORT}/api/data_views/data_view" \
    -H "kbn-xsrf: true" -H "Content-Type: application/json" \
    -d "{\"data_view\":{\"id\":\"${prefix}-dataview\",\"title\":\"${prefix}-*\",\"name\":\"${prefix}\",\"timeFieldName\":\"@timestamp\"},\"override\":true}" \
    -o "$RESP_FILE" -w "%{http_code}")

  if [ "$HTTP_CODE" != "200" ]; then
    echo "[BEAC_004_CREATE_KIBANA_DATAVIEWS] ERREUR pour '${prefix}-*' (HTTP ${HTTP_CODE}) :" >&2
    cat "$RESP_FILE" >&2
    FAILED=1
  else
    echo "[BEAC_004_CREATE_KIBANA_DATAVIEWS] OK : '${prefix}-*' visible dans Discover."
  fi
  rm -f "$RESP_FILE"
done

[ $FAILED -eq 0 ] && exit 0
exit 1
