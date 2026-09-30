#!/bin/bash
# bin/sla_report.sh - Niveau de service MESURE (ITIL 4 / PMP), AJOUTE LE
# 2026-09-30 (demande explicite). Calcule un temps d'execution reel a
# partir de state/JOBS_HISTORY.csv (colonne duree_sec, deja enregistree
# par chaque execution reelle) - jamais une valeur affirmee sans preuve.
#
# LIMITE HONNETE, ecrite ici pour ne jamais etre oubliee : ceci mesure
# le temps d'EXECUTION DU SCRIPT (deploiement/configuration/pilotage),
# PAS un delai de detection bout-en-bout (ex. "temps entre le depot d'un
# fichier et l'alerte VirusTotal dans le Dashboard") - cette derniere
# mesure demanderait de correler un evenement filesystem reel a un
# evenement Wazuh reel (horodatages distincts, jamais captures
# ensemble dans ce projet a ce jour). Ne JAMAIS presenter ce rapport
# comme une "SLA de detection" - c'est une SLA de deploiement/pilotage,
# defendable telle quelle.
#
# Usage :
#   ./bin/sla_report.sh                                  -> tous les jobs avec historique
#   ./bin/sla_report.sh WAZ_050_VIRUSTOTAL_INTEGRATION    -> un seul job
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="$HERE/state/JOBS_HISTORY.csv"
FILTER_JOB="${1:-}"

if [ ! -f "$LEDGER" ]; then
  echo "Aucun historique pour l'instant (state/JOBS_HISTORY.csv absent) - rien a mesurer."
  exit 0
fi

LEDGER_FILE="$LEDGER" FILTER_JOB="$FILTER_JOB" python3 << 'PYEOF'
import os
from collections import defaultdict

ledger_file = os.environ['LEDGER_FILE']
filter_job = os.environ.get('FILTER_JOB', '')

by_job = defaultdict(list)
with open(ledger_file, encoding='utf-8') as f:
    for line in f:
        line = line.rstrip("\n")
        if not line or line.startswith("timestamp"):
            continue
        parts = line.split(",")
        if len(parts) < 6:
            continue
        job_id, duree = parts[1], parts[5]
        try:
            by_job[job_id].append(float(duree))
        except ValueError:
            continue

print("=== Temps d'execution mesure par job (state/JOBS_HISTORY.csv, donnees reelles) ===")
print("LIMITE HONNETE : mesure le temps d'EXECUTION DU SCRIPT, jamais un delai de")
print("detection bout-en-bout - voir l'en-tete de ce script pour le detail.\n")

jobs = [filter_job] if filter_job else sorted(by_job.keys())
rows = []
for job_id in jobs:
    durations = by_job.get(job_id, [])
    if not durations:
        continue
    n = len(durations)
    avg = sum(durations) / n
    rows.append((job_id, n, min(durations), avg, max(durations)))

if not rows:
    print("Aucune donnee pour ce filtre.")
else:
    print(f"{'JOB_ID':<40} {'N':>4} {'MIN(s)':>8} {'MOY(s)':>8} {'MAX(s)':>8}")
    for job_id, n, mn, avg, mx in rows:
        print(f"{job_id:<40} {n:>4} {mn:>8.1f} {avg:>8.1f} {mx:>8.1f}")
PYEOF
