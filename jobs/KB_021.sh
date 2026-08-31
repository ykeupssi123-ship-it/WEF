#!/bin/bash
# KB_021 - WEF_KB_RUN_ISLTDB - Crash test : blocage du port Elasticsearch
set -uo pipefail
source "$VARS_FILE"
echo "[KB_021] Isolation d'Elasticsearch (iptables DROP ${ES_PORT})..."
iptables -A OUTPUT -p tcp --dport ${ES_PORT} -j DROP
echo "[KB_021] OK."
exit 0
