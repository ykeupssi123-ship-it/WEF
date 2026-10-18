#!/bin/bash
# ES_066_COLDARCHIVE_SLMPOLICY - WEF_ES_RUN_COLDSLMPOL
# Politique SLM (Snapshot Lifecycle Management) : planifie des
# sauvegardes regulieres des index log-* vers le depot local enregistre
# par ES_065. Meme discipline toggle que ES_063 (variant S3) mais pour
# le depot local, variable independante ES_COLD_ARCHIVE_ENABLED.
#
# DESACTIVATION REELLE (demande explicite 2026-10-18) : si
# ES_COLD_ARCHIVE_ENABLED=false, la politique SLM est SUPPRIMEE
# (DELETE _slm/policy/<nom>) plutot que laissee inerte - une politique
# supprimee ne peut plus etre executee par le planificateur interne
# d'Elasticsearch, donc plus aucune ressource consommee par
# l'archivage, exactement comme demande ("le jour ou il n'est pas
# d'accord on desactive et ca ne consomme plus les ressources").
#
# CORRIGE LE 2026-10-18 (incident reel, disque a 95%) : "partial": true est
# necessaire car Elasticsearch refuse de sauvegarder TOUT le lot log-* des
# qu'un seul index du lot a un shard primaire non assigne (ex: bloque par le
# watermark disque) - sans ce reglage, un seul index en souffrance bloque
# l'archivage de tous les autres qui vont bien.
#
# CORRIGE LE 2026-10-18 (meme incident, decouverte suivante, preuve directe
# via _slm/policy?human : "last_failure", jamais "last_success") :
# "partial": true evite le REJET de la sauvegarde mais SLM l'enregistre quand
# meme comme un ECHEC global des qu'un seul shard manque - et c'est
# last_success (pas le succes individuel d'un index) que l'action ILM
# wait_for_snapshot (ES_067) exige avant de supprimer quoi que ce soit.
# ES_COLD_ARCHIVE_EXCLUDE_INDICES (vars.conf, liste separee par des espaces,
# vide par defaut) permet d'exclure temporairement les index en souffrance
# du perimetre sauvegarde - pour que le reste obtienne un vrai succes complet
# et que l'automatisation ILM reprenne la main toute seule, sans suppression
# manuelle.
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "${BASH_SOURCE[0]}")/lib/es_admin_curl.sh"

POLICY="${ES_COLD_ARCHIVE_POLICY_NAME:-wef_cold_archive_slm}"
REPO="${ES_COLD_ARCHIVE_REPO_NAME:-wef_cold_archive}"

if [ "${ES_COLD_ARCHIVE_ENABLED:-false}" != "true" ]; then
  echo "[ES_066_COLDARCHIVE_SLMPOLICY] Archivage a froid desactive."
  EXISTS=$(es_admin_curl -s -o /dev/null -w "%{http_code}" "https://127.0.0.1:${ES_PORT}/_slm/policy/${POLICY}")
  if [ "$EXISTS" = "200" ]; then
    echo "[ES_066_COLDARCHIVE_SLMPOLICY] Politique '${POLICY}' presente mais desactivee - suppression (plus aucune sauvegarde planifiee)."
    es_admin_curl -X DELETE "https://127.0.0.1:${ES_PORT}/_slm/policy/${POLICY}" -o /dev/null
  fi
  echo "[ES_066_COLDARCHIVE_SLMPOLICY] OK."
  exit 0
fi

CRON="${ES_COLD_ARCHIVE_SCHEDULE_CRON:-0 15 2 * * ?}"
PATTERN="${ES_COLD_ARCHIVE_INDEX_PATTERN:-log-*}"
RET_EXPIRE="${ES_COLD_ARCHIVE_RETENTION_EXPIRE:-90d}"
RET_MIN="${ES_COLD_ARCHIVE_RETENTION_MIN_COUNT:-5}"
RET_MAX="${ES_COLD_ARCHIVE_RETENTION_MAX_COUNT:-200}"

INDICES_JSON="\"${PATTERN}\""
for EXCL in ${ES_COLD_ARCHIVE_EXCLUDE_INDICES:-}; do
  INDICES_JSON="${INDICES_JSON}, \"-${EXCL}\""
done

echo "[ES_066_COLDARCHIVE_SLMPOLICY] Ecriture de la politique '${POLICY}' (depot local ${REPO}, index [${INDICES_JSON}])..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_slm/policy/${POLICY}" \
  -H "Content-Type: application/json" -d "{
  \"schedule\": \"${CRON}\",
  \"name\": \"<wef-cold-{now/d}>\",
  \"repository\": \"${REPO}\",
  \"config\": { \"indices\": [${INDICES_JSON}], \"include_global_state\": false, \"partial\": true },
  \"retention\": { \"expire_after\": \"${RET_EXPIRE}\", \"min_count\": ${RET_MIN}, \"max_count\": ${RET_MAX} }
}" -o "${WORK_TMP_DIR}/es066.json"

if ! grep -q '"acknowledged":true' "${WORK_TMP_DIR}/es066.json" 2>/dev/null; then
  echo "[ES_066_COLDARCHIVE_SLMPOLICY] AVERTISSEMENT : reponse inattendue, voir ${WORK_TMP_DIR}/es066.json (job non bloquant, on continue quand meme)." >&2
  echo "[ES_066_COLDARCHIVE_SLMPOLICY] OK."
  exit 0
fi
rm -f "${WORK_TMP_DIR}/es066.json"

echo "[ES_066_COLDARCHIVE_SLMPOLICY] Declenchement immediat d'une premiere sauvegarde (ne bloque pas, s'execute en tache de fond cote Elasticsearch)..."
es_admin_curl -X POST "https://127.0.0.1:${ES_PORT}/_slm/policy/${POLICY}/_execute" -o /dev/null

echo "[ES_066_COLDARCHIVE_SLMPOLICY] Politique active."
echo "[ES_066_COLDARCHIVE_SLMPOLICY] OK."
exit 0
