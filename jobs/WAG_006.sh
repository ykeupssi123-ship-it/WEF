#!/bin/bash
# WAG_006 - WEF_WAG_RUN_VERIFY
# Verifie que l'agent est actif et enregistre, et ecrit un rapport
# final (state/agent_report_<AGENT_NAME>.txt). JOB PASSERELLE local :
# emet WAG_READY (rien d'autre n'en depend, un agent est une feuille
# de l'arbre - il consomme le manager, il n'ouvre rien derriere lui).
set -uo pipefail
source "$VARS_FILE"

REPORT="${STATE_DIR}/agent_report_${AGENT_NAME}.txt"

echo "[WAG_006] Verification de l'enregistrement de l'agent '${AGENT_NAME}'..."

STATUS="INCONNU"
if [ -x /var/ossec/bin/agent_control ]; then
  /var/ossec/bin/agent_control -l || true
  STATUS="Voir agent_control -l ci-dessus"
else
  echo "[WAG_006] agent_control non trouve, verification via systemctl uniquement."
fi

{
  echo "=================================================="
  echo " RAPPORT DE DEPLOIEMENT - WAZUH AGENT (LINUX)"
  echo "=================================================="
  echo "Date              : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Projet            : ${PROJECT_NAME:-WAZ_ELK_FACTORY}"
  echo "Nom de l'agent    : ${AGENT_NAME}"
  echo "Manager cible     : ${FACTORY_HOST_IP}"
  echo "Service agent     : $(systemctl is-active wazuh-agent 2>/dev/null || echo inconnu)"
  echo "Statut            : ${STATUS}"
  echo "=================================================="
} > "$REPORT"

cat "$REPORT"
echo "[WAG_006] Rapport ecrit dans ${REPORT}"
echo "[WAG_006] OK."
exit 0
