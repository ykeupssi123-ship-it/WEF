#!/bin/bash
# lib/kibana_dataview.sh - creation/mise a jour d'UN Data View Kibana -
# point unique partage par WAZ_036_KIBANA_INDEX.sh,
# BEAC_004_CREATE_KIBANA_DATAVIEWS.sh et KB_030_GENERIC_LOG_DATAVIEW.sh.
#
# AJOUTE LE 2026-10-22 (demande explicite : "normalement on devait
# avoir un seul job... qui fonctionne de maniere abstraite" - trouve
# en verifiant, pas suppose : TROIS scripts reimplementaient le meme
# appel curl vers l'API Kibana, avec des variantes non justifiees -
# WAZ_036 n'avait ni "id" deterministe ni "override":true (un rejeu
# pouvait echouer silencieusement sur un conflit), les deux autres si.
# Jamais une troisieme copie de plus : la logique vit ICI UNE SEULE
# FOIS, chaque job garde son propre declencheur/IN_COND/OUT_COND dans
# jobs_table.csv (ce sont de vraies differences d'orchestration,
# jamais fusionnees) mais appelle cette meme fonction.
#
# A sourcer APRES vars.conf (utilise STATE_DIR, KB_PORT,
# FACTORY_HOST_IP indirectement).
#
# Usage : create_kibana_dataview <index_pattern> <nom_affiche> [id]
#   - index_pattern : ex. "ambargo-*", "wazuh-alerts-*"
#   - nom_affiche   : ex. "Wazuh Alerts", "Logs generiques"
#   - id (optionnel): identifiant Kibana deterministe - par defaut
#     "<index_pattern sans le '-*'>-dataview" (meme convention deja
#     etablie par BEAC_004/KB_030). Toujours fourni + "override":true
#     => idempotent, un rejeu ne casse jamais rien.
# Retourne 0 si HTTP 200, 1 sinon (reponse affichee sur stderr).
set -uo pipefail

create_kibana_dataview(){
  local index_pattern="$1" display_name="$2"
  local id="${3:-${index_pattern%-\*}-dataview}"

  local bootstrap_pw_file="${STATE_DIR}/es_bootstrap_password.secret"
  if [ ! -f "$bootstrap_pw_file" ]; then
    echo "[create_kibana_dataview] ERREUR : ${bootstrap_pw_file} absent (ES_022 doit avoir tourne sur ELK_HOST)." >&2
    return 1
  fi

  echo "[create_kibana_dataview] Data view '${index_pattern}' (${display_name})..."
  local resp_file http_code
  resp_file="$(mktemp)"
  http_code=$(curl -sk -u "elastic:$(cat "$bootstrap_pw_file")" \
    -X POST "https://127.0.0.1:${KB_PORT}/api/data_views/data_view" \
    -H "kbn-xsrf: true" -H "Content-Type: application/json" \
    -d "{\"data_view\":{\"id\":\"${id}\",\"title\":\"${index_pattern}\",\"name\":\"${display_name}\",\"timeFieldName\":\"@timestamp\"},\"override\":true}" \
    -o "$resp_file" -w "%{http_code}")

  if [ "$http_code" != "200" ]; then
    echo "[create_kibana_dataview] ERREUR pour '${index_pattern}' (HTTP ${http_code}) :" >&2
    cat "$resp_file" >&2
    rm -f "$resp_file"
    return 1
  fi
  rm -f "$resp_file"
  echo "[create_kibana_dataview] OK : '${index_pattern}' visible dans Discover."
  return 0
}
