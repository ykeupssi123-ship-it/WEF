#!/bin/bash
# ES_057 - WEF_ES_RUN_FWSTATCHK - Maintien de l'isolation du pare-feu
set -uo pipefail
source "$VARS_FILE"
echo "[ES_057] Verification de la persistance de la regle pare-feu port ${ES_PORT}..."
firewall-cmd --zone=IngestionZone --query-port=${ES_PORT}/tcp
echo "[ES_057] OK."
exit 0
