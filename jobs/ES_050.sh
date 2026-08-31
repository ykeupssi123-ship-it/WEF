#!/bin/bash
# ES_050 - WEF_ES_RUN_APIFCTRYUSER
# VOLET TOKEN : armement du compte d'ingestion mutualise via une cle API
# (Authorization: ApiKey ...). Fournit le jeton d'authentification pour
# n'importe quel cable logiciel d'usine (Logstash, Filebeat, Metricbeat,
# scripts Python...). Alternative independante : ES_050B (mot de passe).
# Les deux peuvent coexister ; le choix se fait a l'usage via ES_AUTH_MODE.
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core) : la cle ne portait que
# le privilege cluster "monitor". Logstash (logstash-output-elasticsearch,
# manage_template => true par defaut) exige en plus "manage_index_templates"
# pour installer son template "ecs-logstash" a chaque demarrage du pipeline -
# sans lui, l'appel PUT _index_template rend un 403 security_exception,
# Logstash considere son bootstrap comme un echec et arrete tout le pipeline
# ("Failed to bootstrap. Pipeline main is going to shut down"), provoquant
# une boucle de redemarrage systemd sans rapport apparent avec un probleme
# de port/keystore (deja corriges par ailleurs). Ajoute "manage_index_templates"
# (privilege cluster precis, pas "manage" ni "all" - principe du moindre
# privilege deja applique partout ailleurs dans ce projet) au role
# "factory_writer" ET aux role_descriptors inline de la cle API (les deux
# doivent porter le privilege : les role_descriptors embarques dans une cle
# API definissent ses privileges effectifs independamment du role du meme
# nom, qui ne sert que de reference nominative).
#
# AUTO-GUERISON ajoutee dans le meme correctif : sur une machine ou ES_050
# a deja tourne AVANT ce correctif, l'ancien "if [ -f $SECRET_FILE ]; then
# exit 0" sautait purement et simplement la declaration du role a chaque
# nouveau passage - un simple redeploiement de l'archive corrigee n'aurait
# donc jamais repare une cle deja armee avec les anciens privileges,
# perpetuant le 403 indefiniment sans intervention manuelle. Desormais le
# role est toujours redeclare (PUT idempotent, cout negligeable), et si la
# cle existante n'a pas encore le nouveau privilege, elle est mise a jour
# EN PLACE via _security/api_key/_update (meme id, meme secret deja
# distribue aux consommateurs - aucune rotation, aucune interruption).
# Meme principe que es_admin_curl.sh/reinitialiser_mdp_elastic.sh : la
# reparation doit se produire toute seule au prochain passage du job.
#
# CORRECTIF 2026-08-19 (deuxieme et troisieme sessions, meme journee,
# decouverts en testant le deblocage manuel ci-dessus EN DIRECT sur
# wef-elk-core) : trois bugs reels dans la premiere version de cette
# auto-guerison, chacun revele par un echec reel successif de la MEME
# commande manuelle, jamais anticipes par les tests fonctionnels initiaux.
# (a) `_security/api_key/_update` exige la methode PUT, pas POST -
# confirme par le cluster lui-meme : "Incorrect HTTP method for uri
# [/_security/api_key/_update] and method [POST], allowed: [PUT]"
# (HTTP 405).
# (b) rechercher l'id de la cle par
# `GET _security/api_key?name=factory_ingest_key` n'est PAS fiable des
# qu'il existe plusieurs cles actives portant ce meme nom sur le cluster
# (constate en reel : la recherche par nom renvoyait un id different de
# celui effectivement embarque dans le secret local deja distribue a
# Logstash - `[ERROR] ... API key id [9XEvGKABZGkvlAXd0R6X]` dans les
# logs Logstash, contre un id different retourne par la recherche par
# nom). Une cle API cree par ES_050 n'a pas de contrainte d'unicite sur
# son nom cote Elasticsearch - si `STATE_DIR` a ete reinitialise
# independamment du cluster plus d'une fois (meme situation racine que
# les incidents 9/15/18 plus haut : etat local jete, cluster survivant),
# plusieurs cles "factory_ingest_key" valides coexistent, et rien ne
# garantit que la premiere renvoyee par l'API soit celle reellement en
# usage. Corrige a la racine : l'id de la cle a mettre a jour n'est plus
# JAMAIS cherche par nom - il est decode directement depuis le secret
# local deja arme (`base64 -d` sur le contenu de `$SECRET_FILE`, qui est
# toujours de la forme `id:cle_secrete` avant encodage - le prefixe avant
# le premier `:` EST l'id exact utilise par Logstash, par construction,
# puisque c'est litteralement le meme fichier que celui lu par
# `LS_B025_ARMED.sh` pour armer `factory_ingest_token`). Aucune ambiguite
# possible.
# (c) l'id de la cle se passe dans l'URL (`/_security/api_key/_update/<id>`),
# PAS dans le corps JSON - confirme en reel par
# `x_content_parse_exception: [update_api_key_request_payload] unknown
# field [id]` (HTTP 400) des la premiere commande PUT correctement
# methodee mais avec `"id"` encore present dans le body (heritage de la
# premiere version de ce correctif). Corrige : `"id"` retire du corps
# JSON, l'id figure desormais uniquement dans le chemin de l'URL.
# Reteste fonctionnellement avec un `curl` factice qui echoue
# volontairement sur toute methode POST vers `_update`, sur tout `id`
# encore present dans le body, ou sur toute URL sans l'id en chemin (pour
# prouver que seule la forme exacte `PUT .../_update/<id>` sans `id` dans
# le body est desormais utilisee) et un scenario a deux cles actives de
# meme nom (pour prouver que l'id decode du secret local est bien celui
# choisi, jamais celui qu'une recherche par nom aurait pu renvoyer).
set -uo pipefail
source "$VARS_FILE"

