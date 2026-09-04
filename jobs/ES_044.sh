#!/bin/bash
# ES_044 - WEF_ES_RUN_OPENFILESVERIFY - Verification reelle des descripteurs
set -uo pipefail
source "$VARS_FILE"
PID=$(pgrep -f "org.elasticsearch.bootstrap.Elasticsearch" | head -1)
if [ -z "$PID" ]; then
  echo "[ES_044] ERREUR : processus Elasticsearch introuvable."
  exit 1
fi
LIMIT=$(cat /proc/${PID}/limits 2>/dev/null | awk '/Max open files/{print $4}')
echo "[ES_044] Limite de descripteurs constatee : ${LIMIT:-inconnue}."
if [ -n "$LIMIT" ] && [ "$LIMIT" -lt 65536 ] 2>/dev/null; then
  echo "[ES_044] AVERTISSEMENT : limite inferieure a 65536."
fi
echo "[ES_044] OK."
exit 0
