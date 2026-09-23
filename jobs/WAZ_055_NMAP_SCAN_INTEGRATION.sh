#!/bin/bash
# WAZ_055_NMAP_SCAN_INTEGRATION - WEF_WAZ_RUN_NMAPSCAN - Playbook PB-009
#
# AJOUTE LE 2026-09-22 (demande explicite : "je veux qu'on ajoute nmap a
# wazuh" -> "scan periodique automatique").
#
# REFONDU TROIS FOIS LE MEME WEEK-END (incidents reels sur wef-elk-core,
# chaque fois diagnostique en profondeur avant de conclure) :
#   v1 : <localfile><log_format>command</log_format><frequency> - le
#        process nmap s'executait bien mais aucun contenu n'atteignait
#        jamais analysisd.
#   v2 : <localfile><log_format>syslog</log_format> sur fichier custom -
#        confirme via wazuh-logtest interactif : rejete des le
#        pre-decodage ("No decoder matched"), pas d'entete syslog.
#   v3 : logger -> journald - MEME echec, et surtout : le canari
#        preexistant du projet (regle 100101, meme mecanisme, en place
#        depuis le 2026-08-31) n'a JAMAIS produit d'alerte reelle non
#        plus une fois verifie (grep alerts.json -> 0), meme apres
#        chainage if_sid=1002 (rule "unknown problem" catch-all Wazuh).
#        Conclusion honnete : logcollector/journald n'est pas fiable
#        dans cet environnement precis, cause exacte non identifiee
#        avec certitude.
#
# v4 (celle-ci, definitive) : plus AUCUN <localfile>/journald. Le FIM
# (syscheck) est le SEUL mecanisme de detection externe confirme
# fonctionner ce soir (dizaines d'alertes reelles observees). Ce job se
# limite desormais a poser une regle qui CHAINE sur les evenements FIM
# deja existants (if_sid=100100,550,553,554 - meme technique deja
# prouvee par WAZ_051/regle IOC 100200) plutot que d'ajouter une
# nouvelle source de log. WAZ_056_NMAP_SCAN_RUN.sh ecrit le resultat du
# scan dans /tmp/wef-nmap-scan.log - /tmp est deja dans le perimetre FIM
# du projet (WAZ_050) - aucune configuration ossec.conf supplementaire
# requise ici.
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
fi

RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
[ -f "$RULES_FILE" ] || { echo "[WAZ_055_NMAP_SCAN_INTEGRATION] ERREUR : ${RULES_FILE} introuvable (WAZ_025 doit avoir tourne)." >&2; exit 1; }
MARKER_RULE="<!-- WEF_NMAP_SCAN_RULE (WAZ_055, genere automatiquement - ne pas editer a la main) -->"
if grep -qF "$MARKER_RULE" "$RULES_FILE"; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Regle nmap deja posee, retrait avant reecriture..."
  sed -i "\|^${MARKER_RULE//\//\\/}\$|,\|^<!-- WEF_NMAP_SCAN_RULE_END -->\$|d" "$RULES_FILE"
fi
echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Ajout de la regle de detection (id 100300, chainee sur les evenements FIM)..."
{
  echo "$MARKER_RULE"
  echo "<group name=\"nmap_scan,\">"
  echo "  <rule id=\"100300\" level=\"5\">"
  echo "    <if_sid>100100,550,553,554</if_sid>"
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

echo "[WAZ_055_NMAP_SCAN_INTEGRATION] OK. WAZ_056_NMAP_SCAN_RUN (planifie via schedules.csv) ecrit dans /tmp/wef-nmap-scan.log (deja surveille par le FIM) ; tout port ouvert detecte declenche la regle 100300 (recherche : rule.id : 100300)."
exit 0
