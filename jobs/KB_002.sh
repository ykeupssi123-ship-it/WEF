#!/bin/bash
# KB_002 - WEF_KB_BLD_USRNEW - Creation de l'entite isolee 'kibana'
set -uo pipefail
source "$VARS_FILE"
echo "[KB_002] Creation de l'utilisateur ${KB_USER}..."
id "${KB_USER}" &>/dev/null || useradd --system --no-create-home "${KB_USER}"
echo "[KB_002] OK."
exit 0
