#!/bin/bash
# KB_023 - WEF_KB_BLD_CABLENMNL - Raccordement de Kibana a Elasticsearch
#
# CORRECTIF 2026-08-19 (audit systemique declenche sur wef-elk-core juste
# apres l'incident KB_013/KB_015, meme journee : Kibana capable de demarrer
# jusqu'au bout pour la toute premiere fois a revele "Kibana has not been
# configured" / assistant d'enrolement interactif (code affiche dans les
# logs), alors que ce job est cense armer sa connexion a Elasticsearch -
# aucun job KB_0xx n'echouait pourtant : silencieux, la pire categorie
# (meme famille que l'incident 107/echec silencieux documente plus haut).
# TROIS ecarts trouves, chacun verifie contre la documentation officielle
# Elastic avant correction (jamais suppose) :
#
# (1) elasticsearch.hosts / elasticsearch.ssl.certificateAuthorities
# n'etaient ecrits par AUCUN job de la suite KB_0xx (verifie par grep
# exhaustif sur jobs/KB_*.sh). Kibana (Node.js) ne devine pas l'adresse de
# son Elasticsearch ni ne fait confiance automatiquement au magasin de
# certificats systeme (update-ca-trust, deja fait cote OS par PKI_009) -
# la configuration cote Kibana est TOUJOURS manuelle, meme quand la CA est
# deja approuvee par le systeme. Sans elasticsearch.hosts explicite en
# https://, Kibana part sur son defaut (http://localhost:9200) qui ne peut
# pas dialoguer avec un Elasticsearch qui n'ecoute qu'en TLS - d'ou
# l'assistant d'enrolement qui s'affiche indefiniment (Kibana attend
# qu'un humain le configure a la main via un navigateur, ce qu'aucune
# machine de la chaine ne peut faire). KB_014 copie deja factory_ca.crt
# dans /etc/kibana/certs/ (local_pki_copy) pour le certificat SERVEUR
# (server.ssl.*, trafic entrant navigateur->Kibana) - le meme fichier
# est reutilise ici pour le trafic SORTANT Kibana->Elasticsearch
# (elasticsearch.ssl.certificateAuthorities), aucune copie
# supplementaire necessaire.
#
# (2) et (3) ce job armait elasticsearch.serviceAccountToken (mode token)
# ou elasticsearch.username/password (mode password) avec le MEME secret
# que celui utilise par Logstash pour ECRIRE des donnees
# (factory_ingest_apikey.secret / factory_ingest_user, crees par
# ES_050/ES_050B avec le role "factory_writer" : cluster
# monitor+manage_index_templates, indices write/create_index/auto_configure
# sur * - taille pour l'ingestion, pas pour les besoins internes de Kibana).
# (2) mode token : elasticsearch.serviceAccountToken exige un VRAI jeton de
# compte de service (cree via POST
# _security/service/elastic/kibana/credential/token/<nom>, confirme par la
# doc officielle Elastic), pas une cle API generique - format et royaume
# d'authentification differents cote Elasticsearch, une cle API glissee ici
# est rejetee.
# (3) mode password : "factory_writer" ne couvre ni la creation/lecture/
# suppression de .kibana*/.reporting-*/etc. ni les privileges cluster
# internes dont Kibana a besoin. Le royaume natif dispose justement d'un
# role RESERVE concu pour cet usage exact : "kibana_system" (confirme par
# la doc officielle, assignable tel quel a un utilisateur natif).
#
# Corrige : ce job cree desormais SES PROPRES identifiants dedies,
# entierement independants de ceux de Logstash - factory_kibana_token (vrai
# jeton de compte de service elastic/kibana, immuable : DELETE puis
# recreation en cas de secret local perdu, meme logique d'auto-guerison
# "etat local jete, cluster survivant" que ES_050/ES_050B) en mode token,
# ou factory_kibana_user rattache au role reserve kibana_system (upsert via
# POST _security/user/, meme idiome que ES_050B) en mode password. Les
# secrets d'ingestion (ES_050/ES_050B) ne sont plus lus ici du tout.
#
# CORRIGE LE 2026-08-30 (incident reel wef-elk-core, decouvert en
# verifiant Kibana APRES le premier passage complet de la chaine jusqu'a
# ES_063) : "grep -q ... || echo ..." (ligne d'origine ci-dessous) n'ecrit
# elasticsearch.hosts QUE si la ligne est TOTALEMENT absente - lors du
# changement de ES_PORT (9200 -> 9202, voir vars.conf) survenu apres le
# tout premier passage de ce job, la ligne EXISTAIT DEJA (avec l'ancien
# port 9200, qui se trouve etre aussi le port de wazuh-indexer) et n'a
# donc plus jamais ete corrigee - Kibana continuait de dialoguer en
# silence avec wazuh-indexer au lieu d'Elasticsearch, provoquant des
# erreurs reelles et continues cote Kibana ("Content-Type header
# ... compatible-with=8 ... not supported" - wazuh-indexer ne repond pas
# comme une vraie Elasticsearch 8.x - et "Authentication finally failed"
# - les identifiants dedies crees plus bas dans CE MEME job n'existent
# que cote Elasticsearch, jamais cote wazuh-indexer). Exactement la
# meme famille de bug, memes symptomes, que celui deja trouve et corrige
# dans LS_024.sh (sortie Logstash) le meme jour - meme remede applique
# ici : les deux lignes sont desormais retirees puis reecrites a CHAQUE
# passage (jamais de confiance dans un residu, meme repere par la bonne
# cle), et l'immutabilite posee par KB_028_FINAL.sh (plus tard dans la
# chaine) est levee avant d'ecrire si necessaire - KB_028_FINAL la
# reposera de toute facon au prochain passage complet de la chaine (meme
# raisonnement que LS_024/LS_036_FINAL).
set -uo pipefail
source "$VARS_FILE"

