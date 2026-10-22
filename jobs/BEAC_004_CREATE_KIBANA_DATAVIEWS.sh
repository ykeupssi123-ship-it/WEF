#!/bin/bash
# BEAC_004_CREATE_KIBANA_DATAVIEWS - WEF_BEAC_BLD_KBDATAVIEWS
#
# Cree automatiquement, dans Kibana, un Data View par prefixe d'index
# autorise dans ES_DEMO_INDEX_PREFIXES (vars.conf) - sans ce job, un
# index cree cote Elasticsearch n'apparait PAS tout seul dans le
# selecteur "Data view" de Discover.
#
# Generique et non code en dur : lit ES_DEMO_INDEX_PREFIXES et cree un
# data view par prefixe - tout nouveau prefixe ajoute a cette ligne de
# vars.conf devient visible dans Kibana sans toucher a ce script.
#
# AJOUTE LE 2026-10-22 : le curl lui-meme vit desormais dans
# lib/kibana_dataview.sh (create_kibana_dataview), partage avec
# WAZ_036/KB_030 - jamais une troisieme copie du meme appel API.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/kibana_dataview.sh"

if [ -z "${ES_DEMO_INDEX_PREFIXES:-}" ]; then
  echo "[BEAC_004_CREATE_KIBANA_DATAVIEWS] ES_DEMO_INDEX_PREFIXES est vide : rien a creer (normal sur une installation sans scenario metier actif)."
  exit 0
fi

FAILED=0
IFS=',' read -ra PREFIXES <<< "$ES_DEMO_INDEX_PREFIXES"
for raw_prefix in "${PREFIXES[@]}"; do
  prefix="$(echo "$raw_prefix" | xargs)"
  [ -z "$prefix" ] && continue
  create_kibana_dataview "${prefix}-*" "$prefix" "${prefix}-dataview" || FAILED=1
done

[ $FAILED -eq 0 ] && exit 0
exit 1
