#!/bin/bash
# LS_024 - WEF_LS_BLD_OUTAGN - Cablage des sorties Logstash (ES / fichier / S3)
#
# Genere /etc/logstash/conf.d/30-outputs.conf EN ENTIER a chaque execution,
# a partir de trois interrupteurs independants dans vars.conf :
#   LS_OUTPUT_ES_ENABLED    -> vers Elasticsearch local (mode token ou
#                               mot de passe, choisi par ES_AUTH_MODE,
#                               arme ensuite par LS_B025_ARMED)
#   LS_OUTPUT_FILE_ENABLED  -> vers un fichier texte local (JSON lines)
#   LS_OUTPUT_S3_ENABLED    -> vers l'object storage OVH (S3-compatible)
#
# IMPORTANT (proprete) : le fichier de sortie est toujours reconstruit
# depuis zero (jamais de >> sur ce fichier). Rejouer ce job apres avoir
# change un interrupteur ne laisse JAMAIS de bloc fantome d'une
# configuration precedente - le fichier reflete uniquement l'etat actuel
# de vars.conf.
#
# CORRECTIF 2026-08-18 (incident reel wef-elk-core, decouverte en
# direct) : les references ${...} ci-dessous sont desormais en
# minuscules (factory_ingest_token / factory_ingest_user /
# factory_ingest_password), alors qu'elles etaient en MAJUSCULES
# jusqu'ici. Preuve reelle observee lors de l'armement du keystore
# (LS_B025_ARMED) : "logstash-keystore add FACTORY_INGEST_TOKEN" a
# repondu "FACTORY_INGEST_TOKEN already exists. Overwrite ? [y/N]" -
# alors que "logstash-keystore list" n'affichait QUE
# "factory_ingest_token" (minuscules). Le coffre de Logstash normalise
# donc les noms de cle en minuscules en interne, quelle que soit la
# casse utilisee pour les y ecrire - un comportement different de ce
# qu'on avait suppose (et code en dur) dans le correctif "casse exacte"
# du 2026-08-18 plus tot dans la journee (verification croisee de
# LS_B025_ARMED, qui restait aveugle a cette normalisation). Plutot que
# de parier sur un comportement de casse non documente et propre a
# cette version, on elimine le probleme : le nom de cle ecrit dans le
# keystore ET la reference ${...} lue par Logstash au demarrage du
# pipeline utilisent maintenant EXACTEMENT la meme casse (minuscules)
# des deux cotes - voir LS_B025_ARMED.sh pour le miroir de ce
# changement.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
mkdir -p /etc/logstash/conf.d
# Copie locale des certs (voir lib/commun.sh) - idempotent, sans effet si
# LS_020 l'a deja fait, mais garantit ce fichier correct meme si ce job
# est rejoue seul (ex: bin/order_job.sh) avant LS_020.
local_pki_copy "/etc/logstash/certs" "${LS_USER}:${LS_USER}"

OUT_FILE="/etc/logstash/conf.d/30-outputs.conf"

# CORRIGE LE 2026-08-30 (incident reel wef-elk-core, decouvert en
# rejouant ce job apres un changement de ES_PORT) : LS_036_FINAL (plus
# tard dans la chaine) verrouille /etc/logstash/conf.d/*.conf en
# immuable (chattr +i) une fois le premier passage termine - rejouer CE
# job ensuite (reglage change dans vars.conf, ou comme ici a la main via
# bin/order_job.sh) echouait silencieusement ("Operation non permise" sur
# la redirection, jamais verifiee) : le fichier affichait "regenere"
# dans le log alors qu'il n'avait pas bouge du tout. Corrige : on leve
# l'immutabilite si elle est deja posee - LS_036_FINAL la reposera de
# toute facon au prochain passage complet de la chaine (chattr +i est
# deja inconditionnel de son cote, verifie dans son propre code).
if [ -e "$OUT_FILE" ] && lsattr "$OUT_FILE" 2>/dev/null | grep -q '^....i'; then
  echo "[LS_024] ${OUT_FILE} est immuable (deja verrouille par LS_036_FINAL) - deverrouillage temporaire avant reecriture."
  chattr -i "$OUT_FILE"
fi

BLOCKS=""

