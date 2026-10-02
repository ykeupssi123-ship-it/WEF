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
#   STATE_DIR=... python3 lib/consumers_for_variable.py NOM_VARIABLE
#     -> imprime une ligne par JOB_ID trouve, dans l'ordre de dependance
#        REEL (jamais juste l'ordre alphabetique des fichiers), au format
#        "JOB_ID<TAB>COND_MANQUANTE1,COND_MANQUANTE2" (deuxieme champ vide
#        si rien ne manque). Code de sortie 0.
#   Rien trouve dans le systeme de jobs (variable consommee uniquement
#        hors jobs/, cf OUTSIDE_JOB_CONSUMERS de vars_pilotage_analysis.py,
#        ou variable non consommee du tout) -> rien sur stdout, code de
#        sortie 2 (distinct de 1, reserve aux vraies erreurs - jamais
#        confondu avec "variable inconnue").
#   Cycle de dependance detecte dans le sous-ensemble (ne devrait jamais
#        arriver si jobs_table.csv est sain, mais jamais suppose) ->
#        message d'erreur explicite sur stderr listant les jobs impliques,
#        code de sortie 1.
#
# AJOUTE LE 2026-10-02 (incident reel : WAZ_035B_CUT_INDEXER_TO_ES rejoue
# seul via ce lot a echoue, parce que sa vraie precondition
# WAZ_PIPELINE_ELK_ACTIVE n'est produite que par WAZ_035C_REROUTE_
# PIPELINE_ES - un job qui ne consomme meme pas la variable rejouee, donc
# totalement hors du lot). Le tri topologique ne protegeait QUE contre les
# dependances INTERNES au lot - jamais contre une precondition EXTERNE non
# satisfaite. Meme principe que le bloc "MISSING" deja construit dans
# bin/order.sh (job_done() sur chaque IN_COND), applique ici a chaque job
# du lot : une IN_COND non produite par un autre job DU LOT et pas encore
# marquee faite sur le systeme reel (state/<COND>.ok absent) est signalee
# comme manquante - jamais un blocage automatique (l'operateur reste libre
# de forcer, exactement comme order.sh), juste un avertissement visible
# AVANT la confirmation plutot qu'un echec decouvert apres coup.
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


def external_missing_deps(ordered, in_cond_by_job, out_cond_by_job, state_dir):
    """Pour chaque job du lot, liste ses IN_COND qui (a) ne sont PAS
    produites par un autre job DU MEME LOT (celles-la sont deja garanties
    par le tri topologique) ET (b) ne sont pas encore marquees faites sur
    le systeme reel (state/<COND>.ok absent). Jamais calcule sur des
    conditions internes au lot - un job plus loin dans l'ordre depend
    souvent, legitimement, d'un job plus tot dans ce MEME lot qui n'a pas
    encore tourne au moment de cette verification (c'est precisement ce
    que le tri topologique organise), jamais une vraie precondition
    manquante."""
    ordered_set = set(ordered)
    producer_of = {}
    for j in ordered:
        oc = out_cond_by_job.get(j, "NONE")
        if oc and oc != "NONE":
            producer_of[oc] = j

    missing_by_job = {}
    for j in ordered:
        ic = in_cond_by_job.get(j, "NONE")
        missing = []
        if ic and ic != "NONE":
            for cond in ic.split("|"):
                producer = producer_of.get(cond)
                if producer and producer in ordered_set:
                    continue  # geree par l'ordre interne du lot, jamais une precondition externe
                if not os.path.exists(os.path.join(state_dir, cond + ".ok")):
                    missing.append(cond)
        missing_by_job[j] = missing
    return missing_by_job


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
    state_dir = os.environ.get("STATE_DIR", "")
    missing_by_job = external_missing_deps(ordered, in_cond_by_job, out_cond_by_job, state_dir) if state_dir else {}
    for j in ordered:
        missing = ",".join(missing_by_job.get(j, []))
        print(f"{j}\t{missing}")


if __name__ == "__main__":
    main()
