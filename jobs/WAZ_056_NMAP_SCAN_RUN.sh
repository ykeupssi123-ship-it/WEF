#!/bin/bash
# WAZ_056_NMAP_SCAN_RUN - WEF_WAZ_RUN_NMAPSCANRUN
#
# AJOUTE LE 2026-09-22, en meme temps que la refonte de
# WAZ_055_NMAP_SCAN_INTEGRATION.sh (voir son en-tete pour le detail
# complet du changement d'approche). Ce job execute le scan nmap
# lui-meme et ecrit son resultat dans /var/log/wef-nmap-scan.log,
# surveille par Wazuh (installe par WAZ_055). Declenche par le
# calendrier natif WEF (schedules.csv), jamais par le mecanisme
# log_format=command de Wazuh (abandonne le meme jour - voir WAZ_055).
#
# OUT_COND=NONE (comme tout job planifie du projet, ex. WAZ_053/WAG_010) :
# ce job n'alimente jamais le graphe de dependances, jamais bloquant/
# bloque par un .ok - sa cadence reelle vit entierement dans
# schedules.csv, jamais dans l'etat de dependances.
set -uo pipefail
source "$VARS_FILE"

NMAP_TARGET="${NMAP_SCAN_TARGET:-192.168.50.0/24}"
LOG_FILE="/var/log/wef-nmap-scan.log"

if ! command -v nmap &>/dev/null; then
  echo "[WAZ_056_NMAP_SCAN_RUN] ERREUR : nmap absent (WAZ_055 doit avoir tourne)." >&2
  exit 1
fi
[ -f "$LOG_FILE" ] || { echo "[WAZ_056_NMAP_SCAN_RUN] ERREUR : ${LOG_FILE} introuvable (WAZ_055 doit avoir tourne)." >&2; exit 1; }

echo "[WAZ_056_NMAP_SCAN_RUN] Scan de ${NMAP_TARGET}..."
{
  echo "WEF_NMAP_SCAN $(date -Iseconds)"
  nmap -sV -oG - "$NMAP_TARGET" 2>/dev/null
} >> "$LOG_FILE"

echo "[WAZ_056_NMAP_SCAN_RUN] OK. Resultat ecrit dans ${LOG_FILE}."
exit 0
