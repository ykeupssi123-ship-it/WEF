#!/bin/bash
# MB_001 - WEF_MB_BLD_OSPREP - Alignement OS pour Metricbeat (VM2)
set -uo pipefail
source "$VARS_FILE"
echo "[MB_001] Nettoyage du cache dnf..."
dnf clean all
echo "[MB_001] OK."
exit 0
