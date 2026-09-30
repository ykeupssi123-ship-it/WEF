#!/bin/bash
# WAZ_062_NMAP_ROGUE_DEVICE - WEF_WAZ_RUN_NMAPROGUE
#
# AJOUTE LE 2026-09-29, REVU LE 2026-09-30 - repond a l'objectif
# Architecture "Detection d'appareils intrus sur le parc reseau"
# (Securite > Detection de vulnerabilites). MEME couplage Wazuh & nmap
# que WAZ_056/WAZ_059 (jamais reinvente) : le resultat est ecrit dans un
# fichier deja surveille par le FIM, aucune regle Wazuh dediee.
#
# MECANISME : compare la liste des hotes reellement en ligne a une liste
# de reference (KNOWN_HOSTS_FILE, une IP par ligne, seedee une seule
# fois depuis KNOWN_HOSTS_LIST/vars.conf si le fichier n'existe pas
# encore). Tout hote en ligne ABSENT de la reference est ecrit dans
# ROGUE_DEVICE_LOG (/tmp, jamais /var/log).
#
# REVU LE 2026-09-30 (demande explicite : garantir la detection d'un
# telephone reel branche sur le meme reseau) - DEUX changements :
#   1. "-PR" force le ping ARP (jamais ICMP) pour la decouverte de
#      presence. Sur un segment ethernet local, l'ARP est fiable a 100%
#      et NE PEUT PAS etre bloque par un pare-feu logiciel du telephone
#      (contrairement a ICMP, souvent filtre par defaut sur iOS/Android) -
#      c'est le protocole qui permet a toute machine du segment de
#      trouver l'adresse materielle d'une autre, un telephone ne peut
#      pas s'y soustraire sans se deconnecter du reseau.
#   2. L'adresse MAC (et son constructeur, quand nmap le resout) est
#      desormais capturee et affichee pour chaque appareil non
#      repertorie - "voici l'appareil" devient concret (ex. "Apple, Inc."
#      pour un iPhone), pas seulement une adresse IP anonyme.
#
# LIMITE HONNETE : l'ARP ne fonctionne que sur le MEME segment ethernet
# local (jamais a travers un routeur) - le telephone doit donc rejoindre
# EXACTEMENT le sous-reseau NMAP_SCAN_TARGET (192.168.50.0/24 par
# defaut), pas seulement "le meme WiFi" - voir docs/GUIDE_EXPLOITATION.md
# pour la procedure de branchement reelle (pont reseau necessaire selon
# l'hyperviseur).
#
# CHOIX ASSUME, deliberement PAS automatique : un appareil detecte comme
# "intrus" n'est JAMAIS ajoute automatiquement a la liste de reference -
# ce serait blanchir silencieusement un appareil potentiellement
# malveillant a la prochaine execution. Faire entrer un nouvel appareil
# dans le reseau legitime reste une decision humaine, ajoutee a la main
# dans KNOWN_HOSTS_FILE.
#
# [PLANIFIE UNIQUEMENT via schedules.csv - jamais l'orchestrateur
# automatique, meme gate que WAZ_056]
set -uo pipefail
source "$VARS_FILE"

KNOWN_HOSTS_FILE="/etc/wef/known-hosts.txt"
ROGUE_DEVICE_LOG="/tmp/wef-rogue-device-alert.txt"
TARGET="${NMAP_SCAN_TARGET:-192.168.50.0/24}"

if ! command -v nmap &>/dev/null; then
  echo "[WAZ_062_NMAP_ROGUE_DEVICE] ERREUR : nmap absent (WAZ_055 doit avoir tourne)." >&2
  exit 1
fi

