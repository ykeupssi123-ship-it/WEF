#!/bin/bash
# bin/incidents.sh - Registre d'Incidents (ITIL 4 Incident Management),
# AJOUTE LE 2026-09-30. Distinct du Journal des Problemes
# (docs/JOURNAL_TECHNIQUE.md, qui documente la CAUSE RACINE d'un
# dysfonctionnement) : un Incident est le SYMPTOME - une execution en
# echec, avec sa duree de resolution REELLE, mesuree, jamais devinee.
#
# MECANISME : derive ENTIEREMENT de state/JOBS_HISTORY.csv - jamais une
# deuxieme source de verite saisie a la main. Pour chaque ECHEC/
# FORCE_ECHEC/SCHEDULED_ECHEC, cherche la PROCHAINE execution reussie du
# MEME job dans l'historique -> l'ecart de temps EST la duree de
# resolution. Aucune reussite ulterieure trouvee : incident encore
# OUVERT.
#
# Severite CALCULEE, jamais devinee : nombre de jobs dont l'IN_COND
# depend reellement du OUT_COND de ce job (meme calcul de "rayon
# d'impact" deja utilise par bin/order.sh, jamais duplique a la main) -
# P1 si 3 jobs ou plus en dependent, P2 si 1 ou 2, P3 si le job est
# isole.
#
# ETENDU LE 2026-10-18 (demande explicite : des fiches d'incident
# individuelles, au format reel de la conformite en production - voir
# docs/JOURNAL_TECHNIQUE.md pour le contexte complet). Jusqu'ici,
# INCIDENTS.csv etait la seule sortie - un tableau, pas une preuve
# d'audit presentable une a une. Desormais, CHAQUE incident recoit en
# plus un fichier texte individuel, autoportant, sous
# state/incidents/<INC-ID>.txt - genere automatiquement (jamais ecrit a
# la main), au meme titre qu'un sysout de job.
#
# DEUX GARANTIES STRUCTURELLES, pensees pour une relecture en 2045
# (le probleme pose explicitement par l'operateur : qu'un incident de
# 2026 reste retrouvable a l'identique, par les memes employes ou de
# nouveaux, des annees plus tard) :
#
#   1. IDENTIFIANT STABLE, JAMAIS RENUMEROTE. L'ancienne version
#      numerotait sequentiellement a CHAQUE execution (len(incidents)+1)
#      - un meme incident pouvait changer d'identifiant d'une execution
#      a l'autre selon ce qui restait dans l'historique a ce moment-la
#      (purge, filtre). Desormais, state/incidents_id_map.csv associe
#      DEFINITIVEMENT (job_id, horodatage de detection) -> incident_id,
#      la premiere fois qu'un incident est vu - toute execution
#      ulterieure reutilise le MEME identifiant, jamais un nouveau.
#   2. FICHE IMMUABLE UNE FOIS RESOLUE. Tant qu'un incident reste
#      OUVERT, sa fiche peut etre reecrite (le statut peut changer d'une
#      execution a l'autre, c'est legitime - un vrai ticket vit avant
#      cloture). Une fois RESOLU, sa fiche n'est plus jamais reecrite -
#      verifie en lisant la ligne "Statut" du fichier existant avant
#      toute ecriture. Une fiche cloturee est un document fige, exactement
#      comme un vrai dossier d'audit papier.
#
# Consequence directe et assumee : state/JOBS_HISTORY.csv peut un jour
# etre purge (MNT_purge_hist, deja evoque dans docs/GUIDE_EXPLOITATION.md)
# sans jamais effacer les fiches deja ecrites - une fiche est un
# document autoportant, independant de la source qui l'a produite,
# exactement comme un vrai rapport d'incident imprime reste valide meme
# si le systeme source change.
#
# Chaque fiche tente aussi un rapprochement automatique avec
# docs/JOURNAL_TECHNIQUE.md (cause racine) : si une section datee du
# meme jour mentionne le meme JOB_ID, la fiche y renvoie explicitement -
# jamais invente si rien n'est trouve ("non documentee a ce jour").
#
# Usage :
#   ./bin/incidents.sh              -> tous les jobs, (re)genere toutes
#                                       les fiches necessaires
#   ./bin/incidents.sh WAZ_050_VIRUSTOTAL_INTEGRATION   -> un seul job
#
# Consultation des fiches individuelles : voir bin/incident_card.sh
# (liste, filtre par statut/severite, affichage d'une fiche precise).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="$HERE/state/JOBS_HISTORY.csv"
JOBS_TABLE="$HERE/jobs_table.csv"
JOURNAL="$HERE/docs/JOURNAL_TECHNIQUE.md"
OUT_FILE="$HERE/state/INCIDENTS.csv"
ID_MAP_FILE="$HERE/state/incidents_id_map.csv"
CARDS_DIR="$HERE/state/incidents"
FILTER_JOB="${1:-}"

