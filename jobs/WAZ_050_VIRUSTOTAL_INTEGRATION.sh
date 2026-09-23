#!/bin/bash
# WAZ_050_VIRUSTOTAL_INTEGRATION - WEF_WAZ_RUN_VTINTEGR
#
# AJOUTE LE 2026-09-16 (playbook PB-007, demande explicite : "un job RUN
# pour l'integration VirusTotal"). Chaque fichier detecte par le FIM
# (syscheck) dans VT_WATCH_DIR est automatiquement soumis a l'API
# VirusTotal par le manager - si son hash est deja connu comme
# malveillant, une alerte est generee. Necessite une cle API VirusTotal
# GRATUITE, creee par l'operateur lui-meme sur virustotal.com - jamais
# generee ni devinee ici (voir vars.conf, VIRUSTOTAL_API_KEY_FILE, meme
# principe que SMTP_PASS_FILE).
#
# CORRIGE LE 2026-09-16 (incident reel, wef-elk-core, diagnostique via
# le JSON brut d'une alerte reelle) : filtre par rule_id (100100 - la
# regle generique preexistante de WAZ_025.sh - plus 550/553/554, les
# regles FIM standard), jamais par <group>syscheck</group> - ce groupe
# n'apparait jamais sur les alertes de ce type dans cet environnement,
# rendant l'integration invisible (aucune erreur, juste jamais declenchee).
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

if [ ! -s "${VIRUSTOTAL_API_KEY_FILE:-}" ]; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : ${VIRUSTOTAL_API_KEY_FILE} absent ou vide." >&2
  echo "Creez une cle API gratuite sur https://www.virustotal.com puis :" >&2
  echo "  echo -n 'votre_cle_api' > ${VIRUSTOTAL_API_KEY_FILE}" >&2
  echo "  chmod 600 ${VIRUSTOTAL_API_KEY_FILE}" >&2
  exit 1
fi
VT_API_KEY="$(cat "$VIRUSTOTAL_API_KEY_FILE")"

WATCH_DIR="${VT_WATCH_DIR:-/root/wef_vt_watch}"
echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Preparation du dossier de demo surveille ${WATCH_DIR}..."
mkdir -p "$WATCH_DIR"
chmod 700 "$WATCH_DIR"

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

# ELARGI LE 2026-09-18 (demande explicite : "je veux que virustotal detecte
# seul des fichiers sans qu'un humain lui fournisse le fichier" -> puis,
# apres explication des limites reelles, "faisons comme vous percevez").
# Surveiller "/" entier en temps reel est un anti-pattern reel, jamais
# fait en production, pour 3 raisons verifiables :
#   1. Le noyau limite le nombre de "watches" inotify (quelques centaines
#      de milliers) - depasse en quelques secondes sur "/", au-dela Wazuh
#      arrete silencieusement de surveiller, sans erreur visible.
#   2. Le volume d'ecritures purement internes au systeme (logs, cache du
#      gestionnaire de paquets, fichiers temporaires) genererait des
#      milliers de fausses alertes FIM/heure, saturant instantanement
#      l'API VirusTotal gratuite (4 requetes/minute) - l'inverse de l'
#      objectif ("les vrais problemes", pas du bruit).
#   3. Un attaquant reel depose rarement un fichier dans /usr/lib ou
#      /var/cache - il ecrit la ou un humain peut ecrire.
# Compromis retenu : surveiller TOUTES les zones ou un fichier peut
# legitimement apparaitre (home reels de la machine, /tmp, points de
# montage USB, le dossier de demo) - jamais les dossiers de tenue interne
# du systeme qui changent tout seuls (/proc, /sys, /dev, /var/log,
# /var/cache, /var/lib, /var/ossec lui-meme pour eviter qu'il ne
# s'auto-declenche). Liste construite dynamiquement a chaque execution
# (jamais devinee) : seuls les dossiers reellement presents sur CETTE
# machine sont inclus.
WATCH_DIRS_LIST=("/root" "/tmp" "$WATCH_DIR")
for MOUNT_POINT in /media /mnt; do
  mkdir -p "$MOUNT_POINT" 2>/dev/null || true
  WATCH_DIRS_LIST+=("$MOUNT_POINT")
