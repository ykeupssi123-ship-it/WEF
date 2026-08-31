#!/bin/bash
# WAZ_033 - WEF_WAZ_BLD_DAEMONLOCKED - Figeage de la configuration globale
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_033] Rechargement final du daemon..."
systemctl daemon-reload
echo "[WAZ_033] OK."
exit 0
