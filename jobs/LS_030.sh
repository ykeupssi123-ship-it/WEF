#!/bin/bash
# LS_030 - WEF_LS_RUN_INJECTRAW - Agression de la prise en mode isole
#
# CORRECTIF 2026-08-18 : injection en local, directement sur le port reel
# d'ecoute de Logstash (LS_SYSLOG_INTERNAL_PORT, voir vars.conf/LS_020) et
# non plus sur la facade publique 514. 514 n'est desormais qu'une
# redirection pare-feu (LS_007) vers ce port interne - un test local n'a
# aucune raison de passer par cette redirection.
set -uo pipefail
source "$VARS_FILE"
echo "[LS_030] Injection de 5000 logs Syslog de test via le port ${LS_SYSLOG_INTERNAL_PORT}..."
for i in $(seq 1 5000); do
  logger -n 127.0.0.1 -P ${LS_SYSLOG_INTERNAL_PORT} -t factory-test "stress-test-event-${i}"
done
echo "[LS_030] OK."
exit 0
