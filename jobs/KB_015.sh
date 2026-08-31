#!/bin/bash
# KB_015 - WEF_KB_BLD_XSRFHRDNNG - Durcissement des requetes API transverses
#
# CORRECTIF 2026-08-19 (audit systemique declenche par l'incident
# KB_013/core.lazy_services sur wef-elk-core, meme journee) : ce job
# ecrivait "server.xsrf.whitelist: []", un parametre renomme
# "server.xsrf.allowlist" des Kibana 8.0.0 (langage inclusif) - le nom
# "whitelist" est totalement retire depuis, pas seulement deprecie.
# Meme famille de risque que core.lazy_services (incident precedent) :
# une cle inconnue sous un espace de noms reconnu ("server") fait
# echouer Kibana au demarrage avec la meme erreur FATAL "definition for
# this key is missing". Ce job n'avait pas encore ete atteint lors du
# premier crash (KB_013, plus tot dans la sequence, bloquait deja tout)
# - corrige preventivement avant qu'il ne cause le meme type d'incident
# au prochain demarrage reussi de Kibana.
set -uo pipefail
source "$VARS_FILE"
echo "[KB_015] Durcissement XSRF..."
grep -q "^server.xsrf.allowlist:" /etc/kibana/kibana.yml 2>/dev/null || echo "server.xsrf.allowlist: []" >> /etc/kibana/kibana.yml
echo "[KB_015] OK."
exit 0
