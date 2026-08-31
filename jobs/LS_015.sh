#!/bin/bash
# LS_015 - WEF_LS_BLD_PQENABLE - Activation des Persistent Queues
set -uo pipefail
source "$VARS_FILE"
echo "[LS_015] Activation des Persistent Queues..."
grep -q "^queue.type: persisted$" /etc/logstash/logstash.yml 2>/dev/null || echo "queue.type: persisted" >> /etc/logstash/logstash.yml
echo "[LS_015] OK."
exit 0
