#!/bin/bash
# WAZ_059_NMAP_VULN_ADVISORY - WEF_WAZ_RUN_NMAPVULNADV
#
# AJOUTE LE 2026-09-29 - repond a l'objectif "Alerte de mise a niveau
# recommandee par l'editeur" (feuille Architecture, Securite > Detection
# de vulnerabilites) : ne se contente pas de dire QUELS ports/services
# sont exposes (deja fait par WAZ_056), dit aussi SI la version detectee
# est associee a une vulnerabilite (CVE) deja publiee.
#
# MECANISME - meme discipline exacte que WAZ_056 (jamais reinventee) :
# le script NSE "vulners" (fourni en standard avec nmap, aucune base de
# donnees a installer separement) croise la version de service detectee
# avec la base publique vulners.com et liste les CVE correspondants.
# Le resultat est ecrit dans un fichier .txt (JAMAIS .log - exclusion
# vendor deja documentee dans WAZ_056) sous /tmp, deja surveille en
# temps reel par le FIM (perimetre pose par WAZ_050) : aucune regle
# Wazuh dediee, aucune configuration FIM supplementaire - exactement le
# meme couplage Wazuh & nmap deja prouve pour WAZ_056.
#
# LIMITE HONNETE, non contournee : le script "vulners" interroge une API
# EXTERNE (vulners.com) - si VM1 (192.168.50.128) n'a aucune route vers
# Internet (reseau de laboratoire ferme), nmap termine sans erreur mais
# le rapport ne contient alors AUCUN CVE (silence, jamais un crash) :
# verifier une connectivite sortante reelle avant de conclure a
# l'absence de vulnerabilite. Jamais teste en reel au moment de l'ecriture
# de ce job (aucun acces direct a VM1/VM2 dans cette session) - a
# verifier des le premier lancement reel avant de faire confiance a son
# resultat pour une soutenance ou un audit.
#
# Jamais une installation automatique de correctif : ce job SIGNALE
# uniquement - la decision de mettre a jour reste humaine.
set -uo pipefail
source "$VARS_FILE"

NMAP_TARGET="${NMAP_SCAN_TARGET:-192.168.50.0/24}"
ADVISORY_LOG="/tmp/wef-nmap-vuln-advisory.txt"

if ! command -v nmap &>/dev/null; then
  echo "[WAZ_059_NMAP_VULN_ADVISORY] ERREUR : nmap absent (WAZ_055 doit avoir tourne)." >&2
  exit 1
fi

if ! nmap --script-help vulners &>/dev/null; then
  echo "[WAZ_059_NMAP_VULN_ADVISORY] ERREUR : le script NSE 'vulners' est introuvable dans cette installation de nmap (version trop ancienne ?)." >&2
  exit 1
fi

echo "[WAZ_059_NMAP_VULN_ADVISORY] Scan de vulnerabilites (vulners) sur ${NMAP_TARGET} - necessite une sortie Internet reelle depuis cette machine..."
{
  echo "--- WEF_NMAP_VULN_ADVISORY $(date -Iseconds) ---"
  nmap -sV --script vulners -oN - "$NMAP_TARGET" 2>/dev/null
} >> "$ADVISORY_LOG"

if ! grep -qE "CVE-|NOT VULNERABLE" "$ADVISORY_LOG"; then
  echo "[WAZ_059_NMAP_VULN_ADVISORY] AVERTISSEMENT : aucun resultat vulners dans le rapport - verifier que VM1 a bien un acces reseau sortant vers vulners.com avant de considerer ce resultat comme fiable." >&2
fi

echo "[WAZ_059_NMAP_VULN_ADVISORY] OK. Resultat ajoute a ${ADVISORY_LOG} (surveille par le FIM, meme perimetre que WAZ_056)."
exit 0
