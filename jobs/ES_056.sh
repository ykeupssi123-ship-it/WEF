#!/bin/bash
# ES_056 - WEF_ES_RUN_POSTRSTRTPOLL - Polling de reactivite post-purge RAM
#
# CORRECTIF 2026-08-14 (audit systemique) : en cas de timeout, aucun
# diagnostic n'etait affiche - meme lacune que celle qui avait rendu
# l'incident ES_052 difficile a diagnostiquer en reel. Ajoute : dump du
# statut systemd sur echec, pour ne jamais laisser un operateur devant
# un simple "timeout" sans piste.
set -uo pipefail
source "$VARS_FILE"
echo "[ES_056] Attente de reconnexion apres redemarrage a froid..."
for i in $(seq 1 60); do
  curl -s --cacert "${PKI_DIR}/factory_ca.crt" "https://127.0.0.1:${ES_PORT}/" -o /dev/null && { echo "[ES_056] OK."; exit 0; }
  sleep 5
done
echo "[ES_056] ERREUR : timeout post-redemarrage. Statut systemd :" >&2
systemctl status elasticsearch --no-pager >&2 || true
exit 1
