#!/bin/bash
# ES_060 - WEF_ES_BLD_DMNRELOAD - Figeage definitif du systeme
set -uo pipefail
source "$VARS_FILE"
echo "[ES_060] Rechargement final du daemon systemd..."
systemctl daemon-reload
echo "[ES_060] OK."
exit 0
