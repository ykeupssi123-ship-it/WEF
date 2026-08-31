#!/bin/bash
# LS_009 - WEF_LS_BLD_FWAPPLY - Fixation persistante des regles
set -uo pipefail
source "$VARS_FILE"
echo "[LS_009] Rechargement de firewalld..."
firewall-cmd --reload
echo "[LS_009] OK."
exit 0
