#!/bin/bash
# LS_005 - WEF_LS_BLD_DIROWNER - Permissions de l'entite confinee
set -uo pipefail
source "$VARS_FILE"
echo "[LS_005] Alignement des permissions..."
chown -R "${LS_USER}:${LS_USER}" /var/lib/logstash /var/log/logstash
echo "[LS_005] OK."
exit 0
