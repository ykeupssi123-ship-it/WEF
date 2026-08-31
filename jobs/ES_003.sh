#!/bin/bash
# ES_003 - WEF_ES_BLD_OSSWPPNS - vm.swappiness=1
set -uo pipefail
source "$VARS_FILE"
if grep -q "^vm.swappiness=1$" /etc/sysctl.conf 2>/dev/null; then
  echo "[ES_003] swappiness deja fixe, ignore."
  echo "[ES_003] OK."
  exit 0
fi
echo "[ES_003] Fixation de vm.swappiness=1..."
sed -i '/^vm.swappiness=/d' /etc/sysctl.conf
echo "vm.swappiness=1" >> /etc/sysctl.conf
sysctl -p
echo "[ES_003] OK."
exit 0
