#!/bin/bash
# ES_027 - WEF_ES_RUN_HLTPOLL - Polling local actif de l'API (jusqu'a reponse)
set -uo pipefail
source "$VARS_FILE"
echo "[ES_027] Attente de la reponse d'Elasticsearch..."
PORT_OK=0
for i in $(seq 1 60); do
  if curl -s --cacert "${PKI_DIR}/factory_ca.crt" "https://127.0.0.1:${ES_PORT}/" -o /dev/null; then
    echo "[ES_027] Elasticsearch repond (port ouvert)."
    PORT_OK=1
    break
  fi
  sleep 5
done
if [ "$PORT_OK" -ne 1 ]; then
  echo "[ES_027] ERREUR : timeout, Elasticsearch ne repond pas apres 5 minutes."
  exit 1
fi

# CORRECTIF 2026-08-14 (incident reel pre-demo) : un port qui repond ne
# prouve PAS que l'authentification fonctionne - curl sans -f considere
# un 401 comme une reponse "reussie". Ce controle passait donc "OK" un
# jour ou le mot de passe 'elastic' stocke etait desynchronise du mot
# de passe reellement actif dans le cluster (dossier de donnees
# Elasticsearch ayant survecu d'un deploiement anterieur sur la meme
# machine) - la vraie erreur n'apparaissait alors que 2 jobs plus tard,
# sur ES_028, sans lien evident avec sa cause reelle.
#
# Verification reelle desormais, via es_admin_curl qui resynchronise
# automatiquement le mot de passe si necessaire (voir
# jobs/lib/es_admin_curl.sh et reinitialiser_mdp_elastic.sh, seul point
# sanctionne pour toucher ce mot de passe) - la desynchronisation est
# ainsi detectee ET reparee ICI, tout de suite, plutot que de ressurgir
# plus loin dans la chaine.
source "$(dirname "$0")/lib/es_admin_curl.sh"
if ! es_admin_curl "https://127.0.0.1:${ES_PORT}/_cluster/health" -o /dev/null; then
  echo "[ES_027] ERREUR : Elasticsearch repond mais l'authentification admin echoue encore, meme apres tentative de resynchronisation automatique."
  exit 1
fi
echo "[ES_027] Verifie : authentification admin OK."
echo "[ES_027] OK."
exit 0
