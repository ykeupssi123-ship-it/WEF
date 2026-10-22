#!/bin/bash
# WAZ_036_KIBANA_INDEX - WEF_WAZ_RUN_KBIDXNEW
# Cree/attache l'index pattern Kibana pour les alertes Wazuh, une fois
# le routage bascule vers Logstash/Elasticsearch (mode convergent).
#
# POSITION DELIBEREE dans la chaine (IN_COND=WAZ_WAZUI_STOPPED,
# verifie le 2026-10-22) : tourne juste apres l'arret du Wazuh
# Dashboard pendant la bascule, et juste AVANT WAZ_037_CONVERGENT_TEST
# qui prouve que les alertes arrivent reellement apres la bascule -
# jamais fusionne avec un job generique "des que Kibana est en ligne",
# ce serait perdre cette garantie de sequence.
#
# AJOUTE LE 2026-10-22 : le curl lui-meme vit desormais dans
# lib/kibana_dataview.sh (create_kibana_dataview), partage avec
# BEAC_004/KB_030 - jamais une troisieme copie du meme appel API.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/kibana_dataview.sh"

create_kibana_dataview "wazuh-alerts-*" "Wazuh Alerts" "wazuh-alerts-dataview"
exit $?