if [ ! -f "$LEDGER" ]; then
  echo "Aucun historique pour l'instant (state/JOBS_HISTORY.csv absent) - rien a deriver."
  exit 0
fi

mkdir -p "$CARDS_DIR"

LEDGER_FILE="$LEDGER" JOBS_TABLE_FILE="$JOBS_TABLE" JOURNAL_FILE="$JOURNAL" \
OUT_FILE="$OUT_FILE" ID_MAP_FILE="$ID_MAP_FILE" CARDS_DIR="$CARDS_DIR" \
FILTER_JOB="$FILTER_JOB" python3 << 'PYEOF'
import csv, os, re, datetime

# datetime.fromisoformat() n'existe qu'a partir de Python 3.7 - VM1/VM2
# tournent Python 3.6 (deja rencontre cette session, ex. check_ilm.py).
# L'offset de fuseau ("+01:00") est toujours le meme sur une seule
# machine : il est ignore ici (jamais necessaire pour une SOUSTRACTION
# entre deux horodatages de la meme machine), seule la partie naive est
# parsee.
def parse_ts(s):
    naive = re.sub(r'[+-]\d{2}:\d{2}$', '', s)
    return datetime.datetime.strptime(naive, "%Y-%m-%dT%H:%M:%S")

ledger_file = os.environ['LEDGER_FILE']
jobs_table_file = os.environ['JOBS_TABLE_FILE']
journal_file = os.environ['JOURNAL_FILE']
out_file = os.environ['OUT_FILE']
id_map_file = os.environ['ID_MAP_FILE']
cards_dir = os.environ['CARDS_DIR']
filter_job = os.environ.get('FILTER_JOB', '')

# --- Graphe de dependances (rayon d'impact), identique a l'original ---
outcond_by_job = {}
with open(jobs_table_file, encoding='utf-8') as f:
    reader = csv.reader(f)
    next(reader)
    rows = [r for r in reader if len(r) >= 8]
for row in rows:
    outcond_by_job[row[0]] = row[7]

consumers_of = {}
for row in rows:
    in_cond = row[6]
    if in_cond and in_cond != "NONE":
        needed = set(in_cond.split("|"))
        for job_id, out_cond in outcond_by_job.items():
            if out_cond in needed:
                consumers_of.setdefault(job_id, []).append(row[0])

def severity(job_id):
    cons = sorted(set(consumers_of.get(job_id, [])))
    n = len(cons)
    if n >= 3:
        return "P1", cons
    if n >= 1:
        return "P2", cons
    return "P3", cons

# --- Rapprochement cause racine : docs/JOURNAL_TECHNIQUE.md ---
# Sections datees "## AAAA-MM-JJ - titre" (format reel, confirme par
# lecture directe du fichier). Un incident du <date> est rapproche d'une
# section de CE MEME jour qui mentionne le meme JOB_ID - jamais une
# correspondance approximative.
journal_sections = []  # (date_str, titre, texte)
if os.path.isfile(journal_file):
    with open(journal_file, encoding='utf-8') as f:
        content = f.read()
    parts = re.split(r'(?m)^(## .+)$', content)
    # parts[0] = preambule avant la 1ere section ; ensuite alterne [header, body, header, body, ...]
    for i in range(1, len(parts), 2):
        header = parts[i].strip()
        body = parts[i + 1] if i + 1 < len(parts) else ""
        m = re.match(r'##\s+(\d{4}-\d{2}-\d{2})\s*-\s*(.*)', header)
        if m:
            journal_sections.append((m.group(1), m.group(2).strip(), header + body))

