#!/bin/bash
# WAZ_024 - WEF_WAZ_BLD_VALVCHK - Validation du flux inter-demons local
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_024] Verification du canal local vers Logstash (port 5000)..."
netstat -tpln 2>/dev/null | grep -q ":5000 " && { echo "[WAZ_024] OK."; exit 0; }
echo "[WAZ_024] AVERTISSEMENT : port 5000 non detecte en ecoute cote Logstash (verifiez LS_026_FINAL)."
exit 0
