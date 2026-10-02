# lib/consumers_for_variable.py - AJOUTE LE 2026-10-02, pour bin/replay_for_variable.sh.
#
# Reutilise EXACTEMENT la meme recherche reelle que vars_pilotage_analysis.py
# (meme pattern grep \$\{?NOM\b, memes repertoires source, meme lecture de
# jobs_table.csv) - jamais une deuxieme implementation qui pourrait diverger
# de l'analyse deja affichee dans le tableur. Ajoute ce que l'analyse du
# tableur n'avait pas besoin de faire : trier le sous-ensemble de jobs
# trouves dans un ORDRE DE DEPENDANCE REEL (tri topologique sur IN_COND/
# OUT_COND, restreint a ce sous-ensemble), pour qu'un rejeu automatique ne
# joue jamais un job avant celui dont il depend reellement.
#
# Usage :
#   python3 lib/consumers_for_variable.py NOM_VARIABLE
#     -> imprime les JOB_ID trouves, UN PAR LIGNE, dans un ordre de
#        dependance sur VERAI (jamais juste l'ordre alphabetique des
#        fichiers). Code de sortie 0.
#   Rien trouve dans le systeme de jobs (variable consommee uniquement
#        hors jobs/, cf OUTSIDE_JOB_CONSUMERS de vars_pilotage_analysis.py,
#        ou variable non consommee du tout) -> rien sur stdout, code de
#        sortie 2 (distinct de 1, reserve aux vraies erreurs - jamais
#        confondu avec "variable inconnue").
#   Cycle de dependance detecte dans le sous-ensemble (ne devrait jamais
#        arriver si jobs_table.csv est sain, mais jamais suppose) ->
#        message d'erreur explicite sur stderr listant les jobs impliques,
#        code de sortie 1.
import csv
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SEARCH_DIRS = ["jobs/*.sh", "jobs/lib/*.sh", "bin/*.sh", "setup/*.sh", "lib/*.sh"]
SEARCH_SINGLE = ["orchestrator.sh"]


def _load_source_files():
    files = {}
    for pattern in SEARCH_DIRS:
        for fp in glob.glob(os.path.join(ROOT, pattern)):
            with open(fp, encoding="utf-8", errors="ignore") as f:
                files[os.path.relpath(fp, ROOT)] = f.read()
    for fp in SEARCH_SINGLE:
        full = os.path.join(ROOT, fp)
        if os.path.exists(full):
            with open(full, encoding="utf-8", errors="ignore") as f:
                files[fp] = f.read()
    return files


def _parse_jobs_table():
    """jobid_by_script, et in_cond/out_cond REELS par JOB_ID (jamais
    devines) - directement depuis jobs_table.csv, memes 8 colonnes que
    partout ailleurs dans ce projet."""
    path = os.path.join(ROOT, "jobs_table.csv")
    jobid_by_script = {}
    in_cond_by_job = {}
    out_cond_by_job = {}
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            jobid_by_script[row["SCRIPT_FILE"]] = row["JOB_ID"]
            in_cond_by_job[row["JOB_ID"]] = row["IN_COND"]
            out_cond_by_job[row["JOB_ID"]] = row["OUT_COND"]
    return jobid_by_script, in_cond_by_job, out_cond_by_job


def find_consumer_jobs(name):
    """Meme recherche reelle que vars_pilotage_analysis.py : grep du nom de
    variable dans le code source reel, puis association script->JOB_ID."""
    pattern = re.compile(r'\$\{?' + re.escape(name) + r'\b')
    source_files = _load_source_files()
    jobid_by_script, in_cond_by_job, out_cond_by_job = _parse_jobs_table()
    referencing = [fn for fn, txt in source_files.items() if pattern.search(txt)]
    job_hits = [fn for fn in referencing if os.path.basename(fn) in jobid_by_script]
    jobids = sorted({jobid_by_script[os.path.basename(fn)] for fn in job_hits})
    return jobids, in_cond_by_job, out_cond_by_job


def topological_order(jobids, in_cond_by_job, out_cond_by_job):
    """Tri topologique REEL du sous-ensemble jobids, restreint aux
    dependances INTERNES a ce sous-ensemble (une IN_COND satisfaite par un
    job HORS du sous-ensemble est ignoree ici - elle est, par construction,
    deja satisfaite dans l'etat normal du systeme, jamais la responsabilite
    de ce rejeu cible). Kahn's algorithm, ordre stable (alphabetique) entre
    jobs sans relation de dependance entre eux, pour un resultat
    reproductible. Leve ValueError si un cycle existe dans ce sous-ensemble
    (jamais un ordre partiel silencieux)."""
    jobids_set = set(jobids)
    # out_cond -> job qui la produit, restreint au sous-ensemble
    producer_of = {}
    for j in jobids:
        oc = out_cond_by_job.get(j, "NONE")
        if oc and oc != "NONE":
            producer_of[oc] = j

    deps = {j: set() for j in jobids}  # j depend de deps[j] (jobs du sous-ensemble)
    for j in jobids:
        ic = in_cond_by_job.get(j, "NONE")
        if not ic or ic == "NONE":
            continue
        for cond in ic.split("|"):
            producer = producer_of.get(cond)
            if producer and producer in jobids_set and producer != j:
                deps[j].add(producer)

    ordered = []
    remaining = set(jobids)
    while remaining:
        ready = sorted(j for j in remaining if deps[j] <= set(ordered))
        if not ready:
            cyclic = sorted(remaining)
            raise ValueError("Cycle de dependance detecte parmi : " + ", ".join(cyclic))
        ordered.extend(ready)
        remaining -= set(ready)
    return ordered


def main():
    if len(sys.argv) != 2:
        print("Usage: consumers_for_variable.py NOM_VARIABLE", file=sys.stderr)
        sys.exit(1)
    name = sys.argv[1]
    jobids, in_cond_by_job, out_cond_by_job = find_consumer_jobs(name)
    if not jobids:
        sys.exit(2)
    try:
        ordered = topological_order(jobids, in_cond_by_job, out_cond_by_job)
    except ValueError as e:
        print("ERREUR: " + str(e), file=sys.stderr)
        sys.exit(1)
    for j in ordered:
        print(j)


if __name__ == "__main__":
    main()
