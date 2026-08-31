#!/bin/bash
# WAZ_001 - WEF_WAZ_BLD_OSLIMIT - ulimit et memlock pour les moteurs Wazuh
set -uo pipefail
source "$VARS_FILE"
echo "[WAZ_001] Injection des limites systeme pour Wazuh..."
cat > /etc/security/limits.d/wazuh.conf << LIMEOF
wazuh hard nofile 65536
wazuh soft nofile 65536
LIMEOF
echo "[WAZ_001] OK."
exit 0
