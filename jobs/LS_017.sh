#!/bin/bash
# LS_017 - WEF_LS_BLD_JVMTUNING - Memoire JVM (taille lue depuis LS_JVM_HEAP_SIZE, vars.conf)
set -uo pipefail
source "$VARS_FILE"
HEAP="${LS_JVM_HEAP_SIZE:-4g}"
echo "[LS_017] Fixation de la memoire JVM a ${HEAP} (LS_JVM_HEAP_SIZE)..."
sed -i -E "s/^-Xm[sx][0-9]+[gGmM]/-Xms${HEAP}/" /etc/logstash/jvm.options 2>/dev/null || true
grep -q "^-Xms${HEAP}$" /etc/logstash/jvm.options 2>/dev/null || echo "-Xms${HEAP}" >> /etc/logstash/jvm.options
grep -q "^-Xmx${HEAP}$" /etc/logstash/jvm.options 2>/dev/null || echo "-Xmx${HEAP}" >> /etc/logstash/jvm.options
echo "[LS_017] OK."
exit 0
