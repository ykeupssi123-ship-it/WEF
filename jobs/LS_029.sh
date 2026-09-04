#!/bin/bash
# LS_029 - WEF_LS_RUN_SIMABS - Crash test : coupure du lien vers Elasticsearch
set -uo pipefail
source "$VARS_FILE"
echo "[LS_029] Simulation d'absence d'Elasticsearch (iptables DROP 9200)..."
iptables -A OUTPUT -p tcp --dport ${ES_PORT} -j DROP
echo "[LS_029] OK."
exit 0