def find_root_cause_link(date_str, job_id):
    for d, titre, _ in journal_sections:
        if d == date_str and job_id in next(txt for dd, tt, txt in journal_sections if dd == d and tt == titre):
            return f"docs/JOURNAL_TECHNIQUE.md, section \"{d} - {titre}\""
    return None

# AJOUTE LE 2026-10-21 (demande explicite : le pourquoi doit etre visible
# IMMEDIATEMENT sur la fiche, pas seulement dans le log qu'il faut aller
# ouvrir separement). bin/order.sh ecrit deja "Raison : <texte>" dans
# l'en-tete du JOB_LOG avant tout forcage (voir bin/order.sh, "la raison
# est obligatoire"). Un job normal ou planifie n'a jamais cette ligne -
# jamais invente une raison qui n'existe pas, le champ dit alors
# clairement qu'il n'y en a pas.
def find_reason(log_path):
    if not log_path or not os.path.isfile(log_path):
        return None
    try:
        with open(log_path, encoding='utf-8', errors='replace') as f:
            head = f.read(2000)  # l'en-tete est toujours dans les premieres lignes
    except OSError:
        return None
    m = re.search(r'^Raison\s*:\s*(.+)$', head, re.MULTILINE)
    return m.group(1).strip() if m else None

# --- Identifiants stables : charges une fois, jamais renumerotes ---
id_map = {}  # (job_id, detected_ts) -> incident_id (ex "INC-0007")
if os.path.isfile(id_map_file):
    with open(id_map_file, encoding='utf-8') as f:
        reader = csv.reader(f)
        next(reader, None)
        for r in reader:
            if len(r) >= 3:
                id_map[(r[0], r[1])] = r[2]

existing_numbers = [int(v.split('-')[1]) for v in id_map.values() if re.match(r'^INC-\d+$', v)]
next_num = (max(existing_numbers) + 1) if existing_numbers else 1

FAIL_LABELS = {"ECHEC", "FORCE_ECHEC", "SCHEDULED_ECHEC"}
OK_LABELS = {"OK", "FORCE_OK", "SCHEDULED_OK"}

executions = []
with open(ledger_file, encoding='utf-8') as f:
    for line in f:
        line = line.rstrip("\n")
        if not line or line.startswith("TIMESTAMP") or line.startswith("timestamp"):
            continue
        parts = line.split(",")
        if len(parts) < 6:
            continue
        executions.append(tuple(parts[:6]))

def human_duration(seconds_str):
    try:
        s = int(seconds_str)
    except (TypeError, ValueError):
        return "-"
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    out = []
    if h:
        out.append(f"{h}h")
    if m:
        out.append(f"{m}m")
    out.append(f"{sec}s")
    return " ".join(out)

