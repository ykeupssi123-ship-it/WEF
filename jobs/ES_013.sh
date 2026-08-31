#!/bin/bash
# ES_013 - WEF_ES_BLD_FWOPEN9200 - Ouverture du port 9200
#
# CORRIGE LE 2026-08-31 (meme audit reel que WAZ_005.sh/WAZ_006.sh -
# meme diagnostic : "IngestionZone" n'est liee a AUCUNE interface
# reseau, regle invisible au trafic reel depuis l'origine de cette
# usine). SANS IMPACT FONCTIONNEL AUJOURD'HUI, a noter honnetement :
# ES_023.sh isole deliberement Elasticsearch sur network.host: 127.0.0.1
# (design voulu, "Isolation stricte" selon son propre en-tete) - aucune
# regle de pare-feu, correcte ou non, ne rendrait ce port joignable de
# l'exterieur tant que ce choix de binding reste en place. Corrige quand
# meme, pour la coherence et si ce choix d'isolation venait a changer un
# jour : cible desormais "public", la seule zone reellement active sur
# l'interface.
set -uo pipefail
source "$VARS_FILE"
echo "[ES_013] Ouverture du port ${ES_PORT}/tcp sur public..."
firewall-cmd --permanent --zone=public --add-port=${ES_PORT}/tcp
firewall-cmd --reload
echo "[ES_013] OK."
exit 0
