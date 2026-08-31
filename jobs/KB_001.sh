#!/bin/bash
# KB_001 - WEF_KB_BLD_OSPREP - Alignement OS pour Kibana
set -uo pipefail
source "$VARS_FILE"
echo "[KB_001] Nettoyage du cache dnf..."
dnf clean all
echo "[KB_001] OK."
exit 0
