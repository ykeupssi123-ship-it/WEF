#!/bin/bash
# LS_032 - WEF_LS_RUN_DLQVERIFY - Injection d'un log corrompu
#
# CORRECTIF 2026-08-18 : meme raison que LS_030 - cible directement le
# port reel d'ecoute de Logstash (LS_SYSLOG_INTERNAL_PORT), pas la
# facade publique 514 (desormais une simple redirection pare-feu).
set -uo pipefail
source "$VARS_FILE"
echo "[LS_032] Injection d'un payload JSON structurellement brise..."
echo '{"broken_json": TRUE_NOT_QUOTED,,, }' | logger -n 127.0.0.1 -P ${LS_SYSLOG_INTERNAL_PORT} -t factory-dlq-test
sleep 5
if find /var/lib/logstash/dlq -type f -newer /tmp -mmin -1 2>/dev/null | grep -q .; then
  echo "[LS_032] Log toxique isole dans la DLQ."
fi
echo "[LS_032] OK."
exit 0
