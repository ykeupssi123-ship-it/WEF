#!/bin/bash
# KB_003 - WEF_KB_BLD_DIRINIT - Repertoires de stockage des objets
set -uo pipefail
source "$VARS_FILE"
echo "[KB_003] Creation des repertoires..."
mkdir -p /var/lib/kibana /var/log/kibana /etc/kibana
echo "[KB_003] OK."
exit 0
