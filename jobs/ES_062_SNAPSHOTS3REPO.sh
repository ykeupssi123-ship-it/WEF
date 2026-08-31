#!/bin/bash
# ES_062_SNAPSHOTS3REPO - WEF_ES_RUN_S3REPOSET
# Enregistre (idempotent, PUT = ecrasement propre) un depot de snapshots
# Elasticsearch pointant vers l'object storage OVH (S3-compatible).
#
# JOB ISOLE ET OPTIONNEL, comme INFRA_001/INFRA_002 : rien d'autre ne
# depend de son resultat reel. Si ES_SNAPSHOT_S3_ENABLED=false (valeur
# par defaut) ou si les variables OVH_S3_* sont incompletes, ce job ne
# fait rien et sort en succes (exit 0) pour ne jamais bloquer la chaine
# - "juste au cas ou on veut l'utiliser plus tard".
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "${BASH_SOURCE[0]}")/lib/es_admin_curl.sh"

if [ "${ES_SNAPSHOT_S3_ENABLED:-false}" != "true" ]; then
  echo "[ES_062_SNAPSHOTS3REPO] Sauvegarde S3 desactivee (ES_SNAPSHOT_S3_ENABLED=false), ignore."
  echo "[ES_062_SNAPSHOTS3REPO] OK."
  exit 0
fi

if [ -z "${OVH_S3_ENDPOINT:-}" ] || [ -z "${OVH_S3_BUCKET:-}" ] || [ -z "${OVH_S3_ACCESS_KEY:-}" ] || [ -z "${OVH_S3_SECRET_KEY:-}" ]; then
  echo "[ES_062_SNAPSHOTS3REPO] AVERTISSEMENT : ES_SNAPSHOT_S3_ENABLED=true mais OVH_S3_* incomplet dans vars.conf. Depot non cree, ignore proprement."
  echo "[ES_062_SNAPSHOTS3REPO] OK."
  exit 0
fi

echo "[ES_062_SNAPSHOTS3REPO] Installation du plugin repository-s3 (si absent)..."
if ! /usr/share/elasticsearch/bin/elasticsearch-plugin list 2>/dev/null | grep -q "^repository-s3$"; then
  /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch repository-s3
fi

echo "[ES_062_SNAPSHOTS3REPO] Armement des identifiants S3 dans le keystore Elasticsearch..."
echo "${OVH_S3_ACCESS_KEY}" | /usr/share/elasticsearch/bin/elasticsearch-keystore add s3.client.default.access_key --stdin --force
echo "${OVH_S3_SECRET_KEY}" | /usr/share/elasticsearch/bin/elasticsearch-keystore add s3.client.default.secret_key --stdin --force

# CORRECTIF 2026-08-14 (audit systemique suite a l'incident LS_B025_ARMED) :
# les ajouts ci-dessus n'etaient jamais verifies - meme famille de bug qui
# a fait planter Logstash en boucle sur VM1 (voir README, incident 17).
# Job non bloquant par design (voir en-tete) : on avertit sans stopper la
# chaine, plutot que de faire un echec dur comme les jobs du chemin
# critique (LS_B025_ARMED, ES_021/022, KB_017/023, FB_009/010, MB_009/010).
if ! /usr/share/elasticsearch/bin/elasticsearch-keystore list 2>/dev/null | grep -qx "s3.client.default.access_key" || \
   ! /usr/share/elasticsearch/bin/elasticsearch-keystore list 2>/dev/null | grep -qx "s3.client.default.secret_key"; then
  echo "[ES_062_SNAPSHOTS3REPO] AVERTISSEMENT : verification post-ecriture echouee - identifiants S3 absents de 'elasticsearch-keystore list' apres l'ajout (job non bloquant, on continue quand meme)."
fi

echo "[ES_062_SNAPSHOTS3REPO] Rechargement des secrets sans redemarrage complet..."
es_admin_curl -X POST "https://127.0.0.1:${ES_PORT}/_nodes/reload_secure_settings" -o /dev/null

echo "[ES_062_SNAPSHOTS3REPO] Enregistrement du depot '${ES_SNAPSHOT_REPO_NAME}' -> bucket ${OVH_S3_BUCKET}..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_snapshot/${ES_SNAPSHOT_REPO_NAME}" \
  -H "Content-Type: application/json" -d "{
  \"type\": \"s3\",
  \"settings\": {
    \"bucket\": \"${OVH_S3_BUCKET}\",
    \"endpoint\": \"${OVH_S3_ENDPOINT}\",
    \"region\": \"${OVH_S3_REGION}\",
    \"path_style_access\": true
  }
}" -o ${WORK_TMP_DIR}/es062.json

grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es062.json 2>/dev/null && { echo "[ES_062_SNAPSHOTS3REPO] Depot enregistre."; rm -f ${WORK_TMP_DIR}/es062.json; echo "[ES_062_SNAPSHOTS3REPO] OK."; exit 0; }
echo "[ES_062_SNAPSHOTS3REPO] AVERTISSEMENT : reponse inattendue, voir ${WORK_TMP_DIR}/es062.json (job non bloquant, on continue quand meme)."
echo "[ES_062_SNAPSHOTS3REPO] OK."
exit 0
