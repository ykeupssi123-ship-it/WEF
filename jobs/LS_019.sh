#!/bin/bash
# LS_019 - WEF_LS_BLD_PLGNSVAL - Modules de sortie mondiaux
set -uo pipefail
source "$VARS_FILE"
echo "[LS_019] Installation des plugins de sortie standards..."
/usr/share/logstash/bin/logstash-plugin install logstash-output-kafka logstash-output-amazon_s3 2>&1 | grep -qi "already provided" || true
echo "[LS_019] OK."
exit 0
