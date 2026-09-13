#!/bin/bash
# LS_020 - WEF_LS_BLD_INPUTUNVRSL - Entrees SSL universelles
# CORRECTIF 2-VM : le bloc "beats" ecoute sur 0.0.0.0 (au lieu de
# 127.0.0.1 uniquement) pour accepter BEATS_HOST (VM2). Le pare-feu
# (LS_008) reste la ligne de defense qui limite la source a BEATS_HOST_IP.
# Ajoute aussi une 3e entree dediee a Wazuh (port 5000, meme machine,
# donc boucle locale) : necessaire pour WAZ_023 plus loin dans la chaine.
#
# CORRECTIF 2026-08-18 (incident reel : crash loop Netty
# RejectedExecutionException) : l'entree TCP syslog n'ecoute PLUS sur le
# port privilegie 514 (bind EACCES pour l'utilisateur non-root logstash,
# retries en boucle, event-loop-group Netty detruit en plein retry ->
# RejectedExecutionException sur les taches encore en vol). Elle ecoute
# sur LS_SYSLOG_INTERNAL_PORT (5514, non privilegie) ; LS_007 redirige la
# facade publique 514 vers ce port via le pare-feu. Host "0.0.0.0" (et
# non 127.0.0.1) : necessaire pour recevoir le trafic deja redirige par
# le pare-feu (meme raison que le bloc beats ci-dessus), ce qui n'etait
# pas non plus le cas avant ce correctif.
#
# CORRIGE LE 2026-08-31 (incident reel, premier deploiement d'agent sur
# 192.168.50.130) : Filebeat/Metricbeat se connectaient bien (poignee de
# main TCP etablie) puis se faisaient reinitialiser immediatement -
# "write: connection reset by peer", confirme cote Filebeat par
# 8000/8000 evenements en echec de publication. Cause reelle : le bloc
# "beats" ci-dessous fournit "ssl_certificate_authorities" (CA de
# verification) SANS jamais preciser "ssl_client_authentication" - le
# plugin logstash-input-beats exige alors une authentification par
# certificat CLIENT des qu'une CA est fournie, sauf mode explicitement
# desactive - or ni Filebeat ni Metricbeat (FB_012/MB_012) ne presentent
# de certificat client, par conception : l'architecture cible de cette
# usine est une TLS a sens unique (serveur authentifie, jamais le
# client), confirmee par un exemple de configuration reelle et deja
# EPROUVEE EN PRODUCTION fournie directement par l'utilisateur - jamais
# de coffre ni de certificat client cote Beats.
#
# CORRIGE ENCORE LE 2026-08-31 (meme jour - premiere tentative de
# correctif ci-dessus INCOMPLETE, decouvert en redemarrant reellement
# Logstash et en lisant l'erreur EXACTE du plugin, jamais supposee) :
# "ssl_client_authentication => 'none'" ne satisfait PAS le validateur
# du plugin - le message d'erreur reel est on ne peut plus explicite :
# "Configuring ssl_certificate_authorities requires
# ssl_client_authentication => to be configured with 'optional' or
# 'required'" (confirme par lecture directe du code source du plugin,
# beats.rb:342 validate_ssl_config!) - "none" n'est PAS une valeur
# acceptee des lors qu'une CA est fournie, quelle que soit l'intention.
# La vraie cause : "ssl_certificate_authorities" ne sert QU'A verifier
# le certificat d'un CLIENT (authentification mutuelle) - totalement
# inutile ici puisque cette usine ne verifie jamais de certificat cote
# client, par conception (voir plus haut). Corrige pour de bon : la
# ligne "ssl_certificate_authorities" est retiree du bloc "beats"
# (entree) - elle reste evidemment necessaire cote Filebeat/Metricbeat
# (sortie, FB_012/MB_012) pour verifier le certificat SERVEUR presente
# ici, ce sont deux usages distincts, jamais le meme fichier de
# confiance pour les deux sens. "ssl_client_authentication => 'none'"
# est conserve (redondant avec le defaut du plugin en l'absence de CA,
# mais documente l'intention explicitement).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"
echo "[LS_020] Ecriture des entrees (01-inputs.conf)..."
mkdir -p /etc/logstash/conf.d
# Correctif 2026-08-14 : copie locale des certs par prudence (voir
# lib/commun.sh, meme reflexe applique suite a l'incident Elasticsearch
# 8.19/entitlements) - Logstash tourne sur le meme moteur Java/version que
# l'ES qui a echoue, donc traite comme a risque plutot que suppose sain.
local_pki_copy "/etc/logstash/certs" "${LS_USER}:${LS_USER}"
INPUT_FILE="/etc/logstash/conf.d/01-inputs.conf"
if [ -e "$INPUT_FILE" ] && lsattr "$INPUT_FILE" 2>/dev/null | grep -q '^....i'; then
  echo "[LS_020] ${INPUT_FILE} est immuable (deja verrouille par LS_036_FINAL) - deverrouillage temporaire avant reecriture."
  chattr -i "$INPUT_FILE"
fi
cat > "$INPUT_FILE" << CONFEOF
input {
  beats {
    port => ${LS_BEATS_PORT}
    host => "0.0.0.0"
    ssl_enabled => true
    ssl_certificate => "/etc/logstash/certs/factory_fullchain.pem"
    ssl_key => "/etc/logstash/certs/factory_server.key"
    ssl_client_authentication => "none"
  }
  tcp {
    port => ${LS_SYSLOG_INTERNAL_PORT}
    host => "0.0.0.0"
  }
  tcp {
    port => 5000
    host => "127.0.0.1"
    codec => json_lines
    type => "wazuh-alerts"
  }
}
CONFEOF
if ! grep -q 'ssl_client_authentication' "$INPUT_FILE" 2>/dev/null; then
  echo "[LS_020] ERREUR : ${INPUT_FILE} ne contient pas ssl_client_authentication apres ecriture - la redirection a echoue silencieusement (fichier toujours immuable ?)." >&2
  lsattr "$INPUT_FILE" >&2 2>/dev/null || true
  exit 1
fi
echo "[LS_020] OK."
exit 0
