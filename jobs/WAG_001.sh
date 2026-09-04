#!/bin/bash
# WAG_001 - WEF_WAG_BLD_PREREQ
# Verifie que cet hote peut joindre le manager Wazuh (FACTORY_HOST_IP,
# VM1) AVANT toute installation - evite d'installer un agent qui ne
# pourra jamais s'enregistrer. ROLE=WAZUH_AGENT_LINUX : ce job (et
# WAG_002 a WAG_006) se joue sur N'IMPORTE QUEL hote Linux
# supplementaire que vous voulez surveiller, autant de fois que
# necessaire - il suffit de copier ce dossier et changer AGENT_NAME
# dans vars.conf a chaque nouvel hote.
set -uo pipefail
source "$VARS_FILE"

if [ -z "${FACTORY_HOST_IP:-}" ]; then
  echo "[WAG_001] ERREUR : FACTORY_HOST_IP (IP du manager Wazuh) est vide dans vars.conf."
  exit 1
fi

echo "[WAG_001] Test de connectivite vers le manager (${FACTORY_HOST_IP})..."
if ping -c 2 -W 2 "${FACTORY_HOST_IP}" > /dev/null 2>&1; then
  echo "[WAG_001] Manager joignable."
else
  echo "[WAG_001] ERREUR : manager ${FACTORY_HOST_IP} non joignable (verifiez reseau/pare-feu port 1514/1515)."
  exit 1
fi

echo "[WAG_001] OK."
exit 0
