#!/bin/bash
# WAZ_034 - WEF_WAZ_BLD_GTESOUVRN - Vanne maitresse : WAZ_SECURITY_ONLINE
# JOB PASSERELLE final du bastion Wazuh. Ouvre l'acces aux jobs de
# commutation (WAZ_035 a WAZ_040) : bascule Kibana <-> Dashboard natif.
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_034] Verification finale avant emission du signal..."
# CORRIGE LE 2026-08-30 (incident reel wef-elk-core, premier passage
# complet de la chaine jusqu'ici) : l'ancienne forme
# "wazuh-control status | grep -qi 'is running' || ..." echouait a
# CHAQUE fois, meme manager reellement actif (confirme en reel :
# systemctl et wazuh-control montrent bien wazuh-analysisd,
# wazuh-remoted, wazuh-db etc "is running"). Cause reelle : ce projet
# laisse volontairement desactives certains daemons optionnels
# (clusterd/maild/agentlessd/integratord/csyslogd - jamais requis par
# cette usine), et /var/ossec/bin/wazuh-control status renvoie un code
# de sortie 1 des qu'UN SEUL daemon (meme volontairement desactive)
# n'est pas actif - avec "set -o pipefail" (deja en tete de ce script),
# ce code 1 du COTE GAUCHE du pipe ecrasait le succes reel de grep
# (cote droit, qui trouvait bel et bien "is running") dans le statut
# final du pipeline. La sortie est donc capturee HORS pipe : le grep
# ensuite ne porte que sur du texte deja en memoire, plus aucune
# pipeline dont le statut pourrait etre pollue par l'exit code (attendu,
# pas une panne) de wazuh-control lui-meme.
STATUS_OUT="$(/var/ossec/bin/wazuh-control status)"
echo "$STATUS_OUT" | grep -qi "is running" || { echo "[WAZ_034] ERREUR : wazuh-manager non actif."; echo "$STATUS_OUT"; exit 1; }
echo "[WAZ_034] Bastion Wazuh debout, souverain, etanche, operationnel. Signal WAZ_SECURITY_ONLINE emis."
echo "[WAZ_034] OK."
exit 0
