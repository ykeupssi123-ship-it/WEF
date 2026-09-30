#!/bin/bash
# WAZ_059_NMAP_VULN_ADVISORY - WEF_WAZ_RUN_NMAPVULNADV
#
# AJOUTE LE 2026-09-29, REVU LE 2026-09-30 - repond a l'objectif "Alerte
# de mise a niveau recommandee par l'editeur" (feuille Architecture,
# Securite > Detection de vulnerabilites) : ne se contente pas de dire
# QUELS ports/services sont exposes (deja fait par WAZ_056), dit aussi
# SI la version detectee est associee a une vulnerabilite (CVE) deja
# publiee - et desormais l'affiche de maniere IMMEDIATEMENT lisible
# ("service X, version Y -> CVE-XXXX, score Z"), pas seulement dans le
# texte brut de nmap.
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
# REVU LE 2026-09-30 (demande explicite : aller au bout de ce que nmap
# permet, sans aucune dependance externe type MECM - nmap detecte tout
# lui-meme, en boite noire reseau, jamais un inventaire logiciel cote
# agent) : detection de version renforcee (--version-intensity 9, la
# plus agressive - plus de sondes, bien meilleure precision de la
# chaine de version, condition necessaire pour que vulners trouve une
# correspondance CVE fiable). Un second bloc, apres le rapport brut
# nmap, EXTRAIT et reformate lisiblement chaque correspondance trouvee
# ("SERVICE VERSION -> CVE-XXXX (score CVSS)") - jamais une deuxieme
# source de verite, uniquement une lecture plus claire du meme resultat.
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

echo "[WAZ_059_NMAP_VULN_ADVISORY] Scan de vulnerabilites (vulners, detection de version maximale) sur ${NMAP_TARGET} - necessite une sortie Internet reelle depuis cette machine..."
RAW_OUTPUT="$(mktemp)"
nmap -sV --version-intensity 9 --script vulners -oN "$RAW_OUTPUT" "$NMAP_TARGET" 2>/dev/null

{
  echo "--- WEF_NMAP_VULN_ADVISORY $(date -Iseconds) ---"
  cat "$RAW_OUTPUT"
} >> "$ADVISORY_LOG"

echo "[WAZ_059_NMAP_VULN_ADVISORY] Extraction du resume lisible (logiciel -> CVE)..."
RAW_FILE="$RAW_OUTPUT" python3 << 'PYEOF' >> "$ADVISORY_LOG"
import os, re

raw_file = os.environ['RAW_FILE']
with open(raw_file) as f:
    lines = f.readlines()

current_host = None
current_service = None
findings = []
cve_re = re.compile(r'^\s*(CVE-\d{4}-\d+)\s+([\d.]+)')
service_re = re.compile(r'^\d+/tcp\s+open\s+(\S+)\s+(.*)$')
host_re = re.compile(r'^Nmap scan report for (\S+)')

for line in lines:
    m = host_re.match(line)
    if m:
        current_host = m.group(1)
        continue
    m = service_re.match(line)
    if m:
        current_service = f"{m.group(1)} ({m.group(2).strip()})" if m.group(2).strip() else m.group(1)
        continue
    m = cve_re.match(line)
    if m and current_service:
        findings.append((current_host or "?", current_service, m.group(1), m.group(2)))

print("--- RESUME LISIBLE (logiciel a mettre a niveau -> CVE) ---")
if not findings:
    print("Aucune correspondance CVE trouvee dans ce scan (service a jour, OU aucun acces Internet reel depuis cette machine - voir limite honnete en tete de job).")
else:
    findings.sort(key=lambda x: float(x[3]), reverse=True)
    for host, service, cve, score in findings:
        urgence = "CRITIQUE" if float(score) >= 9.0 else ("ELEVE" if float(score) >= 7.0 else "MOYEN")
        print(f"[{urgence}] {host} - {service} -> {cve} (score CVSS {score}) - mise a niveau recommandee par l'editeur")
    print(f"TOTAL={len(findings)} correspondance(s) CVE")
PYEOF

rm -f "$RAW_OUTPUT"

if ! grep -qE "CVE-|NOT VULNERABLE" "$ADVISORY_LOG"; then
  echo "[WAZ_059_NMAP_VULN_ADVISORY] AVERTISSEMENT : aucun resultat vulners dans le rapport - verifier que VM1 a bien un acces reseau sortant vers vulners.com avant de considerer ce resultat comme fiable." >&2
fi

echo "[WAZ_059_NMAP_VULN_ADVISORY] OK. Resultat + resume lisible ajoutes a ${ADVISORY_LOG} (surveille par le FIM, meme perimetre que WAZ_056)."
exit 0
