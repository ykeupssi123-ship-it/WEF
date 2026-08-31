#!/bin/bash
# ES_049 - WEF_ES_RUN_DISKCHK - Evaluation de la reserve disque (seuil lu depuis MIN_DISK_FREE_PCT, vars.conf)
set -uo pipefail
source "$VARS_FILE"
MIN_FREE="${MIN_DISK_FREE_PCT:-20}"
USED_PCT=$(df /var/lib/elasticsearch | awk 'NR==2{gsub("%","",$5); print $5}')
FREE_PCT=$((100 - USED_PCT))
echo "[ES_049] Espace disque libre : ${FREE_PCT}% (seuil minimum configure : ${MIN_FREE}%)."
if [ "$FREE_PCT" -lt "$MIN_FREE" ]; then
  echo "[ES_049] AVERTISSEMENT : espace disque disponible < ${MIN_FREE}%. Voir onglet MAINTENANCE_MNT du blueprint si le disque est proche de 100%."
fi
echo "[ES_049] OK."
exit 0
