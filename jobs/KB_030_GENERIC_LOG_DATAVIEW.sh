#!/bin/bash
# KB_030_GENERIC_LOG_DATAVIEW - WEF_KB_RUN_LOGDATAVIEW
#
# Cree le Data View Kibana pour l'index generique catch-all
# "${ES_INDEX_NAME_PREFIX}-*" (defaut "log") - la ou atterrissent tous
# les evenements qui ne sont ni Wazuh (WAZ_036_KIBANA_INDEX.sh), ni un
# scenario metier BEAC dedie (BEAC_004_CREATE_KIBANA_DATAVIEWS.sh) -
# notamment Filebeat/Metricbeat generiques.
#
# AJOUTE LE 2026-09-24 (incident reel documente dans l'historique de ce
# fichier). AJOUTE LE 2026-10-22 : le curl lui-meme vit desormais dans
# lib/kibana_dataview.sh (create_kibana_dataview), partage avec
# WAZ_036/BEAC_004 - jamais une troisieme copie du meme appel API.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/kibana_dataview.sh"

PREFIX="${ES_INDEX_NAME_PREFIX:-log}"
create_kibana_dataview "${PREFIX}-*" "Logs generiques" "${PREFIX}-dataview"
exit $?
