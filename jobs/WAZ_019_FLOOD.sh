#!/bin/bash
# WAZ_019_FLOOD - WEF_WAZ_RUN_AGENTFLOOD - Deluge massif d'evenements
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_019_FLOOD] Injection de 20000 evenements de test..."
for i in $(seq 1 20000); do
  logger -t auth "wazuh-test-flood: secure event injection ${i}"
done
echo "[WAZ_019_FLOOD] OK."
exit 0