# CORRECTIF 2026-09-02 (incident reel, deploiement VM ELK_HOST Oracle
# Linux 8) : ce job a besoin de contacter Elasticsearch (creation du
# jeton de compte de service / de l'utilisateur dedie, plus bas) mais le
# blocage reseau pose par KB_021 (crash-test WEF_KB_RUN_ISLTDB, "iptables
# -A OUTPUT -p tcp --dport ${ES_PORT} -j DROP") n'etait leve que dans
# KB_024, qui s'execute APRES ce job - KB_023 tentait donc de joindre
# Elasticsearch alors que la regle DROP posee par KB_021 etait encore
# active. Symptome reel observe : la commande curl de creation du jeton
# restait bloquee puis expirait ("Failed to connect ... Connexion
# terminee par expiration du delai d'attente" - signature typique d'un
# DROP silencieux, a distinguer d'un REJECT qui aurait echoue
# immediatement), produisant un fichier reponse VIDE, que le python3 -c
# suivant ne pouvait alors que rejeter avec "json.decoder.JSONDecodeError:
# Expecting value: line 1 column 1 (char 0)" - message qui, pris seul,
# ne montrait pas la vraie cause reseau. Corrige : la levee de
# l'isolement (deja faite, de facon idempotente, par KB_024 juste apres)
# est desormais AUSSI faite ici, en tout debut de job, avant toute
# tentative de contact avec Elasticsearch - sans effet si elle a deja
# ete levee ailleurs (regle absente -> "|| true"). KB_024 la relevera de
# toute facon sans risque, exactement comme avant.
echo "[KB_023] Levee prealable du blocage reseau pose par KB_021 (isolement crash-test) - necessaire avant tout contact avec Elasticsearch..."
iptables -D OUTPUT -p tcp --dport ${ES_PORT} -j DROP || true

BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
mkdir -p "${STATE_DIR}"

