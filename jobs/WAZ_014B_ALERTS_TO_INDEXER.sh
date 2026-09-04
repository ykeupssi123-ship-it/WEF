#!/bin/bash
# WAZ_014B_ALERTS_TO_INDEXER - WEF_WAZ_BLD_ALERTSTOIDXR - Raccordement des
# alertes du manager vers l'indexeur (pipeline Logstash dedie)
#
# AJOUTE LE 2026-08-30 (incident reel wef-elk-core, diagnostic complet
# de l'echec WAZ_020_VERIFY - voir aussi les en-tetes de WAZ_013C/
# WAZ_014A/WAZ_013D pour les autres correctifs du meme diagnostic).
# LACUNE REELLE TROUVEE, pas un bug de script : le manager genere bien
# de vraies alertes (confirme en reel : /var/ossec/logs/alerts/alerts.log
# contenait des dizaines de milliers de lignes reelles), mais RIEN ne
# les acheminait jusqu'a wazuh-indexer avant ce job - aucun job WAZ_0xx
# n'existait pour ca (les jobs FB_* sont reserves a AGENT_HOST, un besoin
# different : expedier les logs D'AUTRES machines, pas les alertes DU
# manager local). Le connecteur natif du manager (<indexer> dans
# ossec.conf, Wazuh 4.8+) est reserve aux indices "wazuh-states-*"
# (inventaire/vulnerabilites), jamais aux alertes elles-memes.
#
# PREMIER ESSAI (abandonne) : Filebeat 8.19.20 (seule version dispo dans
# le depot "elasticsearch" - filebeat-oss et 7.10.2 n'y sont plus
# proposes). Installe, connecte, mais bloque en reel sur une
# incompatibilite connue Filebeat/OpenSearch : les appels internes de
# Filebeat vers /_license et /_xpack (verification de fonctionnalites,
# non desactivable par un reglage YAML trouve) recoivent un 400
# "invalid_index_name_exception" de wazuh-indexer (OpenSearch ne les
# implemente pas du tout), empechant definitivement la publication.
# Confirme par test direct : curl vers ces deux routes echoue pareil,
# hors de tout contexte Filebeat - incompatibilite reelle du produit,
# pas une erreur de configuration de ce projet.
#
# CORRIGE (definitif) : Logstash, DEJA installe et DEJA fonctionnel sur
# cette meme VM pour le pipeline ELK classique (LS_024, deja verifie en
# reel), ne fait pas ces appels /_license//_xpack - son plugin de sortie
# elasticsearch fonctionne directement, meme motif SSL que celui deja
# prouve par LS_024 (ssl_certificate_authorities seul, verification
# complete via la CA de l'usine). Pipeline SEPARE et ISOLE du pipeline
# ELK classique (via pipelines.yml, pas conf.d) : jamais de melange
# entre les alertes Wazuh et le pipeline general, jamais de risque de
# casser LS_024/01-inputs.conf/10-privacy-filter.conf en les rejouant.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

WAZUH_INDEXER_ADMIN_PW="$(read_or_generate_secret "$WAZ_INDEXER_ADMIN_PASSWORD_FILE" non)" || exit 1
# CORRIGE LE 2026-09-03 (incident reel deploiement MIPREL, voir
# docs/JOURNAL_TECHNIQUE.md) : valeur par defaut fausse ici (9200,
# le port Elasticsearch classique) alors que WAZ_014A_INDXR_ADMINPW.sh
# et WAZ_020_VERIFY.sh utilisent tous deux 9201 par defaut pour cette
# meme variable (le vrai port REST de wazuh-indexer sur cette usine,
# voir WAZ_013D_INDXR_PORTS.sh). Preuve directe : Logstash journalisait
# en boucle "Could not fetch URL https://127.0.0.1:9200/... Connexion
# refusee" alors que le manager generait bien de vraies alertes
# localement (6140 confirmees dans alerts.log) - rien n'ecoute en HTTP
# sur 9200 dans ce deploiement.
WAZ_INDEXER_PORT="${WAZ_INDEXER_PORT:-9201}"
LS_CERTS="/etc/logstash/certs"
PIPELINE_CONF="/etc/logstash/wazuh-alerts.conf"
PIPELINES_YML="/etc/logstash/pipelines.yml"

