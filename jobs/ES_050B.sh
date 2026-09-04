#!/bin/bash
# ES_050B - WEF_ES_RUN_APIFCTRYPWD  (job ajoute, pendant password de ES_050)
# VOLET MOT DE PASSE : cree le meme role factory_writer, mais rattache a
# un utilisateur nomme 'factory_ingest_user' avec un mot de passe genere,
# au lieu d'une cle API. Independant de ES_050 : l'un ou l'autre peut
# etre lance, ou les deux (aucun ne bloque l'autre).
#
# CORRECTIF 2026-08-14 (incident reel pre-demo, VM1) : POST
# _security/user/<nom> a une semantique UPSERT cote Elasticsearch - si
# l'utilisateur existe deja (ex: state/ reinitialise mais le cluster,
# lui, a survecu depuis un run precedent - meme situation racine que
# l'incident du mot de passe elastic plus haut), l'appel REUSSIT et met
# a jour le mot de passe vers GENPASS, mais la reponse contient
# "created":false (pas "true") pour signaler qu'il ne s'agissait pas
# d'une creation. Le job ne verifiait que "created":true et traitait a
# tort ce succes reel comme un echec (confirme en reel :
# {"created":false} dans le fichier de diagnostic, HTTP 200). Corrige :
# le code HTTP est desormais la source de verite (200 = l'appel a
# reussi, cree OU mis a jour), "created" n'est plus qu'informatif dans
# le message affiche.
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core, meme cause que sur
# ES_050 - voir son en-tete pour le detail complet du 403
# manage_index_templates) : le role "factory_writer" (partage avec
# ES_050) recoit le meme privilege "manage_index_templates". Contrairement
# a ES_050 (cle API, privileges figes a la creation, necessite une mise a
# jour explicite de la cle), un utilisateur du royaume natif rattache a un
# role PAR NOM (ce que fait ce job) recupere automatiquement tout
# changement futur du role des sa prochaine requete authentifiee - aucune
# logique d'auto-guerison supplementaire n'est donc necessaire ici, sauf
# une chose : l'ancien "if [ -f $SECRET_FILE ]; then exit 0" sautait aussi
# la declaration du role sur une machine deja armee, empechant tout
# redeploiement corrige de jamais propager le nouveau privilege. Corrige :
# le PUT du role est desormais TOUJOURS rejoue (idempotent, cout
# negligeable), seule la generation d'un nouveau mot de passe reste
# conditionnee a l'absence du secret local.
set -uo pipefail
source "$VARS_FILE"

SECRET_FILE="${STATE_DIR}/factory_ingest_password.secret"
BOOTSTRAP_PW_FILE="${STATE_DIR}/es_bootstrap_password.secret"
mkdir -p "${STATE_DIR}"

[ -f "$BOOTSTRAP_PW_FILE" ] || { echo "[ES_050B] ERREUR : mot de passe bootstrap introuvable (ES_022 doit avoir tourne)."; exit 1; }
BOOTSTRAP_PW="$(cat "$BOOTSTRAP_PW_FILE")"

echo "[ES_050B] Declaration du role factory_writer (idempotent, partage avec ES_050, rejoue a chaque passage)..."
curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
  -X PUT "https://127.0.0.1:${ES_PORT}/_security/role/factory_writer" \
  -H "Content-Type: application/json" -d '{
    "cluster": ["monitor","manage_index_templates"],
    "indices": [{"names": ["*"], "privileges": ["write","create_index","auto_configure"]}]
  }' > ${WORK_TMP_DIR}/es050b_role.json

if [ -f "$SECRET_FILE" ]; then
  echo "[ES_050B] Mot de passe d'ingestion deja arme (role rafraichi ci-dessus, suffisant pour un utilisateur rattache au role par nom), ignore."
  rm -f ${WORK_TMP_DIR}/es050b_role.json
  echo "[ES_050B] OK."
  exit 0
fi

GENPASS="$(openssl rand -base64 20)"
echo "[ES_050B] Creation de l'utilisateur factory_ingest_user..."
HTTP_CODE=$(curl -s --cacert "${PKI_DIR}/factory_ca.crt" -u "elastic:${BOOTSTRAP_PW}" \
  -X POST "https://127.0.0.1:${ES_PORT}/_security/user/factory_ingest_user" \
  -H "Content-Type: application/json" -d "{
    \"password\": \"${GENPASS}\",
    \"roles\": [\"factory_writer\"]
  }" -o ${WORK_TMP_DIR}/es050b_user.json -w "%{http_code}")

if [ "$HTTP_CODE" = "200" ]; then
  if grep -qE '"created" *: *true' ${WORK_TMP_DIR}/es050b_user.json; then
    echo "[ES_050B] Utilisateur factory_ingest_user cree."
  else
    echo "[ES_050B] Utilisateur factory_ingest_user existait deja (etat/secrets probablement reinitialises independamment du cluster) - mot de passe mis a jour vers la nouvelle valeur, ce qui est le comportement voulu (upsert)."
  fi
  echo -n "$GENPASS" > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
  rm -f ${WORK_TMP_DIR}/es050b_role.json ${WORK_TMP_DIR}/es050b_user.json
  echo "[ES_050B] OK (mot de passe pret dans ${SECRET_FILE})."
  exit 0
else
  echo "[ES_050B] ERREUR : creation/mise a jour utilisateur en echec (HTTP ${HTTP_CODE}), voir ${WORK_TMP_DIR}/es050b_user.json"
  exit 1
fi
