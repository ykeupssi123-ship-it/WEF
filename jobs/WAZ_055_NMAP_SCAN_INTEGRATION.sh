#!/bin/bash
# WAZ_055_NMAP_SCAN_INTEGRATION - WEF_WAZ_RUN_NMAPSCAN - Playbook PB-009
#
# AJOUTE LE 2026-09-22 (demande explicite : "je veux qu'on ajoute nmap a
# wazuh" -> "scan periodique automatique").
#
# REFONDU DEUX FOIS LE MEME JOUR (incidents reels sur wef-elk-core,
# chaque fois diagnostique avant de conclure, jamais suppose corrige) :
# v1 <localfile><log_format>command</log_format><frequency> - le
# process nmap s'executait bien mais aucun contenu n'atteignait
# analysisd (cause non confirmee). v2 <localfile><log_format>syslog</log_format>
# sur un fichier custom - confirme via wazuh-logtest EN MODE INTERACTIF
# que Wazuh rejette la ligne des le pre-decodage ("No decoder matched",
# jamais de Phase 3) : une ligne nmap brute n'a pas l'entete syslog
# standard attendu par ce format.
#
# v3 (celle-ci) : plus AUCUN <localfile> necessaire. WAZ_056_NMAP_SCAN_RUN.sh
# (execute par bin/scheduler.sh via schedules.csv) envoie chaque ligne
# de resultat via "logger -t wef-nmap-scan <ligne>" - le MEME mecanisme
# deja prouve fiable toute la soiree par le canari (regle 100101,
# WAZ_041_ALERT_CANARY.sh) : logger ecrit dans le vrai syslog systeme,
# avec un entete correct, deja surveille et decode par Wazuh par
# defaut - aucune configuration supplementaire requise. Ce job se
# limite donc desormais a poser la regle de detection (id 100300).
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

OSSEC_CONF="/var/ossec/etc/ossec.conf"
[ -f "$OSSEC_CONF" ] || { echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : ${OSSEC_CONF} introuvable." >&2; exit 1; }

# Nettoyage du bloc <localfile> pose par les versions v1/v2 abandonnees
# (idempotent - ne fait rien si absent, jamais suppose deja propre).
MARKER="<!-- WEF_NMAP_SCAN_CONFIG (WAZ_055, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER" "$OSSEC_CONF" 2>/dev/null; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Retrait du bloc <localfile> des versions precedentes (plus necessaire, voir en-tete)..."
  if lsattr "$OSSEC_CONF" 2>/dev/null | grep -q '^....i'; then
    chattr -i "$OSSEC_CONF"
  fi
  sed -i "\|^${MARKER//\//\\/}\$|,\|^<!-- WEF_NMAP_SCAN_CONFIG_END -->\$|d" "$OSSEC_CONF"
  chown root:wazuh "$OSSEC_CONF"
  chmod 640 "$OSSEC_CONF"
  chattr +i "$OSSEC_CONF"
  RESTART_NEEDED=1
else
  RESTART_NEEDED=0
fi

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

echo "[WAZ_055_NMAP_SCAN_INTEGRATION] OK. WAZ_056_NMAP_SCAN_RUN (planifie via schedules.csv) envoie chaque ligne de scan via logger -t wef-nmap-scan ; tout port ouvert detecte declenche la regle 100300 (recherche : rule.id : 100300)."
exit 0
