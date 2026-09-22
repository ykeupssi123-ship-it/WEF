#!/bin/bash
# WAZ_055_NMAP_SCAN_INTEGRATION - WEF_WAZ_RUN_NMAPSCAN - Playbook PB-009
#
# AJOUTE LE 2026-09-22 (demande explicite : "je veux qu'on ajoute nmap a
# wazuh" -> "scan periodique automatique").
#
# CORRIGE LE 2026-09-22 (meme jour, incident reel sur wef-elk-core) :
# la version initiale utilisait <localfile><log_format>command</log_format>
# (execution native par le logcollector Wazuh). Constate en reel : le
# process nmap s'executait bien (confirme par ps aux), mais AUCUN
# contenu n'atteignait jamais analysisd/alerts.json - ni sous la regle
# 100300, ni sous aucune autre regle (verifie par grep large sur du
# contenu distinctif du scan, aucun resultat). Cause exacte non
# confirmee avec certitude (comportement de log_format=command pas
# assez documente/verifiable dans cet environnement pour conclure sans
# deviner), donc ABANDONNE plutot que suppose corrige a l'aveugle.
#
# Remplace par un mecanisme deja PROUVE fiable ce soir : le calendrier
# natif WEF (bin/scheduler.sh/schedules.csv, teste en reel le
# 2026-09-18) execute WAZ_056_NMAP_SCAN_RUN.sh, qui ecrit dans un
# fichier log ordinaire (/var/log/wef-nmap-scan.log) - surveille par
# Wazuh en <log_format>syslog</log_format>, EXACT MEME mecanisme que
# /var/ossec/logs/active-responses.log deja visible et fonctionnel dans
# ossec.log depuis le debut de la soiree. Plus aucune dependance a un
# comportement de log_format=command non verifie.
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

LOG_FILE="/var/log/wef-nmap-scan.log"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"
chown root:wazuh "$LOG_FILE" 2>/dev/null || true

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ${OSSEC_CONF} est immuable (deja verrouille par WAZ_032) - deverrouillage temporaire avant reecriture."
  chattr -i "$OSSEC_CONF"
fi

MARKER="<!-- WEF_NMAP_SCAN_CONFIG (WAZ_055, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF"; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Bloc deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_NMAP_SCAN_CONFIG_END -->\$|d" "$OSSEC_CONF"
fi
echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Declaration de la surveillance de ${LOG_FILE} dans ossec.conf..."
{
  echo "$MARKER"
  echo "<ossec_config>"
  echo "  <localfile>"
  echo "    <log_format>syslog</log_format>"
  echo "    <location>${LOG_FILE}</location>"
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

echo "[WAZ_055_NMAP_SCAN_INTEGRATION] OK. ${LOG_FILE} est surveille ; WAZ_056_NMAP_SCAN_RUN (planifie via schedules.csv) y ecrit le resultat de chaque scan ; tout port ouvert detecte declenche la regle 100300 (recherche : rule.id : 100300)."
exit 0
