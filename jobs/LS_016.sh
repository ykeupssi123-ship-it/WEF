#!/bin/bash
# LS_016 - WEF_LS_BLD_PQSIZE - Taille limite de la queue (lue depuis LS_PQ_MAX_BYTES, vars.conf)
set -uo pipefail
source "$VARS_FILE"
PQ_SIZE="${LS_PQ_MAX_BYTES:-10gb}"
echo "[LS_016] Fixation de la taille max de la PQ a ${PQ_SIZE} (LS_PQ_MAX_BYTES)..."
sed -i -E "/^queue\.max_bytes:/d" /etc/logstash/logstash.yml 2>/dev/null || true
echo "queue.max_bytes: ${PQ_SIZE}" >> /etc/logstash/logstash.yml
echo "[LS_016] OK."
exit 0