SECRET_FILE="${STATE_DIR}/factory_ingest_apikey.secret"
BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
mkdir -p "${STATE_DIR}"

[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[ES_050] ERREUR : mot de passe bootstrap introuvable (ES_022 doit avoir tourne)."; exit 1; }
BOOTSTRAP_PW="$(cat "$BOOTSTRAP_PW_FILE")"

ROLE_JSON='{
    "cluster": ["monitor","manage_index_templates"],
    "indices": [{"names": ["*"], "privileges": ["write","create_index","auto_configure"]}]
  }'

echo "[ES_050] Declaration du role factory_writer (idempotent, rejoue a chaque passage pour propager tout correctif de privilege futur)..."
curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
  -X PUT "https://127.0.0.1:${ES_PORT}/_security/role/factory_writer" \
  -H "Content-Type: application/json" -d "${ROLE_JSON}" > ${WORK_TMP_DIR}/es050_role.json

if [ -f "$SECRET_FILE" ]; then
  echo "[ES_050] Cle API d'ingestion deja armee - verification que ses privileges sont a jour..."
  # L'id de la cle EST le prefixe avant le premier ':' du secret decode
  # (base64("id:cle_secrete")) - jamais une recherche par nom, voir
  # CORRECTIF ci-dessus (peut renvoyer une AUTRE cle active du meme nom).
  KEY_ID="$(printf '%s' "$(cat "$SECRET_FILE")" | base64 -d 2>/dev/null | cut -d: -f1)"

  if [ -z "$KEY_ID" ]; then
    echo "[ES_050] ATTENTION : impossible de decoder l'id de la cle depuis ${SECRET_FILE} (fichier vide ou corrompu) - suppression pour forcer une regeneration propre ci-dessous."
    rm -f "$SECRET_FILE"
  else
    KEY_STATE="$(curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
      "https://127.0.0.1:${ES_PORT}/_security/api_key?id=${KEY_ID}" \
      | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    k = d['api_keys'][0]
    if k.get('invalidated'):
        print('invalidee')
    else:
        cl = k.get('role_descriptors', {}).get('factory_writer', {}).get('cluster', [])
        print('privilege_ok' if 'manage_index_templates' in cl else 'privilege_manquant')
