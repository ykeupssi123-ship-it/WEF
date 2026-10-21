#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bin/revue_jobs.py - Phase 1 du plan "maintien en forme" : passe chaque job
reel de jobs_table.csv au crible de 5 criteres reels, jamais une impression.

Lecture seule. Rien n'est execute, rien n'est modifie. Standard library only.

Les 5 criteres (texte exact de la Phase 1) :
  PREREQ   prerequis verifies au debut, avec code 2 et la commande qui regle
  IDEMP    idempotence (rejouable sans degat)
  TRACE    trace + code de sortie juste (garanti structurellement par
           lib/run_job.sh pour tout job invoque via order.sh/orchestrator.sh/
           scheduler.sh - verifie ici que le job ne retourne jamais un code
           de sortie incoherent en forcant `exit 0` apres une erreur reelle)
  SECRET   aucun secret affiche (echo/printf/cat direct d'une variable ou
           d'un fichier sensible vers stdout/stderr)
  MSG      message final clair ([JOB_ID] ... en derniere ligne reelle)
  TIMEOUT  delai borne sur tout curl/attente de service

HONNETE SUR LA METHODE : ceci est de l'analyse de motifs (grep intelligent),
jamais une preuve. Un "OK" ici veut dire "le motif attendu est present",
jamais "ce job a ete reellement rejoue et observe". Un "A VERIFIER" n'est
jamais un verdict de bug - juste un signal qui merite un oeil humain ou un
vrai test (voir Phase 3, wef_test.sh).

Usage: revue_jobs.py [jobs_dir] [jobs_table.csv]
Output: REVUE_DES_JOBS.md (a cote de ce script) + resume sur stdout.
"""
import csv, os, re, sys

JOBS_DIR = sys.argv[1] if len(sys.argv) > 1 else 'jobs'
TABLE = sys.argv[2] if len(sys.argv) > 2 else 'jobs_table.csv'
HERE = os.path.dirname(os.path.abspath(__file__))

SECRET_RE = re.compile(r'\b(echo|printf)\b[^|>\n]*\$\{?([A-Z0-9_]*(PASSWORD|SECRET|TOKEN|API_KEY|_KEY|PASS)[A-Z0-9_]*)\}?\b[^|>\n]*$', re.I | re.M)
# cat'ing a *_FILE path variable is only a leak if its output isn't captured
# into a variable or redirected to a file - "echo | keystore --stdin" and
# "X=$(cat $Y_FILE)" are both the CORRECT way to hand a secret to a tool.
CAT_SECRET_RE = re.compile(r'(?<!\$\()\bcat\s+"?\$\{?[A-Z0-9_]*(PASSWORD|SECRET)_FILE\}?"?\s*$', re.M | re.I)
PATH_VAR_RE = re.compile(r'_(FILE|PATH)\b', re.I)
PREREQ_EXIT2_RE = re.compile(r'exit\s+2\b')
GENERIC_PREREQ_RE = re.compile(r'(ERREUR|ERROR).*\n?.*exit\s+1', re.I)
IDEMP_HINT_RE = re.compile(r'(idempotent|deja\s|already|override.*true|PUT\b|si.*existe|if\s+\[\s*!?\s*-[fd]\s)', re.I)
FORCE_EXIT0_RE = re.compile(r'(ERREUR|ERROR)[^\n]*\n[^\n]*exit\s+0\b', re.I)
CURL_RE = re.compile(r'\bcurl\b')
CURL_TIMEOUT_RE = re.compile(r'\bcurl\b[^\n|]*(-m\s*\d|--max-time\s*\d|--connect-timeout)')
WAIT_LOOP_RE = re.compile(r'\b(while|until)\b')
WAIT_HELPER_RE = re.compile(r'wait_for_service_active|wait_for_indexer_auth')
TIMEOUT_CMD_RE = re.compile(r'\btimeout\s+\d')
FINAL_MSG_RE = re.compile(r'echo\s+"\[\w+[\w_]*\][^"]*"\s*\n?\s*(exit\s+0)?\s*$')

def read_tail(text, n=400):
    lines = [l for l in text.splitlines() if l.strip()]
    return '\n'.join(lines[-n:])

def analyze(job_id, path):
    if not os.path.exists(path):
        return {'PREREQ': '?', 'IDEMP': '?', 'TRACE': '?', 'SECRET': '?', 'MSG': '?', 'TIMEOUT': '?', 'note': 'script introuvable'}
    text = open(path, encoding='utf-8', errors='replace').read()
    r = {}

    # SECRET - le seul critere ou "positif" = probleme reel. Un echo/printf
    # qui mentionne une variable *_FILE/*_PATH dans un message (ex. "cle API
    # absente : voir ${X_FILE}") affiche un CHEMIN, jamais le secret lui-meme -
    # jamais une fuite.
    leak = None
    m = SECRET_RE.search(text)
    if m and not PATH_VAR_RE.search(m.group(2)):
        leak = m
    if not leak:
        leak = CAT_SECRET_RE.search(text)
    r['SECRET'] = 'FUITE' if leak else 'OK'

    # PREREQ - presence d'un garde-fou avec code 2, ou au moins un exit 1 documente
    if PREREQ_EXIT2_RE.search(text):
        r['PREREQ'] = 'OK'
    elif GENERIC_PREREQ_RE.search(text):
        r['PREREQ'] = 'EXIT1'   # un garde-fou existe, juste pas le code 2 standardise
    else:
        r['PREREQ'] = 'A VERIFIER'

    # IDEMP - heuristique seulement, jamais une preuve
    r['IDEMP'] = 'OK' if IDEMP_HINT_RE.search(text) else 'A VERIFIER'

    # TRACE - jamais de faux OK force apres une vraie erreur
    r['TRACE'] = 'A VERIFIER' if FORCE_EXIT0_RE.search(text) else 'OK'

    # MSG final
    r['MSG'] = 'OK' if FINAL_MSG_RE.search(read_tail(text, 5)) else 'A VERIFIER'

    # TIMEOUT - seulement si le job attend reellement quelque chose
    needs_timeout = CURL_RE.search(text) or WAIT_LOOP_RE.search(text) or WAIT_HELPER_RE.search(text)
    if not needs_timeout:
        r['TIMEOUT'] = 'N/A'
    else:
        has_bound = CURL_TIMEOUT_RE.search(text) or TIMEOUT_CMD_RE.search(text) or WAIT_HELPER_RE.search(text)
        r['TIMEOUT'] = 'OK' if has_bound else 'A VERIFIER'

    return r

def main():
    rows = list(csv.DictReader(open(TABLE, encoding='utf-8', errors='replace')))
    results = []
    for row in rows:
        jid = row['JOB_ID'].strip()
        script = row['SCRIPT_FILE'].strip()
        path = os.path.join(JOBS_DIR, script)
        r = analyze(jid, path)
        r['id'] = jid
        results.append(r)

    crit = ['PREREQ', 'IDEMP', 'TRACE', 'SECRET', 'MSG', 'TIMEOUT']
    counts = {c: {} for c in crit}
    for r in results:
        for c in crit:
            counts[c][r[c]] = counts[c].get(r[c], 0) + 1

    out = []
    out.append('# Revue des jobs - Phase 1 (analyse de motifs, lecture seule)')
    out.append('')
    out.append('%d jobs analyses depuis `%s` / `%s`.' % (len(results), TABLE, JOBS_DIR))
    out.append('')
    out.append('**Methode honnete** : ceci est du pattern-matching sur le texte des scripts, jamais une')
    out.append('execution reelle. "OK" = le motif attendu est present. "A VERIFIER" = le motif attendu')
    out.append('est absent - un signal pour un oeil humain ou un vrai test, jamais un verdict de bug.')
    out.append('')
    out.append('## Resume par critere')
    out.append('')
    out.append('| Critere | OK | A VERIFIER | Autre |')
    out.append('|---|---|---|---|')
    for c in crit:
        ok = counts[c].get('OK', 0)
        av = counts[c].get('A VERIFIER', 0)
        autre = sum(v for k, v in counts[c].items() if k not in ('OK', 'A VERIFIER'))
        out.append('| %s | %d | %d | %d |' % (c, ok, av, autre))
    out.append('')
    out.append('## FUITE DE SECRET - le seul point qui doit etre 0')
    out.append('')
    leaks = [r for r in results if r['SECRET'] == 'FUITE']
    if leaks:
        for r in leaks:
            out.append('- **%s**' % r['id'])
    else:
        out.append('Aucune. %d jobs verifies, zero echo/printf/cat direct d\'un secret.' % len(results))
    out.append('')
    out.append('## Detail par job (un signal "A VERIFIER" ou plus = a regarder)')
    out.append('')
    out.append('| ID | PREREQ | IDEMP | TRACE | SECRET | MSG | TIMEOUT |')
    out.append('|---|---|---|---|---|---|---|')
    flagged = [r for r in results if any(r[c] not in ('OK', 'N/A') for c in crit)]
    clean = len(results) - len(flagged)
    for r in sorted(flagged, key=lambda r: r['id']):
        out.append('| %s | %s | %s | %s | %s | %s | %s |' % (r['id'], r['PREREQ'], r['IDEMP'], r['TRACE'], r['SECRET'], r['MSG'], r['TIMEOUT']))
    out.append('')
    out.append('%d jobs sans aucun signal (tous criteres OK ou N/A), non listes ci-dessus.' % clean)

    txt = '\n'.join(out) + '\n'
    with open(os.path.join(HERE, 'REVUE_DES_JOBS.md'), 'w', encoding='utf-8') as f:
        f.write(txt)

    print('%d jobs analyses, %d sans signal, %d avec au moins un signal a verifier.' % (len(results), clean, len(flagged)))
    print('Fuites de secret reelles : %d' % len(leaks))
    print('Ecrit : REVUE_DES_JOBS.md')

if __name__ == '__main__':
    main()