incidents = []
new_cards = 0
updated_cards = 0
for i, (ts, job_id, job_name, result, log_path, duree) in enumerate(executions):
    if filter_job and job_id != filter_job:
        continue
    if result not in FAIL_LABELS:
        continue

    key = (job_id, ts)
    if key in id_map:
        inc_id = id_map[key]
    else:
        inc_id = f"INC-{next_num:04d}"
        next_num += 1
        id_map[key] = inc_id

    resolved_ts = None
    for ts2, job_id2, job_name2, result2, log_path2, duree2 in executions[i + 1:]:
        if job_id2 == job_id and result2 in OK_LABELS:
            resolved_ts = ts2
            break
    statut = "RESOLU" if resolved_ts else "OUVERT"
    duree_resolution = ""
    if resolved_ts:
        try:
            t1 = parse_ts(ts)
            t2 = parse_ts(resolved_ts)
            duree_resolution = str(int((t2 - t1).total_seconds()))
        except ValueError:
            duree_resolution = ""

    sev, cons = severity(job_id)
    incidents.append([inc_id, ts, job_id, job_name, result, sev, statut, resolved_ts or "",
                       duree_resolution, log_path])

    # --- Fiche individuelle : jamais reecrite une fois RESOLUE ---
    card_path = os.path.join(cards_dir, f"{inc_id}.txt")
    skip_write = False
    if os.path.isfile(card_path):
        with open(card_path, encoding='utf-8') as f:
            existing = f.read()
        m = re.search(r'^Statut\s*:\s*(\S+)', existing, re.MULTILINE)
        if m and m.group(1) == "RESOLU":
            skip_write = True  # figee definitivement, document d'audit clos

    if not skip_write:
        date_str = ts[:10]
        link = find_root_cause_link(date_str, job_id)
        cause_line = link if link else "Non documentee dans le Journal Technique a ce jour - a completer lors de l'investigation."
        impact_line = (f"{len(cons)} job(s) en dependent : {', '.join(cons)}"
                        if cons else "aucun job en aval ne depend de ce resultat (incident isole).")

        card = []
        card.append("=" * 72)
        card.append(f"FICHE D'INCIDENT -- {inc_id}")
        card.append("=" * 72)
        card.append(f"Detecte le        : {ts}")
        card.append(f"Job                : {job_id}")
        card.append(f"Libelle job        : {job_name}")
        card.append(f"Type d'echec       : {result}")
        reason = find_reason(log_path)
        card.append(f"Raison (operateur) : {reason if reason else '(aucune - execution normale ou planifiee, jamais forcee a la main)'}")
        card.append(f"Severite           : {sev}  (rayon d'impact : {impact_line})")
        card.append(f"Statut             : {statut}")
        card.append(f"Resolu le          : {resolved_ts or '-'}")
        card.append(f"Duree resolution   : {human_duration(duree_resolution) if duree_resolution else '-'}")
        card.append(f"Log d'execution    : {log_path}")
        card.append(f"Cause racine       : {cause_line}")
        card.append("-" * 72)
        if statut == "OUVERT":
            card.append("Cette fiche sera mise a jour automatiquement (bin/incidents.sh) des")
            card.append("qu'une execution reussie du meme job sera constatee dans l'historique.")
        else:
            card.append("Incident RESOLU : cette fiche est desormais figee, elle ne sera plus")
            card.append("jamais reecrite automatiquement - document d'audit clos.")
        card.append("=" * 72)
        card.append(f"Genere automatiquement par bin/incidents.sh ({datetime.datetime.now().isoformat(timespec='seconds')}).")
        card.append("Consultation : ./bin/incident_card.sh " + inc_id)
        card.append("")

        is_new = not os.path.isfile(card_path)
        with open(card_path, "w", encoding='utf-8') as f:
            f.write("\n".join(card))
        if is_new:
            new_cards += 1
        else:
            updated_cards += 1

with open(out_file, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["incident_id", "detecte_le", "job_id", "job_name", "type_echec", "severite",
                "statut", "resolu_le", "duree_resolution_sec", "log"])
    w.writerows(incidents)

with open(id_map_file, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["job_id", "detected_ts", "incident_id"])
    for (jid, ts), inc_id in sorted(id_map.items(), key=lambda kv: kv[1]):
        w.writerow([jid, ts, inc_id])

print(f"[incidents] {len(incidents)} incident(s) derive(s) de l'historique reel -> {out_file}")
open_count = sum(1 for inc in incidents if inc[6] == "OUVERT")
p1_count = sum(1 for inc in incidents if inc[5] == "P1")
print(f"[incidents] dont {open_count} encore OUVERT(S) (aucune reussite ulterieure du meme job dans l'historique).")
print(f"[incidents] dont {p1_count} de severite P1 (3 jobs ou plus en dependent).")
print(f"[incidents] fiches individuelles : {new_cards} nouvelle(s), {updated_cards} mise(s) a jour, "
      f"{len(incidents) - new_cards - updated_cards} deja figee(s) (RESOLU, inchangee(s)) -> {cards_dir}/")
PYEOF
