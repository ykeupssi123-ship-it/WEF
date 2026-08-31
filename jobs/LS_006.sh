#!/bin/bash
# LS_006 - WEF_LS_BLD_FWZONE - Zone etanche CollectZone
set -uo pipefail
source "$VARS_FILE"
if firewall-cmd --get-zones 2>/dev/null | grep -qw CollectZone; then
  echo "[LS_006] Zone CollectZone deja presente, ignore."
  echo "[LS_006] OK."
  exit 0
fi
echo "[LS_006] Creation de la zone CollectZone..."
firewall-cmd --permanent --new-zone=CollectZone || true
echo "[LS_006] OK."
exit 0
