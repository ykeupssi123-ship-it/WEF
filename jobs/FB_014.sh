#!/bin/bash
# FB_014 - WEF_FB_BLD_LOGPOLL - Analyse du demarrage sans erreur
#
# CORRIGE LE 2026-08-31 (incident reel, premier deploiement d'agent sur
# 192.168.50.130) : /var/log/filebeat/filebeat (texte brut) n'existe
# jamais sur Filebeat 8.19 - le paquet ecrit desormais en JSON structure
# dans un fichier date (/var/log/filebeat/filebeat-AAAAMMJJ.ndjson) ET
# dans journald simultanement (unite systemd) - confirme en reel par
# inspection directe. Ce job attendait donc un fichier qui ne serait
# jamais apparu, timeout garanti a chaque fois. Corrige : lecture du
# journal reel de l'unite systemd (toujours present, quelle que soit la
# rotation de fichier), recherche du compteur structure
# "harvester":{"...,"running":N (confirme present en reel dans les
# rapports de metriques periodiques de Filebeat) avec N > 0 - preuve
# reelle que des fichiers sont effectivement en cours de lecture, jamais
# une simple supposition de format de message.
set -uo pipefail
source "$VARS_FILE"
echo "[FB_014] Attente de la confirmation reelle qu'un harvester est actif (journal systemd)..."
for i in $(seq 1 60); do
  if journalctl -u filebeat --no-pager -n 200 2>/dev/null | grep -oE '"harvester":\{[^}]*"running":[0-9]+' | grep -qE '"running":[1-9]'; then
    echo "[FB_014] OK (harvester(s) reellement actif(s), confirme par les metriques Filebeat)."
    exit 0
  fi
  sleep 5
done
echo "[FB_014] ERREUR : timeout, aucun harvester actif detecte dans le journal systemd de filebeat."
exit 1
