#!/bin/bash
# WAZ_055_NMAP_SCAN_INTEGRATION - WEF_WAZ_RUN_NMAPSCAN - Playbook PB-009
#
# AJOUTE LE 2026-09-22 (demande explicite : "je veux qu'on ajoute nmap a
# wazuh" -> "scan periodique automatique"). Integration NATIVE Wazuh -
# <localfile><log_format>command</log_format><frequency>...</frequency></localfile>
# est le mecanisme reel et documente de Wazuh pour faire executer une
# commande par le logcollector a intervalle regulier et ingerer chaque
# ligne de sa sortie comme un evenement. Choisi plutot que le calendrier
# natif WEF (bin/scheduler.sh, deja construit pour d'autres besoins) :
# deux mecanismes de periodicite concurrents pour la meme tache seraient
# une duplication inutile, jamais un gain.
#
# JOB_ID choisi (055, pas 054) : 054 reste reserve a une migration future
# deja documentee dans le plan de session (WAZ_054_VT_WATCH_REFRESH,
# jamais construite a ce jour) - evite toute collision future.
#
# Meme discipline "jamais un ID Wazuh par defaut suppose" que WAZ_040/041
# (regle 100101, <match> texte direct) : la regle ci-dessous filtre sur
# le contenu REEL et VERIFIABLE de la sortie nmap au format "grepable"
# (-oG), jamais un rule_id/decoder Wazuh par defaut non confirme.
set -uo pipefail
source "$VARS_FILE"
PROJECT_ROOT="$(dirname "$VARS_FILE")"
source "$PROJECT_ROOT/lib/commun.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : doit tourner en root." >&2
  exit 1
fi

if ! command -v nmap &>/dev/null; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] nmap absent, installation..."
  dnf install -y nmap >/dev/null 2>&1 || yum install -y nmap >/dev/null 2>&1 || {
    echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : installation de nmap echouee (ni dnf ni yum disponible/reussi)." >&2
    exit 1
  }
fi

NMAP_TARGET="${NMAP_SCAN_TARGET:-192.168.50.0/24}"
NMAP_INTERVAL="${NMAP_SCAN_INTERVAL_SEC:-3600}"
echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Cible : ${NMAP_TARGET}, frequence : ${NMAP_INTERVAL}s."

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

# Meme motif deja etabli (WAZ_050/051/052) : deverrouiller si deja
# verrouille immuable par WAZ_032, TOUJOURS reverrouiller apres, jamais
# suppose deja correct dans un sens ou dans l'autre.
if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ${OSSEC_CONF} est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER="<!-- WEF_NMAP_SCAN_CONFIG (WAZ_055, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Bloc deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_NMAP_SCAN_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Declaration du scan periodique dans ossec.conf..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <localfile>"
  echo "    <log_format>command</log_format>"
  echo "    <command>nmap -sV -oG - ${NMAP_TARGET}</command>"
  echo "    <alias>wef-nmap-scan</alias>"
  echo "    <frequency>${NMAP_INTERVAL}</frequency>"
  echo "  </localfile>"
  echo "</ossec_config>"
  echo "<!-- WEF_NMAP_SCAN_CONFIG_END -->"
} >> "$OSSEC_CONF"
grep -qF "$MARKER" "$OSSEC_CONF" || { echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : bloc absent apres ecriture (fichier verrouille ? voir chattr/lsattr)." >&2; exit 1; }

echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Reverrouillage de ${OSSEC_CONF} (droits + chattr +i)..."
chown root:wazuh "$OSSEC_CONF"
chmod 640 "$OSSEC_CONF"
chattr +i "$OSSEC_CONF"

RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
[ -f "$RULES_FILE" ] || { echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : ${RULES_FILE} introuvable (WAZ_025 doit avoir tourne)." >&2; exit 1; }
MARKER_RULE="<!-- WEF_NMAP_SCAN_RULE (WAZ_055, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_RULE" "$RULES_FILE"; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Regle nmap deja posee, retrait avant reecriture..."
  sed -i "\|^${MARKER_RULE//\//\\/}\$|,\|^<!-- WEF_NMAP_SCAN_RULE_END -->\$|d" "$RULES_FILE"
fi
# CORRIGE PAR ANTICIPATION (meme cause reelle deja diagnostiquee sur
# WAZ_050/051 le 2026-09-16/19) : jamais <if_group>syscheck</if_group>
# ni un groupe suppose - un <match> texte direct sur le format grepable
# nmap reel ("Ports: <port>/open/..."), deja la methode eprouvee cette
# session (WAZ_040/041, regle 100101 sur WEF_CANARY_TEST).
# Volontairement PAS d'alerte separee sur "Status: Up" (hote decouvert) :
# bruit constant a chaque tick pour une valeur limitee - seul un port
# OUVERT est le signal de securite reellement utile ici.
echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Ajout de la regle de detection (id 100300)..."
{
  echo "$MARKER_RULE"
  echo "<group name=\"nmap_scan,\">"
  echo "  <rule id=\"100300\" level=\"5\">"
  echo "    <match>Ports: .*open</match>"
  echo "    <description>Scan reseau (nmap) : port(s) ouvert(s) detecte(s) sur le sous-reseau de la Forge</description>"
  echo "    <group>nmap_scan,</group>"
  echo "  </rule>"
  echo "</group>"
  echo "<!-- WEF_NMAP_SCAN_RULE_END -->"
} >> "$RULES_FILE"
grep -qF "$MARKER_RULE" "$RULES_FILE" || { echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : regle absente apres ecriture dans ${RULES_FILE}." >&2; exit 1; }

echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Redemarrage de wazuh-manager pour appliquer..."
systemctl restart wazuh-manager
if ! wait_for_service_active wazuh-manager 180 5; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : wazuh-manager n'a pas redemarre." >&2
  journalctl -u wazuh-manager -n 30 --no-pager 2>/dev/null || true
  exit 1
fi

echo "[WAZ_055_NMAP_SCAN_INTEGRATION] OK. nmap scanne ${NMAP_TARGET} toutes les ${NMAP_INTERVAL}s ; tout port ouvert detecte declenche la regle 100300 (recherche : rule.id : 100300)."
exit 0
