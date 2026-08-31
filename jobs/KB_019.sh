#!/bin/bash
# KB_019 - WEF_KB_RUN_PORTPOLL - Verification de l'ecoute du port 5601
set -uo pipefail
source "$VARS_FILE"
echo "[KB_019] Attente de l'ouverture du port ${KB_PORT}..."
for i in $(seq 1 60); do
  netstat -tpln 2>/dev/null | grep -q ":${KB_PORT} " && { echo "[KB_019] OK."; exit 0; }
  sleep 5
done
echo "[KB_019] ERREUR : le port ${KB_PORT} n'est jamais passe en ecoute."
exit 1