done
for HOME_DIR in /home/*/; do
  [ -d "$HOME_DIR" ] && WATCH_DIRS_LIST+=("${HOME_DIR%/}")
done
FIM_DIRECTORIES="$(printf '%s\n' "${WATCH_DIRS_LIST[@]}" | sort -u | paste -sd, -)"
echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Dossiers reellement surveilles (decouverts sur cette machine) : ${FIM_DIRECTORIES}"

# CORRIGE LE 2026-09-16 (incident reel, wef-elk-core : "Operation non
# permise" sur ossec.conf) : deja verrouille immuable par WAZ_032
# (chattr +i) - meme motif deja etabli ailleurs dans ce projet
# (WAZ_014E_INDEXER_CONNECTOR.sh/WAZ_019_FLOOD.sh) : deverrouiller
# temporairement, reecrire, puis TOUJOURS reverrouiller (droits root:wazuh
# 640 restaures avant le chattr +i final, jamais suppose deja corrects).
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ${OSSEC_CONF} est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER_FIM="<!-- WEF_VT_FIM_CONFIG (WAZ_050, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_FIM" "$OSSEC_CONF"; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Bloc FIM deja pose, retrait avant reecriture..."
  sed -i "\|^${MARKER_FIM//\//\\/}\$|,\|^<!-- WEF_VT_FIM_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
# CORRIGE LE 2026-09-19 (incident reel, wef-elk-core, diagnostique via
# alerts.json en direct avec l'operateur) : l'integration VirusTotal
# ecrit SES PROPRES fichiers de travail temporaires dans /tmp
# (/tmp/virustotal-<epoch>-<random>.alert, crees puis supprimes en
# ~1s). Comme /tmp fait partie du perimetre surveille (ligne
# ci-dessous), CHAQUE fichier temporaire de l'integration declenche
# lui-meme une alerte FIM (rule 554/553) qui matche a nouveau le
# rule_id filtre par l'integration - boucle d'auto-declenchement
# infinie, ~1 appel API/seconde, qui epuise le quota gratuit (4/min)
# en continu depuis le tout premier demarrage. Constate en reel :
# AUCUNE soumission n'a jamais abouti (uniquement rule_id 87101,
# "Public API request rate limit reached", en boucle). Corrige par
# une exclusion FIM explicite de ses propres fichiers de travail -
# la seule source reelle du bruit, jamais les vrais fichiers utilisateur.
echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Ajout de la surveillance FIM temps reel de : ${FIM_DIRECTORIES}..."
{
  echo "$MARKER_FIM"
  echo "<ossec_config>"
  echo "  <syscheck>"
  echo "    <directories realtime=\"yes\" report_changes=\"yes\">${FIM_DIRECTORIES}</directories>"
  echo "    <ignore type=\"sregex\">^/tmp/virustotal-</ignore>"
  echo "  </syscheck>"
  echo "</ossec_config>"
  echo "<!-- WEF_VT_FIM_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER_FIM" "$OSSEC_CONF" || { echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : bloc FIM absent apres ecriture (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

# Jamais le contenu de la cle API n'est ecrit dans un echo/log - seul le
# bloc XML genere ci-dessous la contient, dans ossec.conf lui-meme
# (proprietaire root, meme sensibilite qu'un mot de passe deja gere
# ailleurs dans ce fichier par le paquet Wazuh).
MARKER_VT="<!-- WEF_VT_INTEGRATION_CONFIG (WAZ_050, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_VT" "$OSSEC_CONF"; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Bloc integration deja pose, retrait avant reecriture..."
  sed -i "\|^${MARKER_VT//\//\\/}\$|,\|^<!-- WEF_VT_INTEGRATION_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
# CORRIGE LE 2026-09-16 (incident reel, wef-elk-core) : le filtre
# <group>syscheck</group> ne se declenche JAMAIS ici - une regle
# preexistante du projet (WAZ_025.sh, id 100100, "Modification detectee
# sur un fichier surveille de la Forge") intercepte tout evenement FIM
# generique et n'expose QUE ses propres groupes ("local,syslog,sshd"),
# jamais "syscheck", confirme par l'alerte JSON reelle
# (/var/ossec/logs/alerts/alerts.json). Corrige : filtre par rule_id
# explicite plutot que par groupe - la regle 100100 (celle qui se
# declenche reellement dans cet environnement) plus les regles FIM
# standard (550/553/554) pour rester correct meme sur un chemin qui ne
# serait pas intercepte par la regle 100100.
echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Ajout de l'integration VirusTotal (rule_id 100100,550,553,554)..."
{
  echo "$MARKER_VT"
  echo "<ossec_config>"
  echo "  <integration>"
  echo "    <name>virustotal</name>"
  echo "    <api_key>${VT_API_KEY}</api_key>"
  echo "    <rule_id>100100,550,553,554</rule_id>"
  echo "    <alert_format>json</alert_format>"
  echo "  </integration>"
  echo "</ossec_config>"
  echo "<!-- WEF_VT_INTEGRATION_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER_VT" "$OSSEC_CONF" || { echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : bloc integration absent apres ecriture (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Reverrouillage de ${OSSEC_CONF} (droits + chattr +i)..."
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] ERREUR : wazuh-manager n'a pas redemarre." >&2
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_050_VIRUSTOTAL_INTEGRATION] OK. Tout fichier depose dans l'une de ces zones (${FIM_DIRECTORIES}) - par un humain, un navigateur, une cle USB ou un script - declenche desormais automatiquement une soumission a VirusTotal, sans aucune autre intervention."
exit 0
