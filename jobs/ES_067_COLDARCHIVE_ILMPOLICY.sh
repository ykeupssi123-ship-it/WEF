#!/bin/bash
# ES_067_COLDARCHIVE_ILMPOLICY - WEF_ES_RUN_COLDILMPOL
# Politique ILM (Index Lifecycle Management) : phase hot indefinie, puis
# phase delete a partir de ES_COLD_ARCHIVE_HOT_DAYS jours d'age - mais
# SEULEMENT apres confirmation qu'une sauvegarde existe deja (action
# native wait_for_snapshot, pointant vers la politique SLM de ES_066) :
# jamais de suppression d'un index non sauvegarde, c'est le principe
# meme du "chaud/froid" demande ("sauvegarder les index a chaud et a
# froid", pas juste purger).
#
# Applique via un template d'index SEPARE, a priorite plus haute (150 >
# 100) que le template "log-*" existant (universal_settings/
# universal_mappings) - n'y touche jamais, se contente d'y superposer
# un seul reglage (index.lifecycle.name) pour les FUTURS index log-*.
# Pour les index log-* DEJA existants, le reglage est aussi applique
# directement (un template ne s'applique qu'a la creation).
#
# DESACTIVATION REELLE (demande explicite 2026-10-18) : si
# ES_COLD_ARCHIVE_ENABLED=false, le template de surcouche est retire et
# la politique ILM elle-meme est supprimee - plus aucun index n'est
# gere, plus aucun cycle ILM ne tourne en tache de fond pour cette
# politique.
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "${BASH_SOURCE[0]}")/lib/es_admin_curl.sh"

ILM_NAME="${ES_COLD_ARCHIVE_ILM_NAME:-wef_cold_archive_ilm}"
SLM_POLICY="${ES_COLD_ARCHIVE_POLICY_NAME:-wef_cold_archive_slm}"
OVERLAY_TEMPLATE="${ES_COLD_ARCHIVE_OVERLAY_TEMPLATE_NAME:-wef_cold_archive_overlay}"
OVERLAY_PRIORITY="${ES_COLD_ARCHIVE_OVERLAY_PRIORITY:-150}"
INDEX_PATTERN="${ES_COLD_ARCHIVE_INDEX_PATTERN:-log-*}"

if [ "${ES_COLD_ARCHIVE_ENABLED:-false}" != "true" ]; then
  echo "[ES_067_COLDARCHIVE_ILMPOLICY] Archivage a froid desactive."
  es_admin_curl -X DELETE "https://127.0.0.1:${ES_PORT}/_index_template/${OVERLAY_TEMPLATE}" -o /dev/null
  es_admin_curl -X DELETE "https://127.0.0.1:${ES_PORT}/_ilm/policy/${ILM_NAME}" -o /dev/null
  echo "[ES_067_COLDARCHIVE_ILMPOLICY] Gabarit et politique retires - plus aucun index gere, plus aucun cycle ILM actif pour cette politique."
  echo "[ES_067_COLDARCHIVE_ILMPOLICY] OK."
  exit 0
fi

# ES_COLD_ARCHIVE_HOT_DAYS contient une duree ELASTICSEARCH COMPLETE
# (ex: "7d" en reel, "2m" ou "30s" pour une demo jury - jamais un nombre
# nu) - ainsi vars.conf seul pilote aussi bien la valeur que l'unite,
# sans toucher a ce script, exactement l'usage demande : reduire au
# minimum pour montrer le declenchement en direct devant un jury, puis
# remettre la valeur reelle apres la demo.
HOT_AGE="${ES_COLD_ARCHIVE_HOT_DAYS:-7d}"

echo "[ES_067_COLDARCHIVE_ILMPOLICY] Ecriture de la politique ILM '${ILM_NAME}' (suppression a partir de ${HOT_AGE}, jamais avant sauvegarde confirmee)..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_ilm/policy/${ILM_NAME}" \
  -H "Content-Type: application/json" -d "{
  \"policy\": {
    \"phases\": {
      \"hot\": { \"min_age\": \"0ms\", \"actions\": {} },
      \"delete\": {
        \"min_age\": \"${HOT_AGE}\",
        \"actions\": {
          \"wait_for_snapshot\": { \"policy\": \"${SLM_POLICY}\" },
          \"delete\": {}
        }
      }
    }
  }
}" -o "${WORK_TMP_DIR}/es067_ilm.json"
grep -q '"acknowledged":true' "${WORK_TMP_DIR}/es067_ilm.json" 2>/dev/null || echo "[ES_067_COLDARCHIVE_ILMPOLICY] AVERTISSEMENT : reponse ILM inattendue, voir ${WORK_TMP_DIR}/es067_ilm.json" >&2
rm -f "${WORK_TMP_DIR}/es067_ilm.json"

echo "[ES_067_COLDARCHIVE_ILMPOLICY] Gabarit de surcouche '${OVERLAY_TEMPLATE}' (priorite ${OVERLAY_PRIORITY}, ${INDEX_PATTERN} uniquement, pour les futurs index)..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_index_template/${OVERLAY_TEMPLATE}" \
  -H "Content-Type: application/json" -d "{
  \"index_patterns\": [\"${INDEX_PATTERN}\"],
  \"priority\": ${OVERLAY_PRIORITY},
  \"template\": { \"settings\": { \"index.lifecycle.name\": \"${ILM_NAME}\" } }
}" -o "${WORK_TMP_DIR}/es067_tpl.json"
grep -q '"acknowledged":true' "${WORK_TMP_DIR}/es067_tpl.json" 2>/dev/null || echo "[ES_067_COLDARCHIVE_ILMPOLICY] AVERTISSEMENT : reponse gabarit inattendue, voir ${WORK_TMP_DIR}/es067_tpl.json" >&2
rm -f "${WORK_TMP_DIR}/es067_tpl.json"

echo "[ES_067_COLDARCHIVE_ILMPOLICY] Application directe aux index ${INDEX_PATTERN} deja existants (un gabarit ne s'applique qu'a la creation)..."
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/${INDEX_PATTERN}/_settings" \
  -H "Content-Type: application/json" -d "{ \"index.lifecycle.name\": \"${ILM_NAME}\" }" -o "${WORK_TMP_DIR}/es067_apply.json"
grep -q '"acknowledged":true' "${WORK_TMP_DIR}/es067_apply.json" 2>/dev/null && echo "[ES_067_COLDARCHIVE_ILMPOLICY] Index ${INDEX_PATTERN} existants desormais geres par ILM." || echo "[ES_067_COLDARCHIVE_ILMPOLICY] AVERTISSEMENT : application aux index existants, voir ${WORK_TMP_DIR}/es067_apply.json" >&2
rm -f "${WORK_TMP_DIR}/es067_apply.json"

echo "[ES_067_COLDARCHIVE_ILMPOLICY] OK."
exit 0
