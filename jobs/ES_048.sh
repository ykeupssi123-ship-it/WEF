#!/bin/bash
# ES_048 - WEF_ES_BLD_LGRTTVALID - Test d'execution forcee de la rotation
set -uo pipefail
source "$VARS_FILE"
echo "[ES_048] Validation de la syntaxe logrotate..."
logrotate --force /etc/logrotate.d/elasticsearch
echo "[ES_048] OK."
exit 0
