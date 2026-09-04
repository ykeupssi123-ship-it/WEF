#!/bin/bash
# WAZ_002 - WEF_WAZ_BLD_OSMAXMAP - vm.max_map_count=524288 (cohabitation ES+Wazuh)
set -uo pipefail
source "$VARS_FILE"
if grep -q "^vm.max_map_count=524288$" /etc/sysctl.conf 2>/dev/null; then
  echo "[WAZ_002] Deja fixe, ignore."
  echo "[WAZ_002] OK."
  exit 0
fi
echo "[WAZ_002] Augmentation de vm.max_map_count a 524288..."
sed -i '/^vm.max_map_count=/d' /etc/sysctl.conf
echo "vm.max_map_count=524288" >> /etc/sysctl.conf
sysctl -p
echo "[WAZ_002] OK."
exit 0
