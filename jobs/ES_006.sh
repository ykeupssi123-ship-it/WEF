#!/bin/bash
# ES_006 - WEF_ES_BLD_USRNEW - Creation de l'utilisateur elasticsearch
set -uo pipefail
source "$VARS_FILE"
echo "[ES_006] Creation de l'utilisateur ${ES_USER}..."
id "${ES_USER}" &>/dev/null || useradd --system --no-create-home "${ES_USER}"
echo "[ES_006] OK."
exit 0
