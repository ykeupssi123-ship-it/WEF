#!/bin/bash
# WAZ_023 - WEF_WAZ_BLD_LOGINTGRT - Liaison locale vers Logstash
# Utilise le mecanisme natif Wazuh <syslog_output> (pas un forward OS
# externe) pour router les alertes vers l'entree dediee Logstash (port
# 5000, ajoutee dans LS_020) au format JSON.
#
# REVU LE 2026-08-12 : le bloc est desormais marque par le commentaire
# WEF_LOGSTASH_FORWARD - c'est ce marqueur qui permet a WAZ_035/WAZ_039
# de cibler EXACTEMENT ce bloc pour l'activer/desactiver, au lieu de
# deviner par un toggle global sur n'importe quel <enabled>/<disabled>
# du fichier (bug corrige : l'ancienne version de WAZ_035/039 ne
# touchait PAS ce bloc du tout, le forward vers Logstash restait actif
# meme en mode "souverain").
#
# CORRIGE LE 2026-08-30 (incident reel wef-elk-core, premier passage
# complet de la chaine) : DEUX bugs reels trouves ensemble ici.
#
# (1) Le sed original ("/<\/ossec_config>/i\...") insere le bloc AVANT
# CHAQUE ligne "</ossec_config>" du fichier, pas seulement la derniere -
# or l'ossec.conf LIVRE PAR LE PAQUET WAZUH LUI-MEME (jamais modifie par
# cette usine avant ce job) contient DEJA DEUX sections racine
# <ossec_config>...</ossec_config> distinctes (confirme en reel :
# `grep -c '</ossec_config>' ossec.conf` -> 2, sur une VM neuve). Un
# seul passage de ce job produisait donc DEUX exemplaires dupliques du
# bloc marque, silencieusement (sed ne signale aucune erreur - il a fait
# exactement ce qui lui a ete demande). Corrige : on compte d'abord le
# nombre reel de fermetures, puis on n'insere qu'avant LA DERNIERE
# (comportement voulu depuis le debut : un seul bloc, en toute fin de
# fichier).
#
# (2) L'element <disabled> a l'interieur de <syslog_output> - le
# mecanisme de bascule marche/arret suppose par WAZ_035/WAZ_039 depuis
# leur creation - N'EST PAS RECONNU par le daemon reel installe sur
# cette VM (Wazuh v4.14.7) : `wazuh-csyslogd -t` rejette categoriquement
# tout <syslog_output> contenant un <disabled>, avec
# "ERROR: (1230): Invalid element in the configuration: 'disabled'" -
# confirme par test direct isole (wazuh-csyslogd -t sur une copie du
# fichier), reproductible, jamais une panne passagere. wazuh-manager
# refuse alors de redemarrer entierement (pas seulement csyslogd), ce
# qui a bloque toute la suite de la chaine (WAZ_035 et au-dela).
# Ce projet abandonne donc l'idee d'un <disabled> interne : le bloc
# <syslog_output> n'a plus JAMAIS ce tag - sa seule PRESENCE (ou
# absence) dans ossec.conf fait foi. Voir WAZ_035_MODE_CONVERGENT.sh
# (s'assure que le bloc existe) et WAZ_039_MODE_SOUVERAIN.sh (retire le
# bloc entierement) pour le miroir de ce changement.
set -uo pipefail
source "$VARS_FILE"
MARKER="<!-- WEF_LOGSTASH_FORWARD -->"
echo "[WAZ_023] Configuration de la sortie syslog JSON vers Logstash local..."
if grep -qF "$MARKER" /var/ossec/etc/ossec.conf 2>/dev/null; then
  echo "[WAZ_023] Sortie deja configuree, ignore."
  echo "[WAZ_023] OK."
  exit 0
fi
TOTAL_CLOSINGS=$(grep -c '</ossec_config>' /var/ossec/etc/ossec.conf)
awk -v marker="$MARKER" -v total="$TOTAL_CLOSINGS" '
  /<\/ossec_config>/ {
    n++
    if (n == total) {
      print marker
      print "  <syslog_output>"
      print "    <server>127.0.0.1</server>"
      print "    <port>5000</port>"
      print "    <format>json</format>"
      print "  </syslog_output>"
    }
  }
  { print }
' /var/ossec/etc/ossec.conf > /var/ossec/etc/ossec.conf.wef_tmp && mv /var/ossec/etc/ossec.conf.wef_tmp /var/ossec/etc/ossec.conf
/var/ossec/bin/wazuh-control enable client-syslog 2>/dev/null || true
echo "[WAZ_023] OK."
exit 0
