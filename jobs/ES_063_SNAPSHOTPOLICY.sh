#!/bin/bash
# ES_063_SNAPSHOTPOLICY - WEF_ES_RUN_S3SNAPPOL
# Cree/met a jour (PUT = ecrasement propre, jamais d'accumulation) la
# politique de cycle de vie des snapshots (SLM) : planifie une sauvegarde
# reguliere de tous les index vers le depot S3 OVH enregistre par
# ES_062_SNAPSHOTS3REPO, avec purge automatique au-dela de la retention.
#
# JOB ISOLE ET OPTIONNEL - meme logique que ES_062 : no-op propre si la
# sauvegarde S3 est desactivee ou mal configuree.
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "${BASH_SOURCE[0]}")/lib/es_admin_curl.sh"

if [ "${ES_SNAPSHOT_S3_ENABLED:-false}" != "true" ]; then
  echo "[ES_063_SNAPSHOTPOLICY] Sauvegarde S3 desactivee (ES_SNAPSHOT_S3_ENABLED=false), ignore."
  echo "[ES_063_SNAPSHOTPOLICY] OK."
  exit 0
fi

if [ -z "${OVH_S3_ENDPOINT:-}" ] || [ -z "${OVH_S3_BUCKET:-}" ] || [ -z "${OVH_S3_ACCESS_KEY:-}" ] || [ -z "${OVH_S3_SECRET_KEY:-}" ]; then
  echo "[ES_063_SNAPSHOTPOLICY] AVERTISSEMENT : OVH_S3_* incomplet, depot probablement non cree par ES_062. Politique non creee, ignore proprement."
  echo "[ES_063_SNAPSHOTPOLICY] OK."
  exit 0
fi

RETENTION="${ES_SNAPSHOT_RETENTION_DAYS:-30}"

echo "[ES_063_SNAPSHOTPOLICY] Ecriture de la politique '${ES_SNAPSHOT_POLICY_NAME}' (retention ${RETENTION}j)..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_slm/policy/${ES_SNAPSHOT_POLICY_NAME}" \
  -H "Content-Type: application/json" -d "{
  \"schedule\": \"${ES_SNAPSHOT_SCHEDULE_CRON}\",
  \"name\": \"<wef-snap-{now/d}>\",
  \"repository\": \"${ES_SNAPSHOT_REPO_NAME}\",
  \"config\": { \"indices\": [\"*\"], \"include_global_state\": true },
  \"retention\": {
    \"expire_after\": \"${RETENTION}d\",
    \"min_count\": 5,
    \"max_count\": 100
  }
}" -o ${WORK_TMP_DIR}/es063.json

grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es063.json 2>/dev/null && { echo "[ES_063_SNAPSHOTPOLICY] Politique active."; rm -f ${WORK_TMP_DIR}/es063.json; echo "[ES_063_SNAPSHOTPOLICY] OK."; exit 0; }
echo "[ES_063_SNAPSHOTPOLICY] AVERTISSEMENT : reponse inattendue, voir ${WORK_TMP_DIR}/es063.json (job non bloquant, on continue quand meme)."
echo "[ES_063_SNAPSHOTPOLICY] OK."
exit 0
