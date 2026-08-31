#!/bin/bash
# ES_024 - WEF_ES_BLD_JVMOPTNS - Heap JVM (taille lue depuis ES_JVM_HEAP_SIZE, vars.conf)
set -uo pipefail
source "$VARS_FILE"
HEAP="${ES_JVM_HEAP_SIZE:-4g}"
mkdir -p /etc/elasticsearch/jvm.options.d
echo "[ES_024] Fixation du heap JVM a ${HEAP} (ES_JVM_HEAP_SIZE)..."
cat > /etc/elasticsearch/jvm.options.d/heap.options << JVMEOF
-Xms${HEAP}
-Xmx${HEAP}
JVMEOF
echo "[ES_024] OK."
exit 0
