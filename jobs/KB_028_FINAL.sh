#!/bin/bash
# KB_028_FINAL - WEF_KB_BLD_LOCKCONF - Scellage complet de l'interface
# Se declenche apres LS_RULES_LOCKED (Logstash verrouille en premier).
set -uo pipefail
source "$VARS_FILE"
if lsattr /etc/kibana/kibana.yml 2>/dev/null | grep -q "^----i"; then
  echo "[KB_028_FINAL] Configuration deja immuable, ignore."
  echo "[KB_028_FINAL] OK."
  exit 0
fi
echo "[KB_028_FINAL] Verrouillage immuable de kibana.yml..."
chattr +i /etc/kibana/kibana.yml
echo "[KB_028_FINAL] OK."
exit 0
