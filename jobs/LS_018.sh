#!/bin/bash
# LS_018 - WEF_LS_BLD_DLQSETUP - Activation de la Dead Letter Queue
set -uo pipefail
source "$VARS_FILE"
echo "[LS_018] Activation de la DLQ..."
grep -q "^dead_letter_queue.enable: true$" /etc/logstash/logstash.yml 2>/dev/null || echo "dead_letter_queue.enable: true" >> /etc/logstash/logstash.yml
echo "[LS_018] OK."
exit 0
