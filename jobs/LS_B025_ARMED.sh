#!/bin/bash
# LS_B025_ARMED - WEF_LS_BLD_KSTSECRET
# Injection du secret d'ingestion dans le keystore LOCAL de Logstash,
# choisi selon ES_AUTH_MODE (meme variable que cote Elasticsearch, voir
# es_auth.sh). Lit le secret depuis state/ (arme par ES_050 ou ES_050B),
# jamais de valeur en dur.
#
# CORRECTIF 2026-08-14 (incident reel pre-demo, VM1) : ce job se
# declarait OK sans jamais verifier que "logstash-keystore create"/"add"
# avaient reellement reussi - meme famille de bug que ES_052 avant son
# propre correctif (faire confiance a un code de sortie jamais lu).
# Consequence reelle observee : le job a rendu OK, mais
# /etc/logstash/logstash.keystore n'existait meme pas sur le disque -
# Logstash (LS_026_FINAL demarre "avec succes" selon systemd, mais
# LS_027 le detecte correctement en aval) est parti en boucle de
# redemarrage (13+ tentatives) avec l'erreur "Cannot evaluate
# ${FACTORY_INGEST_TOKEN}. Replacement variable ... is not defined in a
# Logstash secret store". Corrige : verification reelle en relisant
# "logstash-keystore list" apres chaque ecriture et en confirmant que la
# cle attendue y figure bien - jamais un simple code de sortie non lu.
set -uo pipefail
source "$VARS_FILE"

KEYSTORE_BIN="/usr/share/logstash/bin/logstash-keystore"

# CORRECTIF 2026-08-18 (incident reel VM1, wef-elk-core) : sans
# --path.settings explicite, "logstash-keystore" ne trouve pas
# logstash.yml (ni dans $LS_HOME/config, ni dans /etc/logstash - warning
# "Continuing using the defaults" a chaque appel) et retombe sur son
# chemin par defaut $LS_HOME/config/logstash.keystore
# (/usr/share/logstash/config/logstash.keystore) - un fichier
# COMPLETEMENT DIFFERENT de /etc/logstash/logstash.keystore que ce job
# croit etre le bon (verifie plus bas). Consequence reelle observee :
# le keystore existait deja sur disque a /etc/logstash/logstash.keystore
# (cree lors d'un run precedent), le bloc de creation ci-dessous a donc
# ete saute a raison, mais "add" a ensuite ecrit (ou tente d'ecrire)
# dans le mauvais fichier par defaut, et le diagnostic "list" appele en
# cas d'echec a conclu "Can not find Logstash keystore at
# /usr/share/logstash/config/logstash.keystore" - preuve que create/add/
# list ne visaient pas le meme fichier que celui atteste par le test
# d'existence. Corrige : chaque invocation passe desormais
# explicitement --path.settings /etc/logstash, pour garantir que
# create/add/list operent tous sur EXACTEMENT le meme fichier que celui
# verifie par [ -f /etc/logstash/logstash.keystore ].
KEYSTORE_PATH_ARGS=(--path.settings /etc/logstash)

# CORRECTIF 2026-08-18 (2e incident reel wef-elk-core, apres le
# correctif --path.settings ci-dessus) : "logstash-keystore add
# FACTORY_INGEST_TOKEN" a repondu "FACTORY_INGEST_TOKEN already exists.
# Overwrite ? [y/N]" (prompt interactif, jamais de reponse disponible
# sur stdin puisqu'il ne contient que le secret -> EOF -> ECHEC), alors
# que "logstash-keystore list" n'affichait a ce moment QUE
# "factory_ingest_token" en MINUSCULES. Preuve directe que le coffre de
# Logstash normalise les noms de cle en minuscules en interne (ou du
# moins les compare de facon insensible a la casse pour detecter un
# doublon), quelle que soit la casse utilisee pour les y ecrire. Notre
# propre keystore_has() etait aveugle a cette normalisation
# (comparaison stricte grep -qx : "FACTORY_INGEST_TOKEN" ne matche
# jamais "factory_ingest_token") - keystore_has() rendait donc
# systematiquement "absent" pour une cle en realite deja presente,
# keystore_set() sautait le "remove" protecteur, et "add" tombait en
# direct sur le prompt interactif du CLI. Corrige en deux temps : (1)
# LS_024.sh ecrit desormais ${factory_ingest_token}/
# ${factory_ingest_user}/${factory_ingest_password} en MINUSCULES dans
# 30-outputs.conf (meme casse que ce que le coffre affiche reellement -
# fini de parier sur un comportement de casse non documente) ; (2) les
# cles armees ci-dessous sont elles aussi en minuscules, memes noms des
# deux cotes ; (3) keystore_has() reste en plus insensible a la casse
# (grep -qix) en filet de securite, au cas ou une cle residuelle d'un
# ancien run trainerait encore sous une autre casse.
keystore_has(){
  "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" list 2>/dev/null | grep -qix "$1"
}