except Exception:
    print('introuvable')
")"

    case "$KEY_STATE" in
      privilege_ok)
        echo "[ES_050] Privileges deja a jour, rien a faire."
        ;;
      privilege_manquant)
        echo "[ES_050] Privilege 'manage_index_templates' manquant sur la cle existante (id=${KEY_ID}) - mise a jour en place, meme secret deja distribue, aucune rotation..."
        # Endpoint officiel confirme par la documentation Elastic (pas de
        # tatonnement supplementaire) : "Bulk update API keys",
        # POST /_security/api_key/_bulk_update, body { "ids": [...],
        # "role_descriptors": {...} } - PAS PUT /_security/api_key/_update
        # (reserve a l'auto-mise-a-jour d'une cle authentifiee comme
        # elle-meme, sans id explicite) ni /_update/<id> (route
        # inexistante, "no handler found" confirme en reel). Un seul id
        # dans le tableau "ids" ici, mais l'API accepte une liste.
        curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
          -X POST "https://127.0.0.1:${ES_PORT}/_security/api_key/_bulk_update" \
          -H "Content-Type: application/json" \
          -d "{\"ids\": [\"${KEY_ID}\"], \"role_descriptors\": {\"factory_writer\": ${ROLE_JSON}}}" \
          > ${WORK_TMP_DIR}/es050_keyupdate.json
        # Reponse attendue : {"updated":["<id>"],"noops":[],"errors":{...}}.
        # Un simple grep sur l'id ne suffit pas (il peut aussi apparaitre
        # dans un bloc d'erreur) - parse reellement la structure pour ne
        # jamais confondre un echec avec un succes.
        BULK_OK="$(python3 -c "
import json, sys
try:
    d = json.load(open('${WORK_TMP_DIR}/es050_keyupdate.json'))
    ok = '${KEY_ID}' in d.get('updated', []) or '${KEY_ID}' in d.get('noops', [])
    print('yes' if ok else 'no')
except Exception:
    print('no')
")"
        [ "$BULK_OK" = "yes" ] \
          && echo "[ES_050] Cle mise a jour avec succes (auto-guerison)." \
          || { echo "[ES_050] ERREUR : la mise a jour de la cle a echoue, voir ${WORK_TMP_DIR}/es050_keyupdate.json"; exit 1; }
        ;;
      *)
        echo "[ES_050] ATTENTION : la cle referencee par ${SECRET_FILE} (id=${KEY_ID}) n'est plus active sur le cluster (etat local desynchronise, meme famille que l'incident du mot de passe elastic) - suppression du fichier local pour forcer une regeneration propre ci-dessous."
        rm -f "$SECRET_FILE"
        ;;
    esac
  fi
  rm -f ${WORK_TMP_DIR}/es050_role.json ${WORK_TMP_DIR}/es050_keyupdate.json
fi

if [ ! -f "$SECRET_FILE" ]; then
  echo "[ES_050] Generation de la cle API d'ingestion..."
  curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
    -X POST "https://127.0.0.1:${ES_PORT}/_security/api_key" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"factory_ingest_key\", \"role_descriptors\": {\"factory_writer\": ${ROLE_JSON}}}" \
    > ${WORK_TMP_DIR}/es050_apikey.json

  python3 -c "import json,sys; d=json.load(open('${WORK_TMP_DIR}/es050_apikey.json')); sys.stdout.write(d['encoded'])" > "$SECRET_FILE" \
    || { echo "[ES_050] ERREUR : reponse API inattendue, voir ${WORK_TMP_DIR}/es050_apikey.json"; exit 1; }
  chmod 600 "$SECRET_FILE"
  rm -f ${WORK_TMP_DIR}/es050_role.json ${WORK_TMP_DIR}/es050_apikey.json
fi

echo "[ES_050] OK (token pret dans ${SECRET_FILE})."
exit 0
