#!/bin/bash
# WAZ_027 - WEF_WAZ_RUN_CRASHTEST - Arret brutal du manager (crash test)
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_027] Destruction du processus d'analyse (crash-test)..."
pkill -9 ossec-analysisd || true
sleep 2
echo "[WAZ_027] OK."
exit 0
