#!/bin/bash
# WAG_005 - WEF_WAG_BLD_SVCSTART
# Active le demarrage automatique de wazuh-agent au boot et (re)demarre
# le service pour appliquer la configuration ecrite par WAG_004.
set -uo pipefail
source "$VARS_FILE"

echo "[WAG_005] Activation et demarrage de wazuh-agent..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl restart wazuh-agent

sleep 3

if systemctl is-active --quiet wazuh-agent; then
  echo "[WAG_005] wazuh-agent actif."
else
  echo "[WAG_005] ERREUR : wazuh-agent n'a pas demarre."
  exit 1
fi

echo "[WAG_005] OK."
exit 0
