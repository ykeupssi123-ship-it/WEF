#!/bin/bash
# ES_004 - WEF_ES_BLD_OSTHP - Desactivation permanente des THP
set -uo pipefail
source "$VARS_FILE"
CURRENT=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
if [ "$CURRENT" = "never" ]; then
  echo "[ES_004] THP deja desactive, ignore."
  echo "[ES_004] OK."
  exit 0
fi
echo "[ES_004] Desactivation des Transparent Huge Pages..."
echo never > /sys/kernel/mm/transparent_hugepage/enabled
grep -q "transparent_hugepage/enabled" /etc/rc.local 2>/dev/null || \
  echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
chmod +x /etc/rc.local 2>/dev/null || true
echo "[ES_004] OK."
exit 0
