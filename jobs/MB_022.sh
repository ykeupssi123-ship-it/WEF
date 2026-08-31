#!/bin/bash
# MB_022 - WEF_MB_BLD_GTERDY - Vanne maitresse : METRICBEAT_SENSOR_ONLINE
# JOB PASSERELLE (ouvre vers WAZ). Dernier maillon avant le bastion Wazuh.
set -uo pipefail
source "$VARS_FILE"
echo "[MB_022] Verification finale avant emission du signal..."
systemctl is-active --quiet metricbeat || { echo "[MB_022] ERREUR : metricbeat n'est pas actif."; exit 1; }
echo "[MB_022] Capteur de performance operationnel. Signal METRICBEAT_SENSOR_ONLINE emis."
echo "[MB_022] OK."
exit 0
