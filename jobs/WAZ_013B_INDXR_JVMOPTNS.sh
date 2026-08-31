#!/bin/bash
# WAZ_013B - WEF_WAZ_BLD_INDXRJVMOPTNS - Heap JVM wazuh-indexer (taille lue depuis WAZ_INDEXER_JVM_HEAP_SIZE, vars.conf)
# AJOUTE LE 2026-08-11 : avant ce job, wazuh-indexer (fork OpenSearch,
# base sur la meme JVM qu'Elasticsearch) demarrait avec le heap choisi
# automatiquement par OpenSearch selon la RAM detectee - imprevisible
# et parfois trop genereux sur une machine a faible RAM (meme logique
# que ES_024/LS_017 : mieux vaut fixer explicitement plutot que
# laisser un moteur JVM se servir seul quand la RAM est comptee).
set -uo pipefail
source "$VARS_FILE"
HEAP="${WAZ_INDEXER_JVM_HEAP_SIZE:-1g}"
mkdir -p /etc/wazuh-indexer/jvm.options.d
echo "[WAZ_013B] Fixation du heap JVM wazuh-indexer a ${HEAP} (WAZ_INDEXER_JVM_HEAP_SIZE)..."
cat > /etc/wazuh-indexer/jvm.options.d/heap.options << JVMEOF
-Xms${HEAP}
-Xmx${HEAP}
JVMEOF
echo "[WAZ_013B] OK."
exit 0
