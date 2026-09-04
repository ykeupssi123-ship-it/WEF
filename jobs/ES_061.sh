#!/bin/bash
# ES_061 - WEF_ES_RUN_GTECHASSIS - Vanne maitresse : emission DALLE_ELASTIC_ONLINE
# JOB PASSERELLE reel (ouvre vers KB et LS) : l'orchestrateur cree lui-meme
# le fichier state/DALLE_ELASTIC_ONLINE.ok quand ce script sort en 0 -
# ce job n'a rien d'autre a faire que confirmer que tout est vraiment pret.
#
# CORRECTIF 2026-08-14 (incident reel pre-demo, VM1) : ce job appelait
# _cluster/health SANS authentification (curl sans -u), alors que la
# securite Elasticsearch est active depuis ES_022/ES_027 - toute requete
# non authentifiee recoit un 401 (security_exception), dont le corps ne
# contient evidemment jamais "status":"green"/"yellow". Le job echouait
# donc systematiquement avec le message trompeur "cluster non sain" alors
# que le cluster etait en realite parfaitement sain (confirme par ES_053-
# ES_060 juste avant, tous OK dans la meme execution). Seul job de tout
# le projet a interroger l'API Elasticsearch directement sans passer par
# es_admin_curl (verifie : les 7 autres jobs touchant l'API ES sont soit
# deja authentifies, soit un simple test de liveness/poignee de main TLS
# qui n'a pas besoin de lire le corps de la reponse). Corrige : passe
# desormais par es_admin_curl (lib/es_admin_curl.sh), comme tous les
# autres controles admin du projet (ES_046, WAZ_037, WAZ_040...). En
# prime, le fichier de diagnostic n'est plus supprime en cas d'echec
# (il l'etait avant, contrairement a la convention du reste du projet -
# voir README, incident 11 : un job qui echoue doit laisser sa preuve).
set -uo pipefail
source "$VARS_FILE"
source "$(dirname "${BASH_SOURCE[0]}")/lib/es_admin_curl.sh"
echo "[ES_061] Verification finale avant ouverture du signal DALLE_ELASTIC_ONLINE..."
es_admin_curl "https://127.0.0.1:${ES_PORT}/_cluster/health" -o "${WORK_TMP_DIR}/es061.json"
grep -qE '"status":"(green|yellow)"' "${WORK_TMP_DIR}/es061.json" || { echo "[ES_061] ERREUR : cluster non sain, signal NON emis. Voir ${WORK_TMP_DIR}/es061.json"; exit 1; }
rm -f "${WORK_TMP_DIR}/es061.json"
echo "[ES_061] Chassis Elasticsearch disponible. Signal DALLE_ELASTIC_ONLINE emis."
echo "[ES_061] OK."
exit 0
