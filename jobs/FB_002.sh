#!/bin/bash
# FB_002 - WEF_FB_BLD_DIRINIT - Repertoires de transit et registres
set -uo pipefail
source "$VARS_FILE"
echo "[FB_002] Creation des repertoires..."
mkdir -p /var/lib/filebeat /var/log/filebeat /etc/filebeat/prospectors.d
echo "[FB_002] OK."
exit 0
