#!/bin/bash
# MB_014 - WEF_MB_BLD_LOGPOLL - Analyse du demarrage sans erreur
set -uo pipefail
source "$VARS_FILE"
echo "[MB_014] Attente de la boucle d'extraction..."
for i in $(seq 1 60); do
  systemctl is-active --quiet metricbeat && { echo "[MB_014] OK."; exit 0; }
  sleep 5
done
echo "[MB_014] ERREUR : metricbeat n'est jamais devenu actif."
exit 1
