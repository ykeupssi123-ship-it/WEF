#!/bin/bash
# ES_010 - WEF_ES_BLD_TMPSECURE - sticky bit sur /tmp
set -uo pipefail
source "$VARS_FILE"
echo "[ES_010] Securisation de /tmp..."
chmod 1777 /tmp
echo "[ES_010] OK."
exit 0
