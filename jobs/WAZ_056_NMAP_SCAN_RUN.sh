#!/bin/bash
# WAZ_056_NMAP_SCAN_RUN - WEF_WAZ_RUN_NMAPSCANRUN
#
# AJOUTE LE 2026-09-22, refondu deux fois le meme jour (voir WAZ_055
# pour le detail complet des deux versions abandonnees : v1
# log_format=command, v2 log_format=syslog sur fichier custom).
#
# CORRIGE LE 2026-09-23 (troisieme et derniere refonte, incident reel
# confirme en profondeur sur wef-elk-core) : meme le canari existant
# (regle 100101, via logger/journald, en place depuis le 2026-08-31)
# n'a JAMAIS produit d'alerte reelle une fois verifie (grep alerts.json
# -> 0, meme apres reparation de local_rules.xml et ajout d'un
# chainage if_sid=1002). Conclusion honnete : la voie logcollector/
# journald n'est pas fiable dans cet environnement precis, cause exacte
# non identifiee avec certitude malgre un diagnostic approfondi -
# abandonnee plutot que contournee a l'aveugle.
#
# Remplace par le FIM (syscheck) - le SEUL mecanisme de detection
# externe reellement confirme fonctionner ce soir (dizaines d'alertes
# reelles rule 550/554 observees en direct). Ce job ecrit desormais le
# resultat du scan dans /tmp/wef-nmap-scan.log - /tmp est deja surveille
# en temps reel par WAZ_050 (perimetre FIM du projet) : chaque
# modification declenche une vraie alerte FIM, que WAZ_055 chaine
# dessus (if_sid=100100,550,553,554, meme technique deja prouvee par
# WAZ_051/regle IOC 100200).
#
# Effet de bord neutre, attendu et sans consequence : ce fichier sera
# aussi automatiquement soumis a VirusTotal par l'integration existante
# (WAZ_050) - resultat "aucun positif" (texte brut), jamais un souci.
set -uo pipefail
source "$VARS_FILE"

NMAP_TARGET="${NMAP_SCAN_TARGET:-192.168.50.0/24}"
SCAN_LOG="/tmp/wef-nmap-scan.log"

if ! command -v nmap &>/dev/null; then
  echo "[WAZ_056_NMAP_SCAN_RUN] ERREUR : nmap absent (WAZ_055 doit avoir tourne)." >&2
  exit 1
fi

echo "[WAZ_056_NMAP_SCAN_RUN] Scan de ${NMAP_TARGET}..."
{
  echo "--- WEF_NMAP_SCAN $(date -Iseconds) ---"
  nmap -sV -oG - "$NMAP_TARGET" 2>/dev/null
} >> "$SCAN_LOG"

echo "[WAZ_056_NMAP_SCAN_RUN] OK. Resultat ajoute a ${SCAN_LOG} (surveille par le FIM, voir WAZ_055 pour la regle de detection)."
exit 0
