#!/bin/bash
# bin/incidents.sh - Registre d'Incidents (ITIL 4 Incident Management),
# AJOUTE LE 2026-09-30 (demande explicite). Distinct du Journal des
# Problemes (docs/JOURNAL_TECHNIQUE.md, qui documente la CAUSE RACINE
# d'un dysfonctionnement) : un Incident est le SYMPTOME - une execution
# en echec, avec sa duree de resolution REELLE, mesuree, jamais devinee.
#
# MECANISME : derive ENTIEREMENT de state/JOBS_HISTORY.csv - jamais une
# deuxieme source de verite saisie a la main (meme discipline que le
# resume CVE de WAZ_059 : une relecture plus claire d'une donnee deja
# reelle, jamais un doublon). Pour chaque ECHEC/FORCE_ECHEC/
# SCHEDULED_ECHEC, cherche la PROCHAINE execution reussie du MEME job
# dans l'historique -> l'ecart de temps EST la duree de resolution.
# Aucune reussite ulterieure trouvee : incident encore OUVERT.
#
# Severite CALCULEE, jamais devinee : nombre de jobs dont l'IN_COND
# depend reellement du OUT_COND de ce job (meme calcul de "rayon
# d'impact" deja utilise par bin/order.sh, jamais duplique a la main -
# relu directement depuis jobs_table.csv) - P1 si 3 jobs ou plus en
# dependent, P2 si 1 ou 2, P3 si le job est isole.
#
# Usage :
#   ./bin/incidents.sh              -> tous les jobs
#   ./bin/incidents.sh WAZ_050_VIRUSTOTAL_INTEGRATION   -> un seul job
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="$HERE/state/JOBS_HISTORY.csv"
JOBS_TABLE="$HERE/jobs_table.csv"
OUT_FILE="$HERE/state/INCIDENTS.csv"
FILTER_JOB="${1:-}"

if [ ! -f "$LEDGER" ]; then
  echo "Aucun historique pour l'instant (state/JOBS_HISTORY.csv absent) - rien a deriver."
  exit 0
fi

LEDGER_FILE="$LEDGER" JOBS_TABLE_FILE="$JOBS_TABLE" OUT_FILE="$OUT_FILE" FILTER_JOB="$FILTER_JOB" python3 << 'PYEOF'
import csv, os, datetime

ledger_file = os.environ['LEDGER_FILE']
jobs_table_file = os.environ['JOBS_TABLE_FILE']
out_file = os.environ['OUT_FILE']
filter_job = os.environ.get('FILTER_JOB', '')

outcond_by_job = {}
with open(jobs_table_file, encoding='utf-8') as f:
    reader = csv.reader(f)
    next(reader)
    rows = [r for r in reader if len(r) >= 8]
for row in rows:
    outcond_by_job[row[0]] = row[7]

consumers_count = {}
for row in rows:
    in_cond = row[6]
    if in_cond and in_cond != "NONE":
        needed = set(in_cond.split("|"))
        for job_id, out_cond in outcond_by_job.items():
            if out_cond in needed:
                consumers_count[job_id] = consumers_count.get(job_id, 0) + 1

def severity(job_id):
    n = consumers_count.get(job_id, 0)
    if n >= 3:
        return "P1"
    if n >= 1:
        return "P2"
    return "P3"

FAIL_LABELS = {"ECHEC", "FORCE_ECHEC", "SCHEDULED_ECHEC"}
OK_LABELS = {"OK", "FORCE_OK", "SCHEDULED_OK"}

executions = []
with open(ledger_file, encoding='utf-8') as f:
    for line in f:
        line = line.rstrip("\n")
        if not line or line.startswith("timestamp"):
            continue
        parts = line.split(",")
        if len(parts) < 6:
            continue
        executions.append(tuple(parts[:6]))

incidents = []
for i, (ts, job_id, job_name, result, log_path, duree) in enumerate(executions):
    if filter_job and job_id != filter_job:
        continue
    if result not in FAIL_LABELS:
        continue
    resolved_ts = None
    for ts2, job_id2, job_name2, result2, log_path2, duree2 in executions[i + 1:]:
        if job_id2 == job_id and result2 in OK_LABELS:
            resolved_ts = ts2
            break
    statut = "RESOLU" if resolved_ts else "OUVERT"
    duree_resolution = ""
    if resolved_ts:
        try:
            t1 = datetime.datetime.fromisoformat(ts)
            t2 = datetime.datetime.fromisoformat(resolved_ts)
            duree_resolution = str(int((t2 - t1).total_seconds()))
        except ValueError:
            duree_resolution = ""
    incidents.append([f"INC-{len(incidents) + 1:04d}", ts, job_id, job_name, result,
                       severity(job_id), statut, resolved_ts or "", duree_resolution, log_path])

with open(out_file, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["incident_id", "detecte_le", "job_id", "job_name", "type_echec", "severite",
                "statut", "resolu_le", "duree_resolution_sec", "log"])
    w.writerows(incidents)

print(f"[incidents] {len(incidents)} incident(s) derive(s) de l'historique reel -> {out_file}")
open_count = sum(1 for inc in incidents if inc[6] == "OUVERT")
p1_count = sum(1 for inc in incidents if inc[5] == "P1")
print(f"[incidents] dont {open_count} encore OUVERT(S) (aucune reussite ulterieure du meme job dans l'historique).")
print(f"[incidents] dont {p1_count} de severite P1 (3 jobs ou plus en dependent).")
PYEOF
