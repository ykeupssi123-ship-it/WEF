#!/bin/bash
# ES_022 - WEF_ES_BLD_KSTARMED
# Amorcage non-interactif du mot de passe bootstrap du compte 'elastic'.
# Injecte AVANT le premier demarrage (ES_026), directement dans le
# keystore local - ne passe pas par l'API puisque le service ne tourne
# pas encore. C'est le VOLET MOT DE PASSE : le VOLET TOKEN est arme
# plus tard par ES_050, une fois le cluster demarre et securise.
#
# LIMITE CONNUE (incident reel 2026-08-14) : bootstrap.password n'est lu
# par Elasticsearch qu'a la toute premiere creation de l'index de
# securite - inoperant si le dossier de donnees a survecu d'un
# deploiement anterieur sur la meme machine (le mot de passe REEL du
# cluster reste alors celui de ce premier bootstrap, quoi que ce job
# ecrive ici). Si ES_027/es_admin_curl detectent une desynchronisation,
# reinitialiser_mdp_elastic.sh est le SEUL point sanctionne pour la
# corriger (jamais ce job, jamais une commande manuelle isolee).
set -uo pipefail
source "$VARS_FILE"

SECRET_FILE="${STATE_DIR}/es_bootstrap_password.secret"
mkdir -p "${STATE_DIR}"

if grep -q "bootstrap.password" <(/usr/share/elasticsearch/bin/elasticsearch-keystore list 2>/dev/null) 2>/dev/null; then
  echo "[ES_022] bootstrap.password deja arme dans le keystore, ignore."
  echo "[ES_022] OK."
  exit 0
fi

if [ ! -f "$SECRET_FILE" ]; then
  openssl rand -base64 24 > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
fi

echo "[ES_022] Injection silencieuse du mot de passe bootstrap dans le keystore..."
ADD_OUT="$(/usr/share/elasticsearch/bin/elasticsearch-keystore add bootstrap.password --stdin --force < "$SECRET_FILE" 2>&1)"
ADD_CODE=$?

# CORRECTIF 2026-08-14 (audit systemique suite a l'incident LS_B025_ARMED) :
# l'appel ci-dessus n'etait jamais verifie - meme famille de bug qui a
# fait planter Logstash en boucle sur VM1 (voir README, incident 17).
#
# AFFINEMENT 2026-08-14 (meme jour, incident reel sur VM1) : le premier
# passage de ce correctif faisait echouer ce job DUREMENT des que la
# verification post-ecriture echouait, sans distinguer la cause. Sur ce
# VM, ES_008 (chown -R vers l'utilisateur elasticsearch sur tout
# /etc/elasticsearch, rejoue a chaque run) transfere la propriete d'un
# elasticsearch.keystore qui a survecu d'un deploiement anterieur - une
# fois root, "elasticsearch-keystore add --force" refuse alors
# volontairement d'ecrire (code de sortie 78, "will not overwrite
# keystore ... because this incurs changing the file owner"). C'est
# EXACTEMENT le scenario deja documente en tete de ce fichier
# ("LIMITE CONNUE") : bootstrap.password est de toute facon inoperant
# sur un cluster deja initialise, et es_admin_curl/reinitialiser_mdp_elastic.sh
# est deja le point sanctionne qui rattrape une desynchronisation reelle
# a l'usage - donc PAS bloquant pour la suite de la chaine. On distingue
# desormais ce cas precis (avertissement, on continue) de tout autre
# echec inattendu (erreur dure, jamais silencieuse).
if [ "$ADD_CODE" -ne 0 ] && echo "$ADD_OUT" | grep -q "changing the file owner"; then
  echo "[ES_022] AVERTISSEMENT : elasticsearch-keystore refuse d'ecrire (code $ADD_CODE, keystore deja proprietaire de l'utilisateur elasticsearch - dossier de donnees survivant d'un deploiement anterieur, voir LIMITE CONNUE en tete de ce fichier)."
  echo "[ES_022] Non bloquant : es_admin_curl/reinitialiser_mdp_elastic.sh rattraperont une eventuelle desynchronisation reelle au premier appel admin."
  echo "[ES_022] OK (avec avertissement)."
  exit 0
fi

if [ "$ADD_CODE" -ne 0 ] || ! grep -q "bootstrap.password" <(/usr/share/elasticsearch/bin/elasticsearch-keystore list 2>/dev/null) 2>/dev/null; then
  echo "[ES_022] ERREUR : echec inattendu de 'elasticsearch-keystore add' (code $ADD_CODE) ou verification post-ecriture echouee. Sortie :" >&2
  echo "$ADD_OUT" >&2
  exit 1
fi
echo "[ES_022] OK (confirme present dans 'elasticsearch-keystore list')."
exit 0
