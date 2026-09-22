#!/bin/bash
# WAZ_056_NMAP_SCAN_RUN - WEF_WAZ_RUN_NMAPSCANRUN
#
# AJOUTE LE 2026-09-22, refonte le meme jour (voir WAZ_055 pour le detail
# de la premiere version abandonnee, basee sur <localfile><frequency>).
#
# CORRIGE LE 2026-09-22 (meme jour, second incident reel confirme via
# wazuh-logtest EN MODE INTERACTIF - jamais concluant en mode pipe, donc
# refait proprement avant de conclure) : la premiere version de ce
# correctif ecrivait dans un fichier /var/log/wef-nmap-scan.log brut,
# surveille par Wazuh en <log_format>syslog</log_format>. Constate :
# "Phase 2: No decoder matched" pour CHAQUE ligne, jamais de Phase 3 -
# une ligne nmap brute n'a pas l'entete syslog standard (horodatage/
# hote/processus) que ce format attend, donc rejetee au pre-decodage
# avant meme d'atteindre l'evaluation des regles. A l'inverse, le
# canari (regle 100101, WAZ_041_ALERT_CANARY.sh) fonctionne de maniere
# fiable et prouvee toute la soiree via "logger -t <tag> <message>" -
# ecrit dans le VRAI syslog systeme, avec un entete correct que Wazuh
# decode deja. Reutilise ce meme mecanisme, jamais un fichier custom :
# chaque ligne de sortie nmap est passee a logger individuellement.
set -uo pipefail
source "$VARS_FILE"

NMAP_TARGET="${NMAP_SCAN_TARGET:-192.168.50.0/24}"

if ! command -v nmap &>/dev/null; then
  echo "[WAZ_056_NMAP_SCAN_RUN] ERREUR : nmap absent (WAZ_055 doit avoir tourne)." >&2
  exit 1
fi

echo "[WAZ_056_NMAP_SCAN_RUN] Scan de ${NMAP_TARGET}..."
LINE_COUNT=0
while IFS= read -r LINE; do
  [ -z "$LINE" ] && continue
  logger -t wef-nmap-scan "$LINE"
  LINE_COUNT=$((LINE_COUNT+1))
done < <(nmap -sV -oG - "$NMAP_TARGET" 2>/dev/null)

echo "[WAZ_056_NMAP_SCAN_RUN] OK. ${LINE_COUNT} ligne(s) de resultat envoyee(s) via logger (tag wef-nmap-scan)."
exit 0
