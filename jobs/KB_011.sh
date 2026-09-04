#!/bin/bash
# KB_011 - WEF_KB_BLD_DIRSECU - Condamnation de l'ancien espace crypto local
set -uo pipefail
source "$VARS_FILE"
echo "[KB_011] Reinitialisation de /etc/kibana/certs..."
rm -rf /etc/kibana/certs
mkdir -m 700 /etc/kibana/certs
echo "[KB_011] OK."
exit 0
