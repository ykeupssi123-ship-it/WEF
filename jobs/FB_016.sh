#!/bin/bash
# FB_016 - WEF_FB_RUN_INJECTRAW - Agression des entrees en mode isole
set -uo pipefail
source "$VARS_FILE"
echo "[FB_016] Ecriture massive de 10000 lignes de test..."
TESTLOG="/var/log/factory_test.log"
for i in $(seq 1 10000); do echo "factory-test-line-${i}"; done > "$TESTLOG"
echo "[FB_016] OK."
exit 0
