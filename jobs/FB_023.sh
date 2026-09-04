#!/bin/bash
# FB_023 - WEF_FB_BLD_GTERDY - Vanne maitresse : FILEBEAT_SENSOR_ONLINE
# JOB PASSERELLE (ouvre vers MB). Capteur autonome, etanche, operationnel,
# independant de l'etat d'ELK exterieur.
set -uo pipefail
source "$VARS_FILE"
echo "[FB_023] Verification finale avant emission du signal..."
systemctl is-active --quiet filebeat || { echo "[FB_023] ERREUR : filebeat n'est pas actif."; exit 1; }
echo "[FB_023] Capteur de logs operationnel. Signal FILEBEAT_SENSOR_ONLINE emis."
echo "[FB_023] OK."
exit 0
