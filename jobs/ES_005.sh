#!/bin/bash
# ES_005 - WEF_ES_BLD_OSMAXMAP - vm.max_map_count=262144
set -uo pipefail
source "$VARS_FILE"
if grep -q "^vm.max_map_count=262144$" /etc/sysctl.conf 2>/dev/null; then
  echo "[ES_005] max_map_count deja fixe, ignore."
  echo "[ES_005] OK."
  exit 0
fi
echo "[ES_005] Fixation de vm.max_map_count=262144..."
sed -i '/^vm.max_map_count=/d' /etc/sysctl.conf
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -p
echo "[ES_005] OK."
exit 0
