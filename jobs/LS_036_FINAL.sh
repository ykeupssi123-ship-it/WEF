#!/bin/bash
# LS_036_FINAL - WEF_LS_BLD_IMMTBLRULES - Verrouillage immuable des regles
# JOB PASSERELLE (ouvre vers KB). Se declenche apres KB_ROTATE_OK (Kibana
# valide) pour ne jamais figer la config Logstash avant que Kibana ait
# fini de la consommer/verifier.
set -uo pipefail
source "$VARS_FILE"
if lsattr /etc/logstash/logstash.yml 2>/dev/null | grep -q "^----i"; then
  echo "[LS_036_FINAL] Configuration deja immuable, ignore."
  echo "[LS_036_FINAL] OK."
  exit 0
fi
echo "[LS_036_FINAL] Verrouillage immuable de la configuration Logstash..."
chattr +i /etc/logstash/conf.d/*.conf /etc/logstash/logstash.yml
echo "[LS_036_FINAL] OK."
exit 0
