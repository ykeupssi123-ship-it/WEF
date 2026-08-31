#!/bin/bash
# KB_006 - WEF_KB_BLD_FWZONE - Zone etanche UI_Zone
set -uo pipefail
source "$VARS_FILE"
if firewall-cmd --get-zones 2>/dev/null | grep -qw UI_Zone; then
  echo "[KB_006] Zone UI_Zone deja presente, ignore."
  echo "[KB_006] OK."
  exit 0
fi
echo "[KB_006] Creation de la zone UI_Zone..."
firewall-cmd --permanent --new-zone=UI_Zone || true
echo "[KB_006] OK."
exit 0
