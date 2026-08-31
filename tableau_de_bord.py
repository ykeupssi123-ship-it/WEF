#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tableau_de_bord.py - AJOUTE LE 2026-08-20

Tableau de bord visuel de l'orchestrateur WAZ_ELK_FACTORY, dans l'esprit
d'un ecran de "Monitoring Domain" BMC Control-M : une toile de
dependances entre jobs (nœuds relies par des fleches selon
IN_COND/OUT_COND, organises par famille en colonnes), colores selon
l'etat REEL et LIVE de chaque job.

Ne depend d'AUCUN paquet externe (bibliotheque standard Python 3
uniquement, deja presente sur cette machine puisque dnf lui-meme est
ecrit en Python) - aucune installation supplementaire necessaire.

Service en LECTURE SEULE STRICTE : ne modifie jamais aucun fichier
d'etat, ne declenche jamais aucune action sur un job. Il ne fait que
lire jobs_table.csv + state/ a chaque requete HTTP et generer une page
a la volee - toujours a jour, jamais de cache.

Code couleur (choisi pour ce projet, adapte du souvenir operateur de
BMC Control-M plutot que copie tel quel - pas de plage horaire dans ce
projet, donc pas de distinction "attend son heure" vs "attend une
dependance") :
  GRIS   = EN ATTENTE   (dependance(s) non encore satisfaite(s))
  JAUNE  = EN COURS      (marqueur state/RUNNING/<JOB_ID>.running present)
  ORANGE = GELE (HELD)   (gel manuel operateur, ./geler_job.sh)
  VERT   = TERMINE OK    (marqueur state/<OUT_COND>.ok present)
  ROUGE  = ECHEC         (derniere execution ECHEC/FORCE_ECHEC, pas encore OK)

Usage direct (test/debug) :  python3 tableau_de_bord.py
Usage normal : voir installer_service_tableau_de_bord.sh (installe comme
service systemd, ouvre le port dans firewalld, demarre au boot).
"""
import csv
import html
import os
import re
import subprocess
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
JOBS_CSV = os.path.join(PROJECT_ROOT, "jobs_table.csv")
VARS_FILE = os.path.join(PROJECT_ROOT, "vars.conf")

# Ordre d'affichage des familles (gauche -> droite), reprend l'ordre de
# construction reel de l'usine (infra/PKI d'abord, puis chaque produit).
FAMILY_ORDER = ["INFRA", "DIST", "PKI", "ES", "LS", "KB", "FB", "MB", "WAZ", "WAG"]

COLORS = {
    "ATTENTE": "#9AA0A6",  # gris
    "COURS": "#FBBC04",    # jaune
    "GELE": "#FB8C00",     # orange
    "OK": "#34A853",       # vert
    "ECHEC": "#EA4335",    # rouge
}
LABELS = {
    "ATTENTE": "En attente (dependance non satisfaite)",
    "COURS": "En cours d'execution",
    "GELE": "Gele (HELD, gel manuel operateur)",
    "OK": "Termine OK",
    "ECHEC": "Echec (derniere execution)",
}


def read_vars():
    """Lit ROLE/AGENT_COMPONENTS/STATE_DIR/DASHBOARD_PORT via bash (vars.conf
    contient de vraies expressions bash comme INSTALL_DIR=$(cd ...) - on
    laisse bash les evaluer plutot que de re-implementer un parseur."""
    cmd = (
        f'set -a; source "{VARS_FILE}" >/dev/null 2>&1; '
        f'printf "%s\\x1f%s\\x1f%s\\x1f%s" '
        f'"${{ROLE:-}}" "${{AGENT_COMPONENTS:-}}" "${{STATE_DIR:-}}" "${{DASHBOARD_PORT:-8088}}"'
    )
    out = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True).stdout
    parts = out.split("\x1f")
    while len(parts) < 4:
        parts.append("")
    role, agent_components, state_dir, port = parts
    if not state_dir:
        state_dir = os.path.join(PROJECT_ROOT, "state")
    try:
        port = int(port)
    except ValueError:
        port = 8088
    return {
        "ROLE": role or "ELK_HOST",
        "AGENT_COMPONENTS": [c for c in agent_components.split(",") if c],
        "STATE_DIR": state_dir,
        "DASHBOARD_PORT": port,
    }


def component_enabled(component, agent_components):
    if not component or component == "ALWAYS":
        return True
    parts = component.split("|")
    return any(p in agent_components for p in parts)


def load_jobs(cfg):
    jobs = []
    if not os.path.isfile(JOBS_CSV):
        return jobs
    with open(JOBS_CSV, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or row[0] == "JOB_ID":
                continue
            if len(row) < 8:
                continue
            job_id, job_name, job_role, component, script_file, desc, in_cond, out_cond = row[:8]
            if job_role != cfg["ROLE"] and job_role != "ALL":
                continue
            if cfg["ROLE"] == "AGENT_HOST" and not component_enabled(component, cfg["AGENT_COMPONENTS"]):
                continue
            in_conds = [c for c in in_cond.split("|") if c and c != "NONE"]
            jobs.append({
                "id": job_id,
                "name": job_name,
                "desc": desc,
                "script": script_file,
                "in_conds": in_conds,
                "out_cond": out_cond,
            })
    return jobs


def read_state(cfg):
    state_dir = cfg["STATE_DIR"]
    ok_conds = set()
    if os.path.isdir(state_dir):
        for f in os.listdir(state_dir):
            if f.endswith(".ok"):
                ok_conds.add(f[:-3])
    held = set()
    held_dir = os.path.join(state_dir, "HELD")
    if os.path.isdir(held_dir):
        for f in os.listdir(held_dir):
            if f.endswith(".held"):
                held.add(f[:-5])
    running = set()
    running_dir = os.path.join(state_dir, "RUNNING")
    if os.path.isdir(running_dir):
        for f in os.listdir(running_dir):
            if f.endswith(".running") and not f.startswith("_"):
                running.add(f[:-8])
    last_result = {}
    ledger = os.path.join(state_dir, "JOBS_HISTORY.csv")
    if os.path.isfile(ledger):
        with open(ledger, newline="", encoding="utf-8") as f:
            reader = csv.reader(f)
            for row in reader:
                if not row or row[0] == "TIMESTAMP" or len(row) < 4:
                    continue
                last_result[row[1]] = row[3]
    return {"ok_conds": ok_conds, "held": held, "running": running, "last_result": last_result}


def job_family(job_id):
    m = re.match(r"^([A-Z]+)_", job_id)
    fam = m.group(1) if m else job_id
    return fam if fam in FAMILY_ORDER else fam


def compute_state(job, state):
    if job["id"] in state["held"]:
        return "GELE"
    if job["id"] in state["running"]:
        return "COURS"
    if job["out_cond"] in state["ok_conds"]:
        return "OK"
    last = state["last_result"].get(job["id"], "")
    if last in ("ECHEC", "FORCE_ECHEC"):
        return "ECHEC"
    return "ATTENTE"


def compute_layout(jobs):
    by_out = {}
    for j in jobs:
        by_out.setdefault(j["out_cond"], j["id"])
    by_id = {j["id"]: j for j in jobs}

    depth_cache = {}

    def depth(job_id, visiting=None):
        if job_id in depth_cache:
            return depth_cache[job_id]
        if visiting is None:
            visiting = set()
        if job_id in visiting or job_id not in by_id:
            return 0
        visiting = visiting | {job_id}
        job = by_id[job_id]
        if not job["in_conds"]:
            d = 0
        else:
            producer_depths = []
            for cond in job["in_conds"]:
                producer = by_out.get(cond)
                if producer:
                    producer_depths.append(depth(producer, visiting) + 1)
            d = max(producer_depths) if producer_depths else 0
        depth_cache[job_id] = d
        return d

    for j in jobs:
        j["depth"] = depth(j["id"])
        j["family"] = job_family(j["id"])

    families = []
    for f in FAMILY_ORDER:
        if any(j["family"] == f for j in jobs):
            families.append(f)
    for j in jobs:
        if j["family"] not in families:
            families.append(j["family"])

    family_x = {f: i for i, f in enumerate(families)}
    # au sein d'une meme famille/meme profondeur, plusieurs jobs peuvent
    # coexister (paralleles) - on les empile verticalement avec un
    # decalage pour eviter la superposition.
    slot_counter = {}
    for j in sorted(jobs, key=lambda x: (family_x.get(x["family"], 999), x["depth"], x["id"])):
        key = (j["family"], j["depth"])
        slot = slot_counter.get(key, 0)
        slot_counter[key] = slot + 1
        j["slot"] = slot

    return jobs, families, by_out


NODE_W, NODE_H = 170, 46
COL_GAP, ROW_GAP, SLOT_GAP = 220, 64, 54
MARGIN = 60


def render_svg(jobs, families, by_out):
    max_depth = max((j["depth"] for j in jobs), default=0)
    max_slot = max((j["slot"] for j in jobs), default=0)
    width = MARGIN * 2 + len(families) * COL_GAP
    height = MARGIN * 2 + 60 + (max_depth + 1) * ROW_GAP + (max_slot + 1) * SLOT_GAP

    by_id = {j["id"]: j for j in jobs}

    def center(j):
        x = MARGIN + families.index(j["family"]) * COL_GAP + NODE_W / 2
        y = MARGIN + 60 + j["depth"] * ROW_GAP + j["slot"] * SLOT_GAP
        return x, y

    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">']
    parts.append('<rect x="0" y="0" width="100%" height="100%" fill="#0f1115"/>')

    # en-tetes de colonnes (familles)
    for f in families:
        x = MARGIN + families.index(f) * COL_GAP + NODE_W / 2
        parts.append(
            f'<text x="{x}" y="{MARGIN + 20}" fill="#e8eaed" font-size="16" '
            f'font-family="Segoe UI, Arial, sans-serif" font-weight="700" text-anchor="middle">{html.escape(f)}</text>'
        )

    # liens (dessines avant les noeuds pour rester dessous)
    for j in jobs:
        x2, y2 = center(j)
        for cond in j["in_conds"]:
            producer_id = by_out.get(cond)
            producer = by_id.get(producer_id)
            if not producer:
                continue
            x1, y1 = center(producer)
            parts.append(
                f'<path d="M {x1} {y1+NODE_H/2} C {x1} {(y1+y2)/2}, {x2} {(y1+y2)/2}, {x2} {y2-NODE_H/2}" '
                f'fill="none" stroke="#4a4f57" stroke-width="1.4"/>'
            )

    # noeuds
    for j in jobs:
        x, y = center(j)
        state = j["_state"]
        color = COLORS[state]
        rx, ry = x - NODE_W / 2, y - NODE_H / 2
        title = f'{j["id"]} - {j["name"]}\n{j["desc"]}\nEtat : {LABELS[state]}'
        parts.append(f'<g>')
        parts.append(f'<title>{html.escape(title)}</title>')
        parts.append(
            f'<rect x="{rx}" y="{ry}" width="{NODE_W}" height="{NODE_H}" rx="8" ry="8" '
            f'fill="{color}" stroke="#1b1e23" stroke-width="1.5"/>'
        )
        label = j["id"]
        if len(label) > 22:
            label = label[:21] + "…"
        parts.append(
            f'<text x="{x}" y="{y - 3}" fill="#111318" font-size="12.5" font-weight="700" '
            f'font-family="Segoe UI, Arial, sans-serif" text-anchor="middle">{html.escape(label)}</text>'
        )
        sub = j["name"]
        if len(sub) > 24:
            sub = sub[:23] + "…"
        parts.append(
            f'<text x="{x}" y="{y + 13}" fill="#111318" font-size="9.5" '
            f'font-family="Segoe UI, Arial, sans-serif" text-anchor="middle">{html.escape(sub)}</text>'
        )
        parts.append("</g>")

    parts.append("</svg>")
    return "".join(parts), width, height


def render_page(cfg):
    jobs = load_jobs(cfg)
    state = read_state(cfg)
    for j in jobs:
        j["_state"] = compute_state(j, state)
    jobs, families, by_out = compute_layout(jobs)
    svg, width, height = render_svg(jobs, families, by_out)

    counts = {k: 0 for k in COLORS}
    for j in jobs:
        counts[j["_state"]] += 1

    legend_items = "".join(
        f'<span class="legend-item"><span class="dot" style="background:{COLORS[k]}"></span>'
        f'{html.escape(LABELS[k])} ({counts[k]})</span>'
        for k in ["ATTENTE", "COURS", "GELE", "OK", "ECHEC"]
    )

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="5">
<title>WAZ_ELK_FACTORY - Tableau de bord</title>
<style>
  body {{ background:#0f1115; color:#e8eaed; font-family: 'Segoe UI', Arial, sans-serif; margin:0; padding:0; }}
  header {{ padding: 14px 22px; border-bottom: 1px solid #2a2e35; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; }}
  h1 {{ font-size: 18px; margin: 0; font-weight: 700; }}
  .meta {{ font-size: 12px; color:#9aa0a6; }}
  .legend {{ padding: 10px 22px; display:flex; gap:18px; flex-wrap:wrap; border-bottom: 1px solid #2a2e35; }}
  .legend-item {{ font-size: 12.5px; display:flex; align-items:center; gap:6px; }}
  .dot {{ width:11px; height:11px; border-radius:3px; display:inline-block; }}
  .canvas {{ overflow: auto; padding: 10px; }}
</style>
</head>
<body>
<header>
  <h1>WAZ_ELK_FACTORY - Toile de dependances (live)</h1>
  <div class="meta">Genere le {now} - rafraichissement auto (5s) - lecture seule</div>
</header>
<div class="legend">{legend_items}</div>
<div class="canvas">
{svg}
</div>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return
        try:
            cfg = read_vars()
            body = render_page(cfg).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            msg = f"Erreur de generation du tableau de bord : {e}".encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def log_message(self, fmt, *args):
        sys.stderr.write("[tableau_de_bord] " + (fmt % args) + "\n")


def main():
    cfg = read_vars()
    port = cfg["DASHBOARD_PORT"]
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[tableau_de_bord] Ecoute sur 0.0.0.0:{port} (projet : {PROJECT_ROOT})")
    server.serve_forever()


if __name__ == "__main__":
    main()