echo "[WAZ_014B] Copie locale des certificats PKI pour logstash (deja fait par LS_024, idempotent)..."
local_pki_copy "$LS_CERTS" "${LS_USER}:${LS_USER}"

# --- Acces en lecture au fichier d'alertes du manager (BLOCAGE REEL
# TROUVE LE 2026-08-30, apres le correctif "plugin http" ci-dessous :
# le pipeline demarrait bien et ne levait plus aucune erreur, mais
# `sincedb_wazuh_alerts` restait desesperement a 0 octet et
# `wazuh-alerts-4.x-*` inexistant - aucune erreur dans les logs
# Logstash, silence total, car le plugin "file" en input echoue a
# l'OUVERTURE du fichier, avant meme d'avoir quoi que ce soit a logger
# comme erreur applicative. Verifie en reel : `/var/ossec/logs/alerts/`
# est en 750 wazuh:wazuh et `alerts.json` en 640 wazuh:wazuh - le groupe
# "wazuh" (cree par le paquet wazuh-manager lui-meme, jamais par cette
# usine) n'a AUCUN membre (`getent group wazuh` -> vide), et
# ${LS_USER} n'y appartient pas. Meme motif reel, meme solution, que
# LS_013.sh (inclusion au groupe crypto partage) - reprend ici
# exactement le meme idiome plutot que d'inventer une variante :
# ajout de compte au groupe existant, jamais de relachement des droits
# du fichier source (chmod) qui casserait l'isolement voulu par
# wazuh-manager sur ses propres logs. Le redemarrage de logstash plus
# bas dans ce meme job est necessaire ET suffisant pour que le nouveau
# groupe secondaire soit pris en compte (initgroups() au demarrage du
# service, jamais reevalue a chaud sur un processus deja lance). ---
echo "[WAZ_014B] Inclusion de ${LS_USER} au groupe wazuh (lecture de /var/ossec/logs/alerts/alerts.json)..."
usermod -aG wazuh "${LS_USER}" || true

# --- Coffre Logstash : cle en MINUSCULES (meme lecon reelle que
# LS_024/LS_B025_ARMED - le coffre normalise les noms en interne quelle
# que soit la casse ecrite - toutes deux deja documentees et resolues
# dans LS_B025_ARMED.sh (meme projet, plus tot dans la chaine) - reprend
# ici EXACTEMENT le meme motif eprouve, plutot que de rejouer les memes
# incidents par une implementation independante :
#   (1) --path.settings /etc/logstash obligatoire sur CHAQUE appel :
#       sans lui, logstash-keystore vise par defaut
#       /usr/share/logstash/config/logstash.keystore (fichier different,
#       inexistant) au lieu de /etc/logstash/logstash.keystore (le vrai,
#       deja cree par LS_B025_ARMED) - constate en reel juste avant ce
#       correctif ("ERROR: Logstash keystore not found").
#   (2) create (avec "echo y" - invite interactive sinon) uniquement si
#       le fichier n'existe pas encore.
#   (3) remove-puis-add pour l'idempotence : --force n'existe pas sur
#       cette commande.
KEYSTORE_BIN="/usr/share/logstash/bin/logstash-keystore"
KEYSTORE_PATH_ARGS=(--path.settings /etc/logstash)

if [ ! -f /etc/logstash/logstash.keystore ]; then
  echo "[WAZ_014B] Creation du keystore Logstash (absent - inattendu, LS_B025_ARMED aurait deja du le creer)..."
  echo y | "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" create
  [ -f /etc/logstash/logstash.keystore ] || { echo "[WAZ_014B] ERREUR : /etc/logstash/logstash.keystore toujours absent apres 'create'." >&2; exit 1; }
fi

echo "[WAZ_014B] Armement du coffre Logstash (mot de passe admin indexeur)..."
if "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" list 2>/dev/null | grep -qix "wazuh_indexer_admin_password"; then
  "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" remove wazuh_indexer_admin_password >/dev/null 2>&1 || true
fi
# printf (pas echo) : evite un retour a la ligne parasite en fin de
# valeur - meme discipline que LS_B025_ARMED.sh, qui pipe directement
# depuis un fichier ("cat") pour la meme raison, jamais "echo" sur une
# variable shell dont le contenu devient un secret.
printf '%s' "$WAZUH_INDEXER_ADMIN_PW" | "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" add wazuh_indexer_admin_password --stdin
if ! "$KEYSTORE_BIN" "${KEYSTORE_PATH_ARGS[@]}" list 2>/dev/null | grep -qix "wazuh_indexer_admin_password"; then
  echo "[WAZ_014B] ERREUR : wazuh_indexer_admin_password absent de 'logstash-keystore list' apres l'ajout." >&2
  exit 1
