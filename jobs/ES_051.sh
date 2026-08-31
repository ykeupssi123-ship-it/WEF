#!/bin/bash
# ES_051 - WEF_ES_RUN_CRASHTRGGR - Simulation sinistre : arret brutal
set -uo pipefail
source "$VARS_FILE"
echo "[ES_051] Arret brutal du processus Elasticsearch (crash-test)..."
pkill -9 -f "org.elasticsearch.bootstrap.Elasticsearch" || true
echo "[ES_051] OK."
exit 0
