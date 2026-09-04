#!/bin/bash
# ES_007 - WEF_ES_BLD_DIRSTRUCT - Repertoires de donnees/logs/conf
set -uo pipefail
source "$VARS_FILE"
echo "[ES_007] Creation des repertoires..."
mkdir -p /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch
echo "[ES_007] OK."
exit 0
