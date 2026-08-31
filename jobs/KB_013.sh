#!/bin/bash
# KB_013 - WEF_KB_BLD_STNDLNMOD - Mode Core asynchrone
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core) : ce job ecrivait
# "core.lazy_services: true" dans kibana.yml - un parametre qui N'EXISTE
# PAS dans Kibana (aucune trace dans la documentation officielle ni les
# issues GitHub Elastic, verifie par recherche). Consequence reelle :
# Kibana refuse purement et simplement de demarrer des qu'il rencontre
# une cle inconnue sous l'espace de noms "core" (validation stricte du
# schema de configuration, contrairement a certains autres espaces qui se
# contentent d'avertir) - erreur FATAL "config validation of
# [core].lazy_services: definition for this key is missing", boucle de
# redemarrage systemd sans jamais reussir a ouvrir le port 5601. Cette
# cle n'a jamais eu d'equivalent reel a activer : le job est donc
# desormais un no-op assume (il ne touche plus a kibana.yml), qui
# continue neanmoins de produire son OUT_COND habituel pour ne rien
# casser dans la chaine de dependances. Deblocage manuel effectue en
# direct sur wef-elk-core : suppression de la ligne invalide
# (sed -i '/^core.lazy_services:/d' /etc/kibana/kibana.yml) puis
# redemarrage de Kibana - confirme reussi.
set -uo pipefail
source "$VARS_FILE"
echo "[KB_013] Aucun parametre reel a appliquer ici (voir CORRECTIF ci-dessus - l'ancienne cle 'core.lazy_services' n'existe pas dans Kibana), etape neutre."
echo "[KB_013] OK."
exit 0
