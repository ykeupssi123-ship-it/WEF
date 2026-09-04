#!/bin/bash
# LS_003 - WEF_LS_BLD_USRNEW - Creation de l'entite confinee 'logstash'
set -uo pipefail
source "$VARS_FILE"
echo "[LS_003] Creation de l'utilisateur ${LS_USER}..."
id "${LS_USER}" &>/dev/null || useradd --system --no-create-home "${LS_USER}"
echo "[LS_003] OK."
exit 0
