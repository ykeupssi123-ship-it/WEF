#!/bin/bash
# FB_015 - WEF_FB_RUN_SIMABS - Crash test : extinction du monde exterieur
set -uo pipefail
source "$VARS_FILE"
echo "[FB_015] Simulation de coupure vers Logstash (port ${LS_BEATS_PORT})..."
iptables -A OUTPUT -p tcp --dport ${LS_BEATS_PORT} -j DROP
echo "[FB_015] OK."
exit 0
