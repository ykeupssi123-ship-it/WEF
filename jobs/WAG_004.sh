#!/bin/bash
# WAG_004 - WEF_WAG_BLD_CONFIGURE
# Pointe ossec.conf vers le manager (FACTORY_HOST_IP) et definit le nom
# unique de cet agent (AGENT_NAME) pour l'enrolement automatique.
# Idempotent : sed remplace l'adresse existante ; le bloc <enrollment>
# n'est ajoute que s'il est absent.
set -uo pipefail
source "$VARS_FILE"

OSSEC_CONF="/var/ossec/etc/ossec.conf"

echo "[WAG_004] Configuration de ${OSSEC_CONF}..."
if [ ! -f "$OSSEC_CONF" ]; then
  echo "[WAG_004] ERREUR : ${OSSEC_CONF} introuvable. wazuh-agent est-il installe (WAG_003) ?"
  exit 1
fi

sed -i "s|<address>.*</address>|<address>${FACTORY_HOST_IP}</address>|" "$OSSEC_CONF"

if ! grep -q "<enrollment_agent_name>\|<agent_name>" "$OSSEC_CONF"; then
  sed -i "0,/<\/client>/s|</client>|  <enrollment>\n    <enabled>yes</enabled>\n    <manager_address>${FACTORY_HOST_IP}</manager_address>\n    <agent_name>${AGENT_NAME}</agent_name>\n  </enrollment>\n</client>|" "$OSSEC_CONF"
fi

echo "[WAG_004] Manager = ${FACTORY_HOST_IP}, Agent name = ${AGENT_NAME}"
echo "[WAG_004] OK."
exit 0
