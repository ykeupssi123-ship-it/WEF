#!/bin/bash
# ES_041 - WEF_ES_RUN_IDXLIMIT - Disjoncteur cluster : namespaces autorises
#
# CORRIGE LE 2026-09-13 (incident reel, scenario metier BEAC) : le
# nouvel index "ambargo-*" etait rejete en silence par le cluster -
# Logstash envoyait bien sa requete groupee (compte "out" correct cote
# Logstash), mais Elasticsearch refusait la creation de l'index lui-meme
# (`action.auto_create_index` limite deliberement a "log-*,wazuh-*"
# depuis la mise en place de ce disjoncteur - meme classe d'incident
# deja rencontree une fois avec ES_046/"factory-stresstest", voir
# docs/JOURNAL_TECHNIQUE.md). Aucune erreur visible cote Logstash dans
# ce cas precis - confirme uniquement via
# "_cluster/settings?include_defaults=true". Corrige en etendant la
# liste blanche plutot qu'en la desactivant - le principe de durcissement
# reste intact, seuls les motifs legitimes sont ajoutes.
#
# SIMPLIFIE LE MEME JOUR (demande explicite : "un peu comme AllowUsers
# en SSH ... tout ce qu'il y aura sur cette ligne, leur index doit etre
# cree") : au lieu de verifier chaque variable de prefixe une par une
# (ce qui obligeait a modifier CE fichier a chaque nouveau scenario),
# lit desormais UNE SEULE liste generique, ES_DEMO_INDEX_PREFIXES
# (vars.conf, separee par des virgules) - ajouter un futur scenario ne
# touche plus jamais ce fichier, juste vars.conf. Retro-compatible : si
# cette variable est absente/vide (VM sur "main", sans scenario de
# demo), le comportement reste strictement identique a avant
# (uniquement "log-*,wazuh-*,-*").
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "$0")/lib/es_admin_curl.sh"
echo "[ES_041] Restriction de creation d'index aux namespaces autorises..."
AUTO_CREATE_PATTERN="log-*,wazuh-*"
if [ -n "${ES_DEMO_INDEX_PREFIXES:-}" ]; then
  IFS=',' read -ra DEMO_PREFIXES <<< "$ES_DEMO_INDEX_PREFIXES"
  for prefix in "${DEMO_PREFIXES[@]}"; do
    # Retire les espaces autour (tolerance de saisie, ex. "ambargo, cyriellemoney").
    prefix="$(echo "$prefix" | xargs)"
    [ -n "$prefix" ] && AUTO_CREATE_PATTERN="${AUTO_CREATE_PATTERN},${prefix}-*"
  done
fi
AUTO_CREATE_PATTERN="${AUTO_CREATE_PATTERN},-*"
echo "[ES_041] Motifs autorises : ${AUTO_CREATE_PATTERN}"
es_admin_curl -X PUT "https://127.0.0.1:${ES_PORT}/_cluster/settings" \
  -H "Content-Type: application/json" -d "{
    \"persistent\": {\"action.auto_create_index\": \"${AUTO_CREATE_PATTERN}\"}
  }" -o ${WORK_TMP_DIR}/es041.json
grep -q '"acknowledged":true' ${WORK_TMP_DIR}/es041.json && { echo "[ES_041] OK."; rm -f ${WORK_TMP_DIR}/es041.json; exit 0; }
echo "[ES_041] ERREUR, voir ${WORK_TMP_DIR}/es041.json"; exit 1
