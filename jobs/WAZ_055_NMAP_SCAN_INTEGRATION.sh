#!/bin/bash
# WAZ_055_NMAP_SCAN_INTEGRATION - WEF_WAZ_RUN_NMAPSCAN - Playbook PB-009
#
# AJOUTE LE 2026-09-22 (demande explicite : "je veux qu'on ajoute nmap a
# wazuh" -> "scan periodique automatique").
#
# REFONDU CINQ FOIS ENTRE LE 2026-09-22 ET LE 2026-09-23 (chaque version
# testee en reel avant d'etre abandonnee - jamais suppose corrige a
# l'aveugle) : v1 <localfile><log_format>command</log_format> - contenu
# jamais livre a analysisd. v2 <localfile><log_format>syslog</log_format>
# sur fichier custom - rejete au pre-decodage (pas d'entete syslog). v3
# logger/journald - meme echec, et le canari preexistant du projet
# (regle 100101) s'est avere n'avoir JAMAIS fonctionne non plus une fois
# verifie. v4 regle custom (id 100300) chainee sur if_sid=100100,550,
# 553,554 (meme technique que WAZ_051/regle 100200) - la regle se
# chargeait correctement, le FIM detectait bien le fichier (une fois le
# probleme separe du nom ".log" exclu par defaut corrige), mais la
# regle 100300 elle-meme n'a JAMAIS declenche. Verification poussee :
# la regle 100100 (la toute premiere regle custom du projet, creee le
# 2026-09-03) et la regle 100200 (WAZ_051) n'ont EGALEMENT jamais
# declenche historiquement - le chainage if_sid sur des evenements FIM
# ne fonctionne pas de maniere fiable sur cette installation, pour une
# cause non identifiee avec certitude malgre un diagnostic exhaustif.
#
# v5 (celle-ci, definitive et pragmatique) : abandon complet de toute
# regle custom pour ce besoin. La regle VENDOR standard 550/554 (FIM,
# deja fiable a 100% toute la soiree) porte deja le contenu complet du
# scan (syscheck.diff). Filtrage dans le dashboard directement sur
# syscheck.path, jamais besoin d'un rule_id dedie. Ce job se limite
# desormais a installer nmap - plus aucune configuration Wazuh.
set -uo pipefail
source "$VARS_FILE"

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
else
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] nmap deja installe."
fi

# Nettoyage de la regle 100300 posee par la v4 abandonnee (jamais
# fonctionnelle - voir en-tete) - idempotent, ne fait rien si absente.
RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
MARKER_RULE="<!-- WEF_NMAP_SCAN_RULE (WAZ_055, genere automatiquement - ne pas editer a la main) -->"
if [ -f "$RULES_FILE" ] && grep -qF "$MARKER_RULE" "$RULES_FILE" 2>/dev/null; then
  echo "[WAZ_055_NMAP_SCAN_INTEGRATION] Retrait de la regle 100300 (v4 abandonnee, jamais fonctionnelle - voir en-tete)..."
  WAS_IMMUTABLE=0
  if lsattr "$RULES_FILE" 2>/dev/null | grep -q '^....i'; then
    chattr -i "$RULES_FILE"
    WAS_IMMUTABLE=1
  fi
  sed -i "\|^${MARKER_RULE//\//\\/}\$|,\|^<!-- WEF_NMAP_SCAN_RULE_END -->\$|d" "$RULES_FILE"
  [ "$WAS_IMMUTABLE" -eq 1 ] && chattr +i "$RULES_FILE"
  systemctl restart wazuh-manager
fi

echo "[WAZ_055_NMAP_SCAN_INTEGRATION] OK. WAZ_056_NMAP_SCAN_RUN (planifie via schedules.csv) ecrit dans /tmp/wef-nmap-scan-result.txt (deja surveille par le FIM, WAZ_050) ; dashboard : filtrer syscheck.path : \"/tmp/wef-nmap-scan-result.txt\" (retirer tout filtre rule.level qui exclurait le niveau 7)."
exit 0
