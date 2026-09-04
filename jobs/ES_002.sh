#!/bin/bash
# ES_002 - WEF_ES_BLD_OSLIMIT - ulimit -n 65536 et memlock unlimited
set -uo pipefail
source "$VARS_FILE"
LIMITS_FILE="/etc/security/limits.d/elasticsearch.conf"
if [ -f "$LIMITS_FILE" ] && grep -q "elasticsearch.*memlock.*unlimited" "$LIMITS_FILE"; then
  echo "[ES_002] Limites deja injectees, ignore."
  echo "[ES_002] OK."
  exit 0
fi
echo "[ES_002] Injection des limites nofile/memlock pour ${ES_USER}..."
cat > "$LIMITS_FILE" << LIMEOF
${ES_USER} soft nofile 65536
${ES_USER} hard nofile 65536
${ES_USER} soft memlock unlimited
${ES_USER} hard memlock unlimited
LIMEOF
echo "[ES_002] OK."
exit 0