# CORRECTIF 2026-08-18 (meme incident reel) : le deuxieme echec observe
# sur wef-elk-core, independant du probleme de chemin ci-dessus -
# "ERROR: Unrecognized option '--force' for command 'add'". Cette
# version de logstash-keystore installee n'accepte PAS --force sur
# "add" (contrairement a ce que d'autres versions/outils - Beats compris
# - acceptent). Plutot que parier sur la presence de ce flag (fragile,
# differe selon la version du paquet logstash installee), on rend
# l'ajout idempotent nous-memes : si la cle existe deja, on la retire
# d'abord ("remove", qui n'a pas besoin de confirmation), puis on
# l'ajoute toujours a l'etat "cle absente" - jamais de prompt, jamais de
# flag de version incertaine.
keystore_set(){
  local key="$1" value_stdin_cmd="$2"
  if keystore_has "$key"; then
    "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" remove "$key" >/dev/null 2>&1 || true
  fi
  eval "$value_stdin_cmd" | "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" add "$key" --stdin
}

if [ ! -f /etc/logstash/logstash.keystore ]; then
  echo "[LS_B025_ARMED] Creation du keystore Logstash..."
  # CORRECTIF 2026-08-14 (incident reel VM1, meme jour que le correctif ci-dessus) :
  # contrairement a elasticsearch-keystore/kibana-keystore/filebeat keystore/metricbeat
  # keystore (aucun des 4 ne le fait, voir ES_021.sh/KB_017.sh/FB_009.sh/MB_009.sh),
  # "logstash-keystore create" invite INTERACTIVEMENT sur stdin des que
  # LOGSTASH_KEYSTORE_PASS n'est pas positionnee : "Continue without password
  # protection on the keystore? [y/N]". Cette variable n'est definie nulle part dans
  # le projet (design volontairement sans mot de passe de keystore, comme le
  # confirment les appels "add"/"list" plus bas qui n'en positionnent jamais). Sans
  # reponse disponible sur stdin, l'outil part en EOF (java.util.Scanner.throwFor) et
  # le keystore n'est jamais cree - vu en reel : le job echouait proprement (grace a
  # la verification d'existence ci-dessous, pas de faux OK) mais ne pouvait jamais
  # reussir en execution non-interactive. On repond "y" explicitement au prompt au
  # lieu de laisser l'orchestrateur se heurter a une question a laquelle personne ne
  # repond.
  echo y | "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" create
  [ -f /etc/logstash/logstash.keystore ] || {
    echo "[LS_B025_ARMED] ERREUR : /etc/logstash/logstash.keystore n'existe toujours pas apres 'logstash-keystore create'. Rien n'a ete arme." >&2
    exit 1
  }
fi

if [ "${ES_AUTH_MODE:-token}" = "password" ]; then
  SECRET_FILE="${STATE_DIR}/factory_ingest_password.secret"
  [ -f "$SECRET_FILE" ] || { echo "[LS_B025_ARMED] ERREUR : $SECRET_FILE absent (ES_050B doit avoir tourne sur ELK_HOST)."; exit 1; }
  echo "[LS_B025_ARMED] Armement du keystore Logstash (mode password)..."
  keystore_set factory_ingest_user 'echo factory_ingest_user'
  keystore_set factory_ingest_password "cat '${SECRET_FILE}'"
  if ! keystore_has factory_ingest_user || ! keystore_has factory_ingest_password; then
    echo "[LS_B025_ARMED] ERREUR : verification post-ecriture echouee - factory_ingest_user et/ou factory_ingest_password absents de 'logstash-keystore list' apres l'ajout." >&2
    "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" list 2>&1 >&2 || true
    exit 1
  fi
