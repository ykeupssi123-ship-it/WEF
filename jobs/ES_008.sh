#!/bin/bash
# ES_008 - WEF_ES_BLD_DIROWNER2 - Permissions proprietaires
set -uo pipefail
source "$VARS_FILE"
echo "[ES_008] Alignement des permissions..."
chown -R "${ES_USER}:${ES_USER}" /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch
echo "[ES_008] OK."
exit 0
