#!/bin/bash
# KB_008 - WEF_KB_BLD_FWAPPLY - Fixation persistante des regles
set -uo pipefail
source "$VARS_FILE"
echo "[KB_008] Rechargement de firewalld..."
firewall-cmd --reload
echo "[KB_008] OK."
exit 0
