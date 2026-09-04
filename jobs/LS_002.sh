#!/bin/bash
# LS_002 - WEF_LS_BLD_JAVACHECK - Validation runtime OpenJDK 17
set -uo pipefail
source "$VARS_FILE"
echo "[LS_002] Verification du runtime Java..."
java -version 2>&1 | grep -q "17" || dnf install -y java-17-openjdk
echo "[LS_002] OK."
exit 0
