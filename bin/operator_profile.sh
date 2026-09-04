#!/bin/bash
# operator_profile.sh - Vocabulaire operateur court, ajoute le 2026-08-14.
#
# PRINCIPE (observe en centre de production bancaire reel, pilotage
# multi-filiales) : un operateur ne tape jamais un chemin complet a la
# main. Il connait un petit nombre de NOMS COURTS, TOUJOURS LES MEMES
# d'un environnement a l'autre (VM1, VM2, futur client...) - seule la
# VALEUR change derriere le nom, jamais le nom lui-meme. Le cerveau
# humain retient un vocabulaire fixe, pas une variante par machine.
#
# A SOURCER (jamais a executer directement) dans le shell de l'operateur :
#   . /chemin/vers/wazuh_factory_3/operator_profile.sh
# Pour l'avoir a chaque connexion, une seule fois :
#   echo '. /chemin/vers/wazuh_factory_3/operator_profile.sh' >> ~/.bashrc
#
# ADAPTATION A LA NOMENCLATURE D'UN CLIENT : voir le bloc "VOCABULAIRE
# OPERATEUR" plus bas - c'est le SEUL endroit de tout le projet a modifier.
# Renommez une fonction (ex: escreds -> dbconn) sans toucher a aucun autre
# fichier. Si le client n'a pas deja de convention, proposez celle-ci
# telle quelle et documentez-la comme specifique a cette installation
# (voir GUIDE_EXPLOITATION.txt, section "Vocabulaire operateur").
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VARS_FILE="${VARS_FILE:-$HERE/vars.conf}"
source "$VARS_FILE"

# WEF_HOME : meme nom sur toute machine (VM1, VM2, futur client) - seule
# la valeur resolue change selon l'endroit ou ce fichier est source.
export WEF_HOME="$HERE"

# =====================================================================
# VOCABULAIRE OPERATEUR - seul bloc a adapter pour une nomenclature client
# =====================================================================

wenv(){
  echo "ROLE=${ROLE:-inconnu}  PROJET=${PROJECT_NAME:-inconnu}  MACHINE=$(hostname)  WEF_HOME=${WEF_HOME}"
}

escreds(){
  echo "--- Elasticsearch / Kibana ---"
  echo "URL Kibana    : https://127.0.0.1:${KB_PORT:-5601}"
  echo "URL ES        : https://127.0.0.1:${ES_PORT:-9200}"
  echo "Utilisateur   : elastic"
  local bootpw="${STATE_DIR}/es_bootstrap_password.secret"
  if [ -f "$bootpw" ]; then
    echo "Mot de passe  : $(cat "$bootpw")"
  else
    echo "Mot de passe  : non trouve (${bootpw} absent - ES_022 a-t-il tourne sur cette machine ?)"
  fi
  echo "--- Compte d'ingestion (Logstash/Beats), mode ${ES_AUTH_MODE:-token} ---"
  if [ "${ES_AUTH_MODE:-token}" = "password" ]; then
    local pwfile="${STATE_DIR}/factory_ingest_password.secret"
    [ -f "$pwfile" ] && echo "factory_ingest_user : $(cat "$pwfile")" || echo "Non arme (lancer ES_050B)."
  else
    local keyfile="${STATE_DIR}/factory_ingest_apikey.secret"
    [ -f "$keyfile" ] && echo "Cle API : $(cat "$keyfile")" || echo "Non armee (lancer ES_050)."
  fi
}

kburl(){
  echo "https://127.0.0.1:${KB_PORT:-5601}"
}

wstat(){
  "${WEF_HOME}/bin/monitoring.sh"
}

wlog(){
  "${WEF_HOME}/bin/view_history.sh" "$@"
}

# Ajoute le 2026-08-14, suite a un incident reel pre-demo (mot de passe
# 'elastic' desynchronise entre le cluster et state/es_bootstrap_password.secret).
# Seul point sanctionne pour reinitialiser ce mot de passe - voir
# reinitialiser_mdp_elastic.sh pour le detail (verification automatique
# incluse, jamais suppose que ca a fonctionne).
wpwreset(){
  "${WEF_HOME}/reinitialiser_mdp_elastic.sh"
}

# Ajoute le 2026-08-14, suite a une demande reelle de l'operateur (VM1) :
# marquer un job comme deja satisfait SANS l'executer, sans bloquer tout
# ce qui en depend (contrairement a un gel HELD). Voir
# bin/set_to_ok.sh pour le detail (raison obligatoire, confirmation,
# trace distincte MARQUE_FAIT jamais confondue avec une execution reelle).
wskip(){
  "${WEF_HOME}/bin/set_to_ok.sh" "$@"
}

# =====================================================================
# Fin du bloc adaptable.
# =====================================================================

echo "[operator_profile] Vocabulaire operateur charge (WEF_HOME=${WEF_HOME}, ROLE=${ROLE:-inconnu})."
echo "[operator_profile] Commandes disponibles : wenv, escreds, kburl, wstat, wlog <JOB_ID>, wpwreset, wskip <JOB_ID> \"<raison>\""
