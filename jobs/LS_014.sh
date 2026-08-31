#!/bin/bash
# LS_014 - WEF_LS_BLD_DIRSECU - Condamnation de l'ancien espace crypto local
set -uo pipefail
source "$VARS_FILE"
echo "[LS_014] Reinitialisation de /etc/logstash/certs..."
rm -rf /etc/logstash/certs
mkdir -m 700 /etc/logstash/certs
echo "[LS_014] OK."
exit 0
