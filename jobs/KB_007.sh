#!/bin/bash
# KB_007 - WEF_KB_BLD_FWPORT5601 - Ouverture de l'acces au port 5601
#
# CORRIGE LE 2026-08-31 (incident reel wef-elk-core, decouvert en
# testant les liens https depuis le PC physique de l'utilisateur :
# https://<ip>:5601 -> ERR_CONNECTION_TIMED_OUT). Diagnostic complet :
# "UI_Zone" (ciblee ci-dessous) n'est liee a AUCUNE interface reseau
# (confirme : `firewall-cmd --list-all --zone=UI_Zone` -> "interfaces:"
# vide) - l'interface reelle de la VM (ens160) appartient a la zone
# "public" (confirme via `firewall-cmd --get-active-zones`), jamais a
# "UI_Zone". Contrairement a 9200/1514/1515/55000/443 (ports natifs
# Wazuh, ouverts par coincidence dans "public" par les paquets RPM
# eux-memes), Kibana n'a JAMAIS eu cette chance : ce job etait le SEUL
# cense l'ouvrir, et sa regle etait invisible au trafic reel depuis
# l'origine de cette usine - Kibana n'a donc jamais ete reellement
# joignable depuis l'exterieur, meme lors des sessions precedentes.
# Meme famille de bug trouvee et corrigee le meme jour dans
# WAZ_005.sh/WAZ_006.sh/ES_013.sh/ES_014.sh (toutes des zones jamais
# liees a une interface) - corrige en ciblant "public", la seule zone
# reellement active. Ajout de --reload (absent ici a l'origine) : une
# regle --permanent ne prend jamais effet sans reload explicite.
set -uo pipefail
source "$VARS_FILE"
echo "[KB_007] Ouverture du port ${KB_PORT}/tcp sur public..."
firewall-cmd --permanent --zone=public --add-port=${KB_PORT}/tcp
firewall-cmd --reload
echo "[KB_007] OK."
exit 0
