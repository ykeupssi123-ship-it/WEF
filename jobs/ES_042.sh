#!/bin/bash
# ES_042 - WEF_ES_BLD_DISCOSET - Validation finale du mode single-node
set -uo pipefail
source "$VARS_FILE"
echo "[ES_042] Verification du mode single-node dans elasticsearch.yml..."
grep -q "^discovery.type: single-node$" /etc/elasticsearch/elasticsearch.yml
echo "[ES_042] OK."
exit 0
