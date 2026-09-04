#!/bin/bash
# ES_026 - WEF_ES_BLD_STARTENGINE - Demarrage du demon Elasticsearch
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core) : ce job ne faisait
# jamais "systemctl enable elasticsearch", contrairement a TOUS les autres
# services du projet (KB_018, LS_026_FINAL, FB_013, MB_013, WAZ_014,
# WAZ_015, WAZ_016, WAG_005), qui ont tous recu ce correctif suite a
# l'incident 25 ("systemctl enable --now" ne redemarre pas un service deja
# actif - la solution retenue partout ailleurs a ete de separer
# explicitement enable et restart/start). Elasticsearch, seul service du
# projet, avait ete oublie de cette generalisation - constate en reel :
# le serveur a redemarre plusieurs fois en une semaine (`last reboot`),
# et a chaque fois `systemctl status elasticsearch` revenait a
# "disabled"/"inactive (dead)" (aucune ligne dans journalctl depuis le
# redemarrage), pendant que Kibana, deja enable par KB_018, redemarrait
# bien tout seul et echouait avec "connect ECONNREFUSED 127.0.0.1:9200" -
# Elasticsearch etant le tout premier service de la chaine dont tout le
# reste depend, son absence d'enable cassait silencieusement l'ensemble
# de la usine a chaque reboot serveur, sans qu'aucun job ne le signale
# jamais (l'orchestrateur n'est simplement jamais relance automatiquement
# apres un reboot). Corrige : enable et restart separes, meme idiome que
# les 8 autres services deja corriges.
set -uo pipefail
source "$VARS_FILE"
echo "[ES_026] Activation au demarrage (persistance apres reboot serveur)..."
systemctl daemon-reload
systemctl enable elasticsearch 2>/dev/null || true
echo "[ES_026] Demarrage d'Elasticsearch..."
if ! systemctl restart elasticsearch; then
  echo "[ES_026] ERREUR : elasticsearch.service n'a pas demarre. Diagnostic (journalctl -u elasticsearch -n 30) :"
  journalctl -u elasticsearch -n 30 --no-pager 2>/dev/null || true
  echo "[ES_026] Voir aussi /var/log/elasticsearch/*.log pour le detail complet."
  exit 1
fi
echo "[ES_026] OK."
exit 0
