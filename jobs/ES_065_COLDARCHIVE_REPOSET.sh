#!/bin/bash
# ES_065_COLDARCHIVE_REPOSET - WEF_ES_RUN_COLDREPOSET
# Enregistre (idempotent, PUT = ecrasement propre) un depot de snapshots
# Elasticsearch LOCAL (filesystem, /home - separe de / qui est le disque
# sous pression) pour l'archivage "a froid" des vieux index quotidiens
# log-*. Complement local de ES_062/063 (depot S3 OVH, desactive tant
# qu'aucun compte OVH n'est configure) - meme principe de toggle, meme
# style, variable differente pour rester independant.
#
# TOGGLE CLIENT REEL (demande explicite 2026-10-18) : ce job (et
# ES_066/ES_067) doit pouvoir etre active OU desactive par un client,
# sans consommer de ressources une fois desactive - pas juste "ignore".
# Si ES_COLD_ARCHIVE_ENABLED=false, le depot deja enregistre est
# DESINSCRIT (DELETE _snapshot/<repo>) plutot que simplement laisse tel
# quel - un depot desinscrit ne consomme plus rien (aucune tache
# planifiee ES ne peut plus le referencer).
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "${BASH_SOURCE[0]}")/lib/es_admin_curl.sh"

REPO="${ES_COLD_ARCHIVE_REPO_NAME:-wef_cold_archive}"

if [ "${ES_COLD_ARCHIVE_ENABLED:-false}" != "true" ]; then
  echo "[ES_065_COLDARCHIVE_REPOSET] Archivage a froid desactive (ES_COLD_ARCHIVE_ENABLED=false)."
  EXISTS=$(es_admin_curl -s -o /dev/null -w "%{http_code}" "https://127.0.0.1:${ES_PORT}/_snapshot/${REPO}")
  if [ "$EXISTS" = "200" ]; then
    echo "[ES_065_COLDARCHIVE_REPOSET] Depot '${REPO}' present mais desactive - desinscription (plus aucune ressource consommee)."
    es_admin_curl -X DELETE "https://127.0.0.1:${ES_PORT}/_snapshot/${REPO}" -o /dev/null
  fi
  echo "[ES_065_COLDARCHIVE_REPOSET] OK."
  exit 0
fi

REPO_PATH="${ES_COLD_ARCHIVE_REPO_PATH:-/home/es_archive}"
echo "[ES_065_COLDARCHIVE_REPOSET] Preparation du repertoire local ${REPO_PATH}..."
mkdir -p "$REPO_PATH"
chown elasticsearch:elasticsearch "$REPO_PATH"
chmod 750 "$REPO_PATH"

if ! grep -q "path.repo" /etc/elasticsearch/elasticsearch.yml 2>/dev/null; then
  echo "[ES_065_COLDARCHIVE_REPOSET] AVERTISSEMENT : path.repo absent de elasticsearch.yml - ajoutez-le manuellement (chattr -i, echo, chattr +i) puis redemarrez elasticsearch une fois. Ce job ne modifie jamais la configuration statique du service lui-meme (deja immutable par convention)." >&2
  echo "[ES_065_COLDARCHIVE_REPOSET] OK (en attente de configuration manuelle)."
  exit 0
fi

echo "[ES_065_COLDARCHIVE_REPOSET] Enregistrement du depot local '${REPO}' -> ${REPO_PATH}..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_snapshot/${REPO}" \
  -H "Content-Type: application/json" -d "{
  \"type\": \"fs\",
  \"settings\": { \"location\": \"${REPO_PATH}\", \"compress\": true }
}" -o "${WORK_TMP_DIR}/es065.json"

grep -q '"acknowledged":true' "${WORK_TMP_DIR}/es065.json" 2>/dev/null && { echo "[ES_065_COLDARCHIVE_REPOSET] Depot enregistre."; rm -f "${WORK_TMP_DIR}/es065.json"; echo "[ES_065_COLDARCHIVE_REPOSET] OK."; exit 0; }
echo "[ES_065_COLDARCHIVE_REPOSET] AVERTISSEMENT : reponse inattendue, voir ${WORK_TMP_DIR}/es065.json (job non bloquant, on continue quand meme)." >&2
echo "[ES_065_COLDARCHIVE_REPOSET] OK."
exit 0
