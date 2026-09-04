#!/bin/bash
# WAZ_026 - WEF_WAZ_BLD_RULETESTER - Test de conformite des regles
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_026] Test des regles avec wazuh-logtest..."
echo "test event" | /var/ossec/bin/wazuh-logtest
echo "[WAZ_026] OK."
exit 0
