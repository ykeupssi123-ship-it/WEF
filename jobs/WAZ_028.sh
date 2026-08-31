#!/bin/bash
# WAZ_028 - WEF_WAZ_RUN_RCVPOLL - Redemarrage et controle post-sinistre
#
# CORRECTIF 2026-08-14 (audit systemique suite a l'incident ES_052) :
# meme risque exact que ES_051/ES_052 - WAZ_027 (juste avant, meme
# chaine) tue ossec-analysisd avec un pkill -9, et ce job enchainait
# "systemctl start wazuh-manager" + un sleep 5 fixe, sans jamais
# verifier l'etat reel. Plus expose que ES_052 ne l'etait : aucun job
# en aval de cette chaine (WAZ_029 fait de la rotation de logs, pas un
# controle de sante) ne verifie que wazuh-manager a reellement
# redemarre. Corrige : verification reelle via wait_for_service_active
# (lib/commun.sh), avec la meme pause de 2s avant la premiere lecture
# d'etat pour supprimer la fenetre de course a la racine.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
echo "[WAZ_028] Redemarrage de wazuh-manager..."
sleep 2
if wait_for_service_active wazuh-manager 120 5; then
  echo "[WAZ_028] Confirme actif (systemctl is-active)."
  echo "[WAZ_028] OK."
  exit 0
fi
exit 1
