#!/bin/bash
# ES_053 - WEF_ES_RUN_POSTCRASHPOLL - Reponse API post-destruction
#
# CORRECTIF 2026-08-14 (audit systemique) : en cas de timeout, aucun
# diagnostic n'etait affiche (incident reel VM1 : 5 minutes de poll
# silencieux avant l'echec, sans indice que le vrai probleme etait
# ES_052 qui n'avait jamais reellement relance le service - voir
# ES_052.sh et README, incident 12). Ajoute : dump du statut systemd
# sur echec.
set -uo pipefail
source "$VARS_FILE"
echo "[ES_053] Attente de la reprise d'Elasticsearch apres crash..."
for i in $(seq 1 60); do
  curl -s --cacert "${PKI_DIR}/factory_ca.crt" "https://127.0.0.1:${ES_PORT}/" -o /dev/null && { echo "[ES_053] OK."; exit 0; }
  sleep 5
done
echo "[ES_053] ERREUR : Elasticsearch ne repond pas apres le crash-test. Statut systemd :" >&2
systemctl status elasticsearch --no-pager >&2 || true
exit 1
