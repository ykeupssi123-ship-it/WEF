#!/bin/bash
# ES_012 - WEF_ES_BLD_FWZONEDEF - Zone d'ingestion IngestionZone
set -uo pipefail
source "$VARS_FILE"
if firewall-cmd --get-zones 2>/dev/null | grep -qw IngestionZone; then
  echo "[ES_012] Zone IngestionZone deja presente, ignore."
  echo "[ES_012] OK."
  exit 0
fi
echo "[ES_012] Creation de la zone IngestionZone..."
firewall-cmd --permanent --new-zone=IngestionZone
echo "[ES_012] OK."
exit 0
