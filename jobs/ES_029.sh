#!/bin/bash
# ES_029 - WEF_ES_RUN_SOCKETSYSLOG - Pipeline Syslog RFC5424
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_029] Injection du pipeline syslog_universal..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ingest/pipeline/syslog_universal" \
  -H "Content-Type: application/json" -d '{
    "description": "Ingestion Syslog RFC5424 - usine",
    "processors": [
      {"grok": {"field": "message", "patterns": ["<%{POSINT:priority}>%{SYSLOGTIMESTAMP:timestamp} %{SYSLOGHOST:host} %{DATA:program}(?:\\[%{POSINT:pid}\\])?: %{GREEDYDATA:syslog_message}"], "ignore_failure": true}},
      {"set": {"field": "factory_pipeline", "value": "syslog_universal"}}
    ]
  }' -o ${WORK_TMP_DIR}/es029.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es029.json && { echo "[ES_029] OK."; rm -f ${WORK_TMP_DIR}/es029.json; exit 0; }
echo "[ES_029] ERREUR, voir ${WORK_TMP_DIR}/es029.json"; exit 1