mkdir -p "$(dirname "$KNOWN_HOSTS_FILE")"
if [ ! -f "$KNOWN_HOSTS_FILE" ]; then
  echo "[WAZ_062_NMAP_ROGUE_DEVICE] Premiere execution : creation de la liste de reference (${KNOWN_HOSTS_FILE}) depuis KNOWN_HOSTS_LIST..."
  IFS=',' read -ra KNOWN_ENTRIES <<< "${KNOWN_HOSTS_LIST:?ERREUR : KNOWN_HOSTS_LIST doit etre defini dans vars.conf}"
  : > "$KNOWN_HOSTS_FILE"
  for entry in "${KNOWN_ENTRIES[@]}"; do
    entry="$(echo "$entry" | xargs)"
    [ -z "$entry" ] && continue
    echo "$entry" >> "$KNOWN_HOSTS_FILE"
  done
  echo "[WAZ_062_NMAP_ROGUE_DEVICE] $(wc -l < "$KNOWN_HOSTS_FILE") hote(s) de reference ecrit(s)."
fi

echo "[WAZ_062_NMAP_ROGUE_DEVICE] Balayage de presence (ping ARP force, -PR) sur ${TARGET}..."
RAW_OUTPUT="$(mktemp)"
nmap -sn -PR "$TARGET" -oN "$RAW_OUTPUT" 2>/dev/null

ROGUE_FOUND=0
{
  echo "--- WEF_NMAP_ROGUE_DEVICE $(date -Iseconds) ---"
  RAW_FILE="$RAW_OUTPUT" KNOWN_FILE="$KNOWN_HOSTS_FILE" python3 << 'PYEOF'
import os, re

with open(os.environ['RAW_FILE']) as f:
    text = f.read()
with open(os.environ['KNOWN_FILE']) as f:
    known = {line.strip() for line in f if line.strip()}

if 'Nmap scan report for' not in text:
    print("AVERTISSEMENT : aucun hote detecte en ligne - verifier les droits nmap (ping ARP necessite root) avant de conclure a un reseau vide.")
    print("ROGUE_FOUND=0")
    raise SystemExit(0)

# Un bloc par hote : "Nmap scan report for <ip>" suivi, plus loin, d'une
# eventuelle ligne "MAC Address: XX:XX:XX:XX:XX:XX (Constructeur)".
blocks = re.split(r'(?=Nmap scan report for )', text)
rogue_found = False
for block in blocks:
    m_ip = re.search(r'Nmap scan report for (?:\S+ )?\(?([\d.]+)\)?', block)
    if not m_ip:
        continue
    ip = m_ip.group(1)
    if ip in known:
        continue
    rogue_found = True
    m_mac = re.search(r'MAC Address: ([0-9A-Fa-f:]+)(?:\s+\((.+?)\))?', block)
    if m_mac:
        mac, vendor = m_mac.group(1), m_mac.group(2) or "constructeur inconnu"
        print(f"APPAREIL NON REPERTORIE : {ip} - MAC {mac} ({vendor}) - absent de {os.environ['KNOWN_FILE']}")
    else:
        print(f"APPAREIL NON REPERTORIE : {ip} - MAC non resolue (hote peut-etre hors du meme segment ethernet) - absent de {os.environ['KNOWN_FILE']}")
if not rogue_found:
    print("Aucun appareil non repertorie - tous les hotes en ligne figurent dans la reference.")
print("ROGUE_FOUND=1" if rogue_found else "ROGUE_FOUND=0")
PYEOF
} > /tmp/.wef_rogue_scan_result
cat /tmp/.wef_rogue_scan_result | grep -v '^ROGUE_FOUND=' >> "$ROGUE_DEVICE_LOG"
ROGUE_FOUND=0
grep -q '^ROGUE_FOUND=1' /tmp/.wef_rogue_scan_result && ROGUE_FOUND=1
rm -f "$RAW_OUTPUT" /tmp/.wef_rogue_scan_result

if [ "$ROGUE_FOUND" -eq 1 ]; then
  echo "[WAZ_062_NMAP_ROGUE_DEVICE] AU MOINS UN APPAREIL NON REPERTORIE detecte - voir ${ROGUE_DEVICE_LOG} (deja surveille par le FIM)."
else
  echo "[WAZ_062_NMAP_ROGUE_DEVICE] OK. Aucun appareil non repertorie sur ${TARGET}."
fi
exit 0
