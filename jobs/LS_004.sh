#!/bin/bash
# LS_004 - WEF_LS_BLD_DIRINIT - Repertoires de transit + Dead Letter Queue
set -uo pipefail
source "$VARS_FILE"
echo "[LS_004] Creation des repertoires..."
mkdir -p /var/lib/logstash /var/log/logstash /var/lib/logstash/dlq
echo "[LS_004] OK."
exit 0
