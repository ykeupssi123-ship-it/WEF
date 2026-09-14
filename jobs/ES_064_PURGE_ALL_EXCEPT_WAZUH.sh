#!/bin/bash
# ES_064_PURGE_ALL_EXCEPT_WAZUH - WEF_ES_RUN_PURGEALLXWAZ
#
# Purge complete et irreversible de TOUS les index Elasticsearch, SAUF
# la famille "wazuh-*" (wazuh-alerts-4.x-*, wazuh-monitoring-*, etc.) -
# demande explicite : "les alertes wazuh appartiennent a la famille de
# wazuh, ils sont juste en location chez elasticsearch" - jamais
# touches par ce job, quel que soit leur contenu.
#
# DESTRUCTEUR ET IRREVERSIBLE - jamais dans la chaine automatique.
# IN_COND=WAZ_PURGE_MANUAL_GATE (jamais satisfaite ailleurs), meme
# discipline que WAZ_046/047/049E/049G : usage EXCLUSIVEMENT volontaire
# via bin/order.sh, avec sa propre confirmation (retaper le JOB_ID) et
# sa raison obligatoire deja imposees par order.sh lui-meme.
#
# Different des purges existantes (chacune vide UN pattern fige en
# dur) : celui-ci decouvre DYNAMIQUEMENT, au moment de l'execution, la
# liste reelle des index presents - un futur scenario metier ou un
# futur index de test tombe automatiquement dans le perimetre "a
# purger" sans jamais devoir modifier ce script, seul le prefixe
# "wazuh-" est protege en dur.
#
# "Purge" ici = meme semantique que le reste du projet (purge_index_pattern,
# jobs/lib/test_data_tools.sh) : VIDE le contenu (documents) via
# _delete_by_query, ne supprime jamais la structure/le mapping de
# l'index lui-meme - coherent avec WAZ_046/047/049E/049G.
#
# Les index caches/systeme (".kibana*", ".security*", etc., prefixes
# par un point) sont deja exclus nativement par l'API _cat/indices sans
# "expand_wildcards=all" - jamais dans la liste balayee ici, aucun
# risque de casser Kibana lui-meme.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
source "$PROJECT_ROOT/jobs/lib/test_data_tools.sh"

ES_BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
[ -f "$ES_BOOTSTRAP_PW_FILE" ] || { echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] ERREUR : ${ES_BOOTSTRAP_PW_FILE} absent (ES_022 doit avoir tourne)." >&2; exit 1; }
ES_BOOTSTRAP_PW="$(cat "$ES_BOOTSTRAP_PW_FILE")"
ES_URL="https://127.0.0.1:${ES_PORT}"

echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] Inventaire des index reels presents..."
ALL_INDICES="$(curl -sk -u "elastic:${ES_BOOTSTRAP_PW}" "${ES_URL}/_cat/indices?h=index" | sort)"
if [ -z "$ALL_INDICES" ]; then
  echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] Aucun index present, rien a faire."
  exit 0
fi

TO_PURGE=()
KEPT=()
while IFS= read -r idx; do
  [ -z "$idx" ] && continue
  case "$idx" in
    wazuh-*) KEPT+=("$idx") ;;
    *) TO_PURGE+=("$idx") ;;
  esac
done <<< "$ALL_INDICES"

echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] Index preserves (famille wazuh-*, jamais touches) : ${KEPT[*]:-aucun}"
if [ ${#TO_PURGE[@]} -eq 0 ]; then
  echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] Aucun index hors famille wazuh-*, rien a purger."
  exit 0
fi
echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] Index a purger (${#TO_PURGE[@]}) : ${TO_PURGE[*]}"

TARGET_PATTERN="$(IFS=,; echo "${TO_PURGE[*]}")"
purge_index_pattern "$ES_URL" "elastic" "${ES_BOOTSTRAP_PW}" "${PKI_DIR}/factory_ca.crt" "$TARGET_PATTERN"
PURGE_EXIT=$?
if [ $PURGE_EXIT -ne 0 ]; then
  echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] ERREUR : la purge a echoue (voir sortie ci-dessus)." >&2
  exit 1
fi

echo "[ES_064_PURGE_ALL_EXCEPT_WAZUH] OK (${#TO_PURGE[@]} index vides, famille wazuh-* preservee)."
exit 0
