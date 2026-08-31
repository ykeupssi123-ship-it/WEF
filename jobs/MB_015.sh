#!/bin/bash
# MB_015 - WEF_MB_RUN_SIMABS - Crash test : disparition de l'infra reseau
set -uo pipefail
source "$VARS_FILE"
echo "[MB_015] Simulation de coupure vers Logstash (port ${LS_BEATS_PORT})..."
iptables -A OUTPUT -p tcp --dport ${LS_BEATS_PORT} -j DROP
echo "[MB_015] OK."
exit 0
