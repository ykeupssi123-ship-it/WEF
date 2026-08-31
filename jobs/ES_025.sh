#!/bin/bash
# ES_025 - WEF_ES_BLD_CLEANOLDCRYPTO - Evacuation des artefacts .p12 obsoletes
set -uo pipefail
source "$VARS_FILE"
echo "[ES_025] Nettoyage des artefacts obsoletes..."
rm -f /etc/elasticsearch/*.p12 || true
echo "[ES_025] OK."
exit 0
