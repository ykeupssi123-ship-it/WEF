#!/bin/bash
# ES_B001_RAM_CHECK - WEF_ES_BLD_MINRAMVERIFY - Verification RAM min (seuil lu depuis MIN_RAM_GB_REQUIRED, vars.conf)
set -uo pipefail
source "$VARS_FILE"
MIN_RAM="${MIN_RAM_GB_REQUIRED:-14}"
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
echo "[ES_B001_RAM_CHECK] RAM detectee : ${RAM_GB} Go (seuil minimum configure : ${MIN_RAM} Go, RESOURCE_PROFILE=${RESOURCE_PROFILE:-non defini})."
if [ "$RAM_GB" -lt "$MIN_RAM" ]; then
  echo "[ES_B001_RAM_CHECK] ERREUR : RAM insuffisante (minimum ${MIN_RAM} Go requis par MIN_RAM_GB_REQUIRED). Voir vars.conf, section DIMENSIONNEMENT RESSOURCES, pour le tableau de risque par palier de RAM avant d'abaisser ce seuil."
  exit 1
fi
if [ "$MIN_RAM" -lt 14 ]; then
  echo "[ES_B001_RAM_CHECK] AVERTISSEMENT : seuil abaisse a ${MIN_RAM} Go (profil ${RESOURCE_PROFILE:-inconnu}) - la valeur ideale du projet est 14-16 Go. Fonctionnel pour une demo a faible trafic, pas garanti sous charge reelle."
fi
echo "[ES_B001_RAM_CHECK] OK."
exit 0
