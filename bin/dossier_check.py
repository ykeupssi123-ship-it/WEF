#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bin/dossier_check.py - is the operations workbook still true?

The workbook says: "nothing is true because it is written - it is true because it ran".
This applies the rule to the workbook itself. It reads every claim the workbook makes
(bin/dossier_claims.json, exported when the workbook is built) and checks each one
against this machine:

  SCRIPT   every $APP_BIN / $APP_INF / $APP_HOME script a command calls exists
  JOB      every job a command orders exists in jobs_table.csv (or jobs/)
  LEVER    every lever exists in vars.conf, and its value is the one the workbook shows
  SYNTAX   every command line parses in bash (bash -n) - nothing is executed

Read-only. Nothing is run, nothing is changed.
  $APP_BIN/dossier_check.sh              full report
  $APP_BIN/dossier_check.sh --short      verdict and problems only
Output also written to $STATE_DIR/dossier_check.log. Exit 0 = true, 1 = something to fix.
"""
import csv, json, os, re, subprocess, sys, datetime as dt
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
APP_HOME = os.environ.get('APP_HOME') or os.path.dirname(HERE)
STATE = os.environ.get('STATE_DIR') or os.path.join(APP_HOME, 'state')
SHORT = '--short' in sys.argv
P = lambda *p: os.path.join(*p)

claims = json.load(open(P(HERE, 'dossier_claims.json'), encoding='utf-8'))

# ---- what is really on this machine
def read_vars(path):
    out = {}
    if not os.path.exists(path): return out
    for ln in open(path, encoding='utf-8', errors='replace'):
        m = re.match(r'^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)=(.*)$', ln)
        if not m: continue
        v = m.group(2).strip()
        if v[:1] in ('"', "'"):
            q = v[0]; e = v.find(q, 1)
            v = v[1:e] if e > 0 else v[1:]
        else:
            v = v.split(' #')[0].split('\t#')[0].strip()
        out[m.group(1)] = v
    return out
VARS = read_vars(P(APP_HOME, 'vars.conf'))
VARS.update(read_vars(P(APP_HOME, 'vars.local.conf')))
JOBS = set()
if os.path.exists(P(APP_HOME, 'jobs_table.csv')):
    for r in csv.DictReader(open(P(APP_HOME, 'jobs_table.csv'), encoding='utf-8', errors='replace')):
        JOBS.add(r.get('JOB_ID', '').strip())
for d in ('jobs', 'jobs_windows'):
    if os.path.isdir(P(APP_HOME, d)):
        for f in os.listdir(P(APP_HOME, d)):
            JOBS.add(re.sub(r'\.(sh|ps1|enc)$', '', f))
ROOTS = {'$APP_BIN': P(APP_HOME, 'bin'), '$APP_INF': P(APP_HOME, 'setup'), '$APP_HOME': APP_HOME}

# ---- checks
problems = defaultdict(list)   # kind -> [(where, detail)]
counts = defaultdict(int)
seen_script, seen_job = {}, {}
for c in claims['commands']:
    cmd = c['cmd'].split('  # ')[0]
    where = f"{c['sheet'][:12]} r{c['row']} {c['op']}"
    for root, path in re.findall(r'(\$APP_BIN|\$APP_INF|\$APP_HOME)/([\w./-]+\.(?:sh|py))', cmd):
        full = P(ROOTS[root], path)
        if full not in seen_script:
            seen_script[full] = os.path.exists(full); counts['SCRIPT'] += 1
            if not seen_script[full]: problems['SCRIPT'].append((where, f'{root}/{path} not found'))
    for j in re.findall(r'(?:order|hold|free|confirm|history|incidents)\.sh\s+([A-Z][A-Z0-9_]+)', cmd):
        if j in seen_job: continue
        seen_job[j] = j in JOBS; counts['JOB'] += 1
        if not seen_job[j]: problems['JOB'].append((where, f'{j} not in jobs_table.csv nor jobs/'))
    if c['on'] in ('VM1', 'VM2', 'VM1 + VM2') and cmd.strip():
        counts['SYNTAX'] += 1
        test = cmd.replace('{REASON}', 'x')
        r = subprocess.run(['bash', '-n', '-c', test], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        if r.returncode != 0:
            problems['SYNTAX'].append((where, (r.stderr.strip().splitlines() or ['?'])[-1][:90]))
for lv in claims['levers']:
    counts['LEVER'] += 1
    n, doc = lv['name'], lv['value']
    if '$(' in doc:      # computed at run time by bash - nothing to compare
        counts['LEVER'] -= 1; continue
    if n not in VARS:
        problems['LEVER'].append((n, 'not in vars.conf'))
    elif VARS[n] != doc:
        problems['LEVER'].append((n, f'workbook "{doc[:30]}"  ->  machine "{VARS[n][:30]}"'))

# ---- report
W = 100
L = ['=' * W, f'WEF · IS THE WORKBOOK STILL TRUE?   built {claims["built"]}   checked {dt.datetime.now():%Y-%m-%d %H:%M} on {os.uname().nodename}', '=' * W]
bad = sum(len(v) for v in problems.values())
L.append('VERDICT   ' + ('TRUE - every command, job and value of the workbook matches this machine' if not bad
                         else f'{bad} thing(s) differ - the workbook must be rebuilt or the machine corrected'))
L.append('')
for k, what in (('SCRIPT', 'scripts called'), ('JOB', 'jobs ordered'), ('LEVER', 'lever values'), ('SYNTAX', 'command lines (bash -n)')):
    n = counts[k]; ko = len(problems[k])
    L.append(f'   {k:<7} {n:>4} {what:<26} {"OK" if not ko else f"{ko} to fix"}')
for k in ('SCRIPT', 'JOB', 'LEVER', 'SYNTAX'):
    if not problems[k]: continue
    L.append(''); L.append(f'{k}  -  to fix')
    for where, detail in problems[k][: (15 if SHORT else 200)]:
        L.append(f'   {where:<34} {detail}'[:W])
    if SHORT and len(problems[k]) > 15: L.append(f'   ... {len(problems[k]) - 15} more (run without --short)')
L.append('')
L.append('A lever that differs: either the workbook is old (rebuild it) or the machine drifted (correct it, then replay).')
L.append('=' * W)
txt = '\n'.join(L) + '\n'
sys.stdout.write(txt)
try:
    os.makedirs(STATE, exist_ok=True)
    open(P(STATE, 'dossier_check.log'), 'w', encoding='utf-8').write(txt)
except OSError:
    pass
sys.exit(1 if bad else 0)