[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[KB_023] ERREUR : mot de passe bootstrap introuvable (ES_022 doit avoir tourne)."; exit 1; }
BOOTSTRAP_PW="$(cat "$BOOTSTRAP_PW_FILE")"

keystore_has(){
  /usr/share/kibana/bin/kibana-keystore list 2>/dev/null | grep -qx "$1"
}

echo "[KB_023] Declaration de la connexion Elasticsearch dans kibana.yml (elasticsearch.hosts / CA)..."
if lsattr /etc/kibana/kibana.yml 2>/dev/null | grep -q '^....i'; then
  chattr -i /etc/kibana/kibana.yml
fi
sed -i '/^elasticsearch\.hosts:/d; /^elasticsearch\.ssl\.certificateAuthorities:/d' /etc/kibana/kibana.yml
{
  echo "elasticsearch.hosts: [\"https://127.0.0.1:${ES_PORT}\"]"
  echo "elasticsearch.ssl.certificateAuthorities: [\"/etc/kibana/certs/factory_ca.crt\"]"
} >> /etc/kibana/kibana.yml
if ! grep -qF "127.0.0.1:${ES_PORT}" /etc/kibana/kibana.yml 2>/dev/null; then
  echo "[KB_023] ERREUR : elasticsearch.hosts ne porte pas le port ES_PORT attendu (${ES_PORT}) apres ecriture (fichier toujours immuable ?)." >&2
  lsattr /etc/kibana/kibana.yml >&2 2>/dev/null || true
  exit 1
fi

if [ "${ES_AUTH_MODE:-token}" = "password" ]; then
  SECRET_FILE="${STATE_DIR}/factory_kibana_password.secret"

  if [ ! -f "$SECRET_FILE" ]; then
    GENPASS="$(openssl rand -base64 20)"
    echo "[KB_023] Creation de l'utilisateur dedie factory_kibana_user (role reserve kibana_system, distinct de factory_ingest_user)..."
    HTTP_CODE=$(curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
      -X POST "https://127.0.0.1:${ES_PORT}/_security/user/factory_kibana_user" \
      -H "Content-Type: application/json" -d "{
        \"password\": \"${GENPASS}\",
        \"roles\": [\"kibana_system\"]
      }" -o ${WORK_TMP_DIR}/kb023_user.json -w "%{http_code}")

    if [ "$HTTP_CODE" != "200" ]; then
      echo "[KB_023] ERREUR : creation/mise a jour de factory_kibana_user en echec (HTTP ${HTTP_CODE}), voir ${WORK_TMP_DIR}/kb023_user.json"
      exit 1
    fi
    echo -n "$GENPASS" > "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
    rm -f ${WORK_TMP_DIR}/kb023_user.json
  else
    echo "[KB_023] factory_kibana_user deja arme localement, mot de passe reutilise tel quel (upsert deja rejoue au premier armement, role reserve immuable par nature)."
  fi

  echo "[KB_023] Armement du keystore Kibana (mode password, identifiants dedies)..."
  echo "factory_kibana_user" | /usr/share/kibana/bin/kibana-keystore add elasticsearch.username --stdin --force
  cat "$SECRET_FILE" | /usr/share/kibana/bin/kibana-keystore add elasticsearch.password --stdin --force
  if ! keystore_has elasticsearch.username || ! keystore_has elasticsearch.password; then
    echo "[KB_023] ERREUR : verification post-ecriture echouee - elasticsearch.username et/ou elasticsearch.password absents de 'kibana-keystore list' apres l'ajout." >&2
    exit 1
  fi
else
  SECRET_FILE="${STATE_DIR}/factory_kibana_service_token.secret"

  if [ ! -f "$SECRET_FILE" ]; then
    echo "[KB_023] Creation du jeton de compte de service dedie elastic/kibana (factory_kibana_token)..."
    # Idempotence : un jeton de compte de service est immuable une fois
    # cree (pas de mise a jour possible, contrairement a une cle API) - si
    # un jeton du meme nom existe deja cote cluster (etat local perdu
    # independamment du cluster, meme situation racine que les incidents
    # 9/15/18/ES_050 plus haut), on le supprime d'abord (DELETE idempotent,
    # 404 ignore) pour repartir sur une valeur fraiche plutot que d'echouer
    # sur un 409 Conflict.
    curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
      -X DELETE "https://127.0.0.1:${ES_PORT}/_security/service/elastic/kibana/credential/token/factory_kibana_token" \
      > /dev/null

    curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
      -X POST "https://127.0.0.1:${ES_PORT}/_security/service/elastic/kibana/credential/token/factory_kibana_token" \
      > ${WORK_TMP_DIR}/kb023_token.json

    python3 -c "import json,sys; d=json.load(open('${WORK_TMP_DIR}/kb023_token.json')); sys.stdout.write(d['token']['value'])" > "$SECRET_FILE" \
      || { echo "[KB_023] ERREUR : reponse API inattendue lors de la creation du jeton, voir ${WORK_TMP_DIR}/kb023_token.json"; exit 1; }
    chmod 600 "$SECRET_FILE"
    rm -f ${WORK_TMP_DIR}/kb023_token.json
  else
    echo "[KB_023] Jeton de compte de service deja arme localement, reutilise tel quel (immuable par nature, jamais de mise a jour en place possible)."
  fi

  echo "[KB_023] Armement du keystore Kibana (mode token, jeton de compte de service dedie)..."
  cat "$SECRET_FILE" | /usr/share/kibana/bin/kibana-keystore add elasticsearch.serviceAccountToken --stdin --force
  if ! keystore_has elasticsearch.serviceAccountToken; then
    echo "[KB_023] ERREUR : verification post-ecriture echouee - elasticsearch.serviceAccountToken absent de 'kibana-keystore list' apres l'ajout." >&2
    exit 1
  fi
fi
echo "[KB_023] OK (connexion kibana.yml + identifiants dedies confirmes)."
exit 0
