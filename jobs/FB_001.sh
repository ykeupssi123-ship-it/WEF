#!/bin/bash
# FB_001 - WEF_FB_BLD_OSPREP - Alignement OS pour Filebeat (VM2)
set -uo pipefail
source "$VARS_FILE"
echo "[FB_001] Nettoyage du cache dnf..."
dnf clean all
echo "[FB_001] OK."
exit 0