else
  SECRET_FILE="${STATE_DIR}/factory_ingest_apikey.secret"
  [ -f "$SECRET_FILE" ] || { echo "[LS_B025_ARMED] ERREUR : $SECRET_FILE absent (ES_050 doit avoir tourne sur ELK_HOST)."; exit 1; }
  echo "[LS_B025_ARMED] Armement du keystore Logstash (mode token)..."
  keystore_set factory_ingest_token "cat '${SECRET_FILE}'"
  if ! keystore_has factory_ingest_token; then
    echo "[LS_B025_ARMED] ERREUR : verification post-ecriture echouee - factory_ingest_token absent de 'logstash-keystore list' apres l'ajout." >&2
    "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" list 2>&1 >&2 || true
    exit 1
  fi
fi

# CORRECTIF 2026-08-18 (reponse definitive a la question "est-ce que
# Logstash resout vraiment ${factory_ingest_token} ?") : plutot qu'une
# verification manuelle ponctuelle et non reproductible, on transforme
# la question en garde-fou permanent. LS_024 (prerequis LS_OUTPUT_OK de
# ce job, donc deja execute) a deja ecrit
# /etc/logstash/conf.d/30-outputs.conf avec les references litterales
# ${factory_ingest_token} ou
# ${factory_ingest_user}/${factory_ingest_password} (minuscules depuis
# le correctif de casse ci-dessus - voir LS_024.sh). On relit ce
# fichier, on extrait chaque token ${...} qu'il contient, et on verifie
# - avec la MEME fonction keystore_has() (desormais insensible a la
# casse, en filet de securite supplementaire) que celle utilisee
# ci-dessus pour armer - que chacun existe bel et bien dans
# 'logstash-keystore list'. Si demain un nom de variable derive entre
# LS_024 et LS_B025_ARMED (faute de frappe, refactor, copier-coller
# imparfait), ce job echoue ICI, avant meme que Logstash ne demarre -
# au lieu de le decouvrir trois jobs plus tard via un crash loop.
OUT_CONF="/etc/logstash/conf.d/30-outputs.conf"
if [ -f "$OUT_CONF" ]; then
  echo "[LS_B025_ARMED] Verification croisee : tokens \${...} de ${OUT_CONF} vs cles du keystore..."
  TOKENS=$(grep -oE '\$\{[A-Za-z0-9_]+\}' "$OUT_CONF" | sed -E 's/\$\{(.*)\}/\1/' | sort -u)
  if [ -z "$TOKENS" ]; then
    echo "[LS_B025_ARMED] AVERTISSEMENT : aucun token \${...} trouve dans ${OUT_CONF} (sortie ES peut-etre desactivee - voir LS_OUTPUT_ES_ENABLED)."
  else
    MISSING=0
    while IFS= read -r tok; do
      if keystore_has "$tok"; then
        echo "[LS_B025_ARMED]   OK  \${${tok}} -> present dans le keystore (casse exacte)."
      else
        echo "[LS_B025_ARMED]   MANQUANT  \${${tok}} reference dans ${OUT_CONF} mais absent de 'logstash-keystore list' (nom ou casse different)." >&2
        MISSING=1
      fi
    done <<< "$TOKENS"
    if [ "$MISSING" -eq 1 ]; then
      echo "[LS_B025_ARMED] ERREUR : au moins un token reference par la pipeline de sortie ne correspond a aucune cle du keystore. Logstash echouerait au demarrage avec 'Cannot evaluate \${...}'. Corrige avant meme d'essayer de demarrer le service." >&2
      "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" list 2>&1 >&2 || true
      exit 1
    fi
  fi
else
  echo "[LS_B025_ARMED] AVERTISSEMENT : ${OUT_CONF} introuvable (LS_024 a-t-il bien tourne avant ce job ?) - verification croisee ignoree."
fi

echo "[LS_B025_ARMED] OK (confirme present dans 'logstash-keystore list')."
exit 0