fi

# --- Pipeline dedie (regenere entierement a chaque passage, meme
# philosophie que LS_024/WAZ_017C : jamais de residu a deviner) ---
#
# CORRIGE LE 2026-08-30 (2e incident reel le meme jour, sortie
# "elasticsearch" de Logstash abandonnee a son tour) : cette sortie
# echoue systematiquement avec "Could not connect to a compatible
# version of Elasticsearch", meme avec des identifiants et un
# certificat verifies corrects par ailleurs (curl direct, memes
# identifiants, meme CA : reponse 200 immediate). Cause trouvee dans le
# CODE SOURCE reel du plugin installe
# (logstash-output-elasticsearch-11.22.17-java/lib/.../pool.rb,
# methode elasticsearch?()) : pour une version rapportee 7.x, le plugin
# EXIGE que la reponse racine contienne version.build_flavor == "default"
# - or la reponse de wazuh-indexer (verifiee en reel) ne contient AUCUN
# champ build_flavor du tout, quel que soit compatibility.override_main_
# response_version cote serveur (ce reglage ne fabrique pas ce champ).
# Verification codee en dur, sans option YAML pour la contourner (grep
# exhaustif sur le gem installe, aucun reglage trouve). Meme famille de
# blocage, cause differente, que l'abandon de Filebeat plus tot.
#
# Corrige en changeant de plugin de sortie : "http" (generique, deja
# installe - "logstash-plugin list" confirme sa presence), qui ne fait
# AUCUNE verification de version/produit - un simple client HTTP qui
# POST directement vers l'API _doc de l'indexeur. Perd la gestion de
# pool/retry avancee du plugin "elasticsearch" specialise, mais chaque
# alerte est deja un document JSON autonome (codec json en entree) : un
# POST simple par document suffit a ce besoin.
echo "[WAZ_014B] Ecriture du pipeline dedie ${PIPELINE_CONF}..."
cat > "$PIPELINE_CONF" << CONFEOF
input {
  file {
    path => "/var/ossec/logs/alerts/alerts.json"
    start_position => "beginning"
    sincedb_path => "/var/lib/logstash/sincedb_wazuh_alerts"
    codec => "json"
  }
}
output {
  http {
    url => "https://127.0.0.1:${WAZ_INDEXER_PORT}/wazuh-alerts-4.x-%{+YYYY.MM.dd}/_doc"
    http_method => "post"
    format => "json"
    user => "${WAZ_INDEXER_ADMIN_USER}"
    password => "\${wazuh_indexer_admin_password}"
    cacert => "${LS_CERTS}/factory_ca.crt"
    retry_non_idempotent => true
  }
}
CONFEOF
chown "${LS_USER}:${LS_USER}" "$PIPELINE_CONF"
chmod 640 "$PIPELINE_CONF"

# --- Enregistrement du pipeline (idempotent : n'ajoute qu'une fois,
# jamais de doublon si ce job est rejoue) ---
if grep -q '^- pipeline.id: wazuh-alerts$' "$PIPELINES_YML" 2>/dev/null; then
  echo "[WAZ_014B] Pipeline 'wazuh-alerts' deja enregistre dans ${PIPELINES_YML}, ignore."
else
  echo "[WAZ_014B] Enregistrement du pipeline 'wazuh-alerts' dans ${PIPELINES_YML}..."
  {
    echo ""
    echo "- pipeline.id: wazuh-alerts"
    echo "  path.config: \"${PIPELINE_CONF}\""
  } >> "$PIPELINES_YML"
fi

echo "[WAZ_014B] Redemarrage de logstash (prend en compte le nouveau pipeline)..."
systemctl restart logstash 2>/dev/null || true
if ! wait_for_service_active logstash 120 5; then
  echo "[WAZ_014B] ERREUR : logstash.service n'a pas redemarre. Diagnostic (journalctl -u logstash -n 30) :" >&2
  journalctl -u logstash -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_014B] OK (pipeline 'wazuh-alerts' actif - la verification fonctionnelle reelle du transit des alertes reste faite par WAZ_020_VERIFY, en aval)."
exit 0
