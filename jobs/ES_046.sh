#!/bin/bash
# ES_046 - WEF_ES_RUN_STRESSTESTPIPE - Simulation de charge d'ingestion
#
# CORRECTIF 2026-08-14 (incident reel pre-demo) : l'index de test
# s'appelait "factory-stresstest", qui ne correspond a aucun des motifs
# autorises par ES_041 ("log-*,wazuh-*,-*" - creation automatique
# refusee pour tout le reste). ES_041 s'execute juste avant ce job dans
# la chaine, donc l'echec ("index_not_found_exception ... forbids
# automatic creation") apparaissait a chaque execution, sans lien
# evident avec son origine reelle (deux jobs ecrits independamment,
# jamais confrontes bout en bout avant ce jour). Renomme en
# "log-factory-stresstest" - motif deja autorise (log-*), et qui
# exerce en plus le vrai gabarit de production (ES_040) au lieu d'un
# nom ad-hoc non templatise : le test est plus fidele qu'avant, pas
# juste reparee.
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_046] Injection puis purge d'un lot de test _bulk..."
BULK_BODY=""
for i in $(seq 1 50); do
  BULK_BODY+='{"index":{"_index":"log-factory-stresstest"}}'$'\n''{"message":"stress-test-event-'"$i"'","factory_test":true}'$'\n'
done
echo "$BULK_BODY" | es_admin_curl -X POST "https://127.0.0.1:${ES_PORT}/_bulk" -H "Content-Type: application/x-ndjson" --data-binary @- -o ${WORK_TMP_DIR}/es046.json
es_admin_curl -X DELETE "https://127.0.0.1:${ES_PORT}/log-factory-stresstest" -o /dev/null
grep -q '"errors":false' ${WORK_TMP_DIR}/es046.json && { echo "[ES_046] OK."; rm -f ${WORK_TMP_DIR}/es046.json; exit 0; }
echo "[ES_046] ERREUR ou erreurs partielles, voir ${WORK_TMP_DIR}/es046.json"; exit 1
