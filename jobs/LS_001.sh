#!/bin/bash
# LS_001 - WEF_LS_BLD_OSPREP - Alignement OS Oracle Linux 8.10 pour Logstash
set -uo pipefail
source "$VARS_FILE"
echo "[LS_001] Nettoyage du cache dnf..."
dnf clean all
echo "[LS_001] OK."
exit 0
