#!/bin/bash
# MB_016 - WEF_MB_RUN_STRESSTEST - Generation de faux pics d'activite
set -uo pipefail
source "$VARS_FILE"
echo "[MB_016] Generation de charge artificielle (stress-ng)..."
command -v stress-ng >/dev/null || dnf install -y stress-ng
stress-ng --cpu 2 --vm 1 --vm-bytes 128M --timeout 15s
echo "[MB_016] OK."
exit 0
