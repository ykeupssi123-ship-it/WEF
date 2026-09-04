#!/bin/bash
# WAZ_021_RECOVER - WEF_WAZ_BLD_RCVRNET - Levee des barrieres reseau
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_021_RECOVER] Retablissement du reseau..."
iptables -F OUTPUT
echo "[WAZ_021_RECOVER] OK."
exit 0
