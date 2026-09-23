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
# resultat du scan dans /tmp/wef-nmap-scan-result.txt (voir aussi le
# correctif du 2026-09-23 plus bas : jamais ".log", exclu par defaut) -
# /tmp est deja surveille en temps reel par WAZ_050 (perimetre FIM du
# projet) : chaque modification declenche une vraie alerte FIM (rule
# 550/554), directement filtrable dans le dashboard via syscheck.path -
# voir WAZ_055 (v5) pour la conclusion finale (regle custom abandonnee).
#
# Effet de bord neutre, attendu et sans consequence : ce fichier sera
# aussi automatiquement soumis a VirusTotal par l'integration existante
# (WAZ_050) - resultat "aucun positif" (texte brut), jamais un souci.
#
# CORRIGE LE 2026-09-23 (incident reel, cause FINALE et confirmee, apres
# tout le reste ci-dessus) : le FIM ignore par defaut tout fichier se
# terminant par ".log" - regle vendor deja presente dans ossec.conf
# ("<ignore type=\"sregex\">.log$|.swp$</ignore>", jamais ajoutee par ce
# projet). "wef-nmap-scan.log" matchait exactement cette exclusion -
# aucun rapport avec nmap, le chainage de regle, ou les redemarrages :
# juste un nom de fichier malheureux. Confirme en reel : un fichier
# ".txt" identique, meme contenu, meme dossier, est detecte
# INSTANTANEMENT (rule 554). Renomme en ".txt".
set -uo pipefail
source "$VARS_FILE"

NMAP_TARGET="${NMAP_SCAN_TARGET:-192.168.50.0/24}"
SCAN_LOG="/tmp/wef-nmap-scan-result.txt"

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
