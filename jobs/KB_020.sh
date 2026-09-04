#!/bin/bash
# KB_020 - WEF_KB_RUN_UIHEALTH - Polling de l'API de statut interne
set -uo pipefail
source "$VARS_FILE"
echo "[KB_020] Verification du statut Kibana..."
for i in $(seq 1 60); do
  curl -sk "https://127.0.0.1:${KB_PORT}/api/status" -o /dev/null && { echo "[KB_020] OK."; exit 0; }
  sleep 5
done
echo "[KB_020] ERREUR : timeout sur /api/status."
exit 1