# --- Bloc Elasticsearch (token ou mot de passe, selon ES_AUTH_MODE) ---
if [ "${LS_OUTPUT_ES_ENABLED:-true}" = "true" ]; then
  if [ "${ES_AUTH_MODE:-token}" = "password" ]; then
    echo "[LS_024] Sortie Elasticsearch : mode MOT DE PASSE."
    BLOCKS="${BLOCKS}
  elasticsearch {
    hosts => [\"https://127.0.0.1:${ES_PORT}\"]
    user => \"factory_ingest_user\"
    password => \"\${factory_ingest_password}\"
    ssl_certificate_authorities => [\"/etc/logstash/certs/factory_ca.crt\"]
    index => \"log-%{+YYYY.MM.dd}\"
  }"
  else
    echo "[LS_024] Sortie Elasticsearch : mode TOKEN."
    BLOCKS="${BLOCKS}
  elasticsearch {
    hosts => [\"https://127.0.0.1:${ES_PORT}\"]
    api_key => \"\${factory_ingest_token}\"
    ssl_certificate_authorities => [\"/etc/logstash/certs/factory_ca.crt\"]
    index => \"log-%{+YYYY.MM.dd}\"
  }"
  fi
else
  echo "[LS_024] Sortie Elasticsearch : DESACTIVEE (LS_OUTPUT_ES_ENABLED=false)."
fi

# --- Bloc fichier texte local (JSON lines, pour audit/relecture/archive) ---
if [ "${LS_OUTPUT_FILE_ENABLED:-false}" = "true" ]; then
  echo "[LS_024] Sortie fichier : ACTIVEE -> ${LS_OUTPUT_FILE_PATH}"
  mkdir -p "$(dirname "${LS_OUTPUT_FILE_PATH}")"
  BLOCKS="${BLOCKS}
  file {
    path => \"${LS_OUTPUT_FILE_PATH}\"
    codec => json_lines
  }"
else
  echo "[LS_024] Sortie fichier : desactivee (LS_OUTPUT_FILE_ENABLED=false)."
fi

# --- Bloc S3 OVH (object storage S3-compatible) ---
if [ "${LS_OUTPUT_S3_ENABLED:-false}" = "true" ]; then
  if [ -z "${OVH_S3_ENDPOINT:-}" ] || [ -z "${OVH_S3_BUCKET:-}" ] || [ -z "${OVH_S3_ACCESS_KEY:-}" ] || [ -z "${OVH_S3_SECRET_KEY:-}" ]; then
    echo "[LS_024] AVERTISSEMENT : LS_OUTPUT_S3_ENABLED=true mais OVH_S3_* incomplet dans vars.conf. Sortie S3 ignoree."
  else
    echo "[LS_024] Sortie S3 OVH : ACTIVEE -> bucket ${OVH_S3_BUCKET}"
    if ! /usr/share/logstash/bin/logstash-plugin list 2>/dev/null | grep -q "^logstash-output-s3$"; then
      echo "[LS_024] Installation du plugin logstash-output-s3..."
      /usr/share/logstash/bin/logstash-plugin install logstash-output-s3
    fi
    BLOCKS="${BLOCKS}
  s3 {
    endpoint => \"${OVH_S3_ENDPOINT}\"
    region => \"${OVH_S3_REGION}\"
    bucket => \"${OVH_S3_BUCKET}\"
    access_key_id => \"${OVH_S3_ACCESS_KEY}\"
    secret_access_key => \"${OVH_S3_SECRET_KEY}\"
    additional_settings => {
      force_path_style => true
    }
    prefix => \"wef-logstash/%{+YYYY/MM/dd}\"
    time_file => 15
    codec => json_lines
  }"
  fi
else
  echo "[LS_024] Sortie S3 OVH : desactivee (LS_OUTPUT_S3_ENABLED=false)."
fi

if [ -z "$BLOCKS" ]; then
  echo "[LS_024] AVERTISSEMENT : aucune sortie activee, un bloc output vide sera ecrit."
fi

cat > "$OUT_FILE" << CONFEOF
output {${BLOCKS}
}
CONFEOF

# Verification explicite de l'ecriture (jamais suppose) - directement
# motive par l'incident immuable ci-dessus : la redirection avait deja
# echoue une fois en silence (code de sortie de "cat >" jamais lu),
# "OK" affiche quand meme.
if [ "${LS_OUTPUT_ES_ENABLED:-true}" = "true" ] && ! grep -q "127.0.0.1:${ES_PORT}" "$OUT_FILE"; then
  echo "[LS_024] ERREUR : ${OUT_FILE} ne contient pas le port ES_PORT attendu (${ES_PORT}) apres ecriture - la redirection a echoue silencieusement (fichier toujours immuable ?)." >&2
  lsattr "$OUT_FILE" >&2 2>/dev/null || true
  exit 1
fi

echo "[LS_024] Pipeline de sortie regenere dans ${OUT_FILE}."
echo "[LS_024] OK."
exit 0
