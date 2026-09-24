#!/bin/bash
# KB_030_GENERIC_LOG_DATAVIEW - WEF_KB_RUN_LOGDATAVIEW
#
# Cree le Data View Kibana pour l'index generique catch-all
# "${ES_INDEX_NAME_PREFIX}-*" (defaut "log", jobs/LS_024.sh:47/96) - la
# ou atterrissent tous les evenements qui ne sont ni Wazuh (deja couvert
# par WAZ_036_KIBANA_INDEX), ni un scenario metier BEAC dedie (LCB-FT/
# CyrielleMoney/ambargo, deja couverts par jobs/BEAC_004_CREATE_KIBANA_
# DATAVIEWS.sh) - notamment Filebeat/Metricbeat generiques (agents
# Windows/Linux hors scenario metier).
#
# AJOUTE LE 2026-09-24 (incident reel : Filebeat/Metricbeat actifs sur
# la machine Windows physique de l'operateur, donnees bien recues par
# Logstash, mais AUCUN Data View Kibana ne pointait vers "log-*" -
# Discover n'affichait que "All logs"/"ambargo"/"cyriellemoney"/"Wazuh
# Alerts", jamais l'index generique. Meme cause de fond deja documentee
# dans BEAC_004 : un index Elasticsearch qui recoit des documents
# n'apparait jamais tout seul dans Discover, Kibana a besoin d'un objet
# Data View dedie.
#
# Meme mecanisme que WAZ_036_KIBANA_INDEX (data view UNIQUE, pas une
# liste - ES_INDEX_NAME_PREFIX est un scalaire dans vars.conf, jamais
# une liste comme ES_DEMO_INDEX_PREFIXES) : "id" deterministe +
# "override":true, idempotent, rejouable sans erreur.
set -uo pipefail
source "$VARS_FILE"

BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[KB_030_GENERIC_LOG_DATAVIEW] ERREUR : $BOOTSTRAP_PW_FILE absent (ES_022 doit avoir tourne sur ELK_HOST)."; exit 1; }

PREFIX="${ES_INDEX_NAME_PREFIX:-log}"

echo "[KB_030_GENERIC_LOG_DATAVIEW] Data view '${PREFIX}-*'..."
RESP_FILE="$(mktemp)"
HTTP_CODE=$(curl -sk -u "elastic:$(cat "$BOOTSTRAP_PW_FILE")" \
  -X POST "https://127.0.0.1:${KB_PORT}/api/data_views/data_view" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -d "{\"data_view\":{\"id\":\"${PREFIX}-dataview\",\"title\":\"${PREFIX}-*\",\"name\":\"Logs generiques\",\"timeFieldName\":\"@timestamp\"},\"override\":true}" \
  -o "$RESP_FILE" -w "%{http_code}")

if [ "$HTTP_CODE" != "200" ]; then
  echo "[KB_030_GENERIC_LOG_DATAVIEW] ERREUR (HTTP ${HTTP_CODE}) :" >&2
  cat "$RESP_FILE" >&2
  rm -f "$RESP_FILE"
  exit 1
fi
rm -f "$RESP_FILE"
echo "[KB_030_GENERIC_LOG_DATAVIEW] OK : '${PREFIX}-*' visible dans Discover."
exit 0
