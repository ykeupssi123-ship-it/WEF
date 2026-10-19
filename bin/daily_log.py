#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bin/daily_log.py - the WEF daily log, written by the server itself.

One plain-text file per day (and per week, month, quarter, semester, year).
Nobody fills it in: it is built from what really ran (state/JOBS_HISTORY.csv)
and from the registers the engine already keeps (CHANGE_LOG, CONFIG_AUDIT_TRAIL,
INCIDENTS). Read it with cat.

  cat $STATE_DIR/daily_log/TODAY.log                today, refreshed every 15 min
  cat $STATE_DIR/daily_log/day/2026-10-18.log       a closed day
  cat $STATE_DIR/daily_log/month/2026-10.log        a month (same for week/quarter/semester/year)

Usage:
  daily_log.sh                         today so far  -> daily_log/TODAY.log
  daily_log.sh day 2026-10-18          one day       -> daily_log/day/2026-10-18.log
  daily_log.sh week [2026-W42]         a week        -> daily_log/week/2026-W42.log
  daily_log.sh month [2026-10]         a month       -> daily_log/month/2026-10.log
  daily_log.sh quarter [2026-Q4]       a quarter
  daily_log.sh semester [2026-S2]      a semester
  daily_log.sh year [2026]             a year
  daily_log.sh period 2026-10-01 2026-10-18   any period an auditor asks for
  daily_log.sh --close                 (cron, 00:10) close yesterday + every period that just ended
  options: --org "Name"   --mail (send the report to DAILY_LOG_MAIL_TO)

Standard library only. Read-only on the engine. No network (mail is sent by daily_log.sh).
"""
import csv, datetime as dt, hashlib, json, os, re, socket, sys, textwrap

# ANSI colour - this file is meant to be cat'd in a real terminal (PuTTY),
# never opened as plain text. Applied as the LAST step, after every column
# is already padded on plain text - colour codes are invisible width, so
# they ride along without breaking alignment.
_A = dict(g='\033[32m', y='\033[33m', r='\033[31m', d='\033[2m', c='\033[36m', b='\033[1m', z='\033[0m')
def _c(s, k): return _A[k] + s + _A['z']
_DOT_COLOR = {'OK': 'g', 'NOT DUE': 'd', 'NOT YET': 'y', 'LATE': 'y', 'MISSED': 'r'}
_STATUS_COLOR = {'OK': 'g', 'CLEAN': 'g', 'FORCE_OK': 'g', 'SCHEDULED_OK': 'g', 'MARQUE_OK': 'g',
                 'LATE': 'y', 'NOT YET': 'y', 'WARN': 'y',
                 'MISSED': 'r', 'FAILED': 'r', 'ECHEC': 'r', 'FORCE_ECHEC': 'r', 'SCHEDULED_ECHEC': 'r', 'ACTION': 'r',
                 'NOT DUE': 'd'}
_STATUS_RE = re.compile(r'\b(' + '|'.join(sorted(_STATUS_COLOR, key=len, reverse=True)) + r')\b')
_ANSI_RE = re.compile(r'\033\[\d+m')
def vlen(s): return len(_ANSI_RE.sub('', s))
def dot(verdict): return _c('●', _DOT_COLOR.get(verdict, 'd'))
def paint(line):
    line = line.replace('✓', _c('✓', 'g')).replace('✗', _c('✗', 'r'))
    return _STATUS_RE.sub(lambda m: _c(m.group(1), _STATUS_COLOR[m.group(1)]), line)
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
APP_HOME = os.environ.get('APP_HOME') or os.path.dirname(HERE)
STATE = os.environ.get('STATE_DIR') or os.path.join(APP_HOME, 'state')
OUTROOT = os.path.join(STATE, 'daily_log')
W = 100
NOW = dt.datetime.now()
TODAY = NOW.date()
P = lambda *p: os.path.join(*p)
D = lambda s: dt.datetime.strptime(s, '%Y-%m-%d').date()

# ------------------------------------------------------------------ arguments -> list of reports to write
args = sys.argv[1:]
org = os.environ.get('ORG_NAME') or 'WEF Operations'
if '--org' in args:
    k = args.index('--org'); org = args[k + 1]; del args[k:k + 2]
args = [a for a in args if a != '--mail']

def week_of(d):
    y, w, _ = d.isocalendar(); mon = d - dt.timedelta(d.weekday())
    return ('week', '%d-W%02d' % (y, w), mon, mon + dt.timedelta(6))
def month_of(d):
    a = d.replace(day=1); b = (a + dt.timedelta(32)).replace(day=1) - dt.timedelta(1)
    return ('month', a.strftime('%Y-%m'), a, b)
def quarter_of(d):
    q = (d.month - 1) // 3; a = dt.date(d.year, 3 * q + 1, 1)
    b = (dt.date(d.year + (q == 3), (3 * q + 3) % 12 + 1, 1)) - dt.timedelta(1)
    return ('quarter', '%d-Q%d' % (d.year, q + 1), a, b)
def semester_of(d):
    s = 0 if d.month <= 6 else 1; a = dt.date(d.year, 6 * s + 1, 1)
    b = dt.date(d.year, 6, 30) if s == 0 else dt.date(d.year, 12, 31)
    return ('semester', '%d-S%d' % (d.year, s + 1), a, b)
def year_of(d):
    return ('year', str(d.year), dt.date(d.year, 1, 1), dt.date(d.year, 12, 31))
def parse_key(kind, key):
    if kind == 'week':
        y, w = map(int, re.match(r'(\d{4})-W(\d{1,2})$', key).groups())
        return week_of(dt.date.fromordinal(dt.date(y, 1, 4).toordinal() - dt.date(y, 1, 4).weekday() + 7 * (w - 1)))
    if kind == 'month': return month_of(D(key + '-01'))
    if kind == 'quarter':
        y, q = map(int, re.match(r'(\d{4})-Q([1-4])$', key).groups()); return quarter_of(dt.date(y, 3 * q - 2, 1))
    if kind == 'semester':
        y, s = map(int, re.match(r'(\d{4})-S([12])$', key).groups()); return semester_of(dt.date(y, 6 * s - 5, 1))
    if kind == 'year': return year_of(dt.date(int(key), 1, 1))
OF = {'week': week_of, 'month': month_of, 'quarter': quarter_of, 'semester': semester_of, 'year': year_of}

jobs = []   # (kind, key, from, to, outfile)
try:
    if not args:
        jobs.append(('day', TODAY.isoformat(), TODAY, TODAY, P(OUTROOT, 'TODAY.log')))
    elif args[0] == 'day':
        d = D(args[1]) if len(args) > 1 else TODAY
        jobs.append(('day', d.isoformat(), d, d, P(OUTROOT, 'day', d.isoformat() + '.log')))
    elif args[0] in OF:
        kind = args[0]
        t = parse_key(kind, args[1]) if len(args) > 1 else OF[kind](TODAY)
        jobs.append(t + (P(OUTROOT, kind, t[1] + '.log'),))
    elif args[0] == 'period':
        a, b = sorted([D(args[1]), D(args[2])])
        key = '%s_%s' % (a, b)
        jobs.append(('period', key, a, b, P(OUTROOT, 'period', key + '.log')))
    elif args[0] == '--close':
        y = TODAY - dt.timedelta(1)
        jobs.append(('day', y.isoformat(), y, y, P(OUTROOT, 'day', y.isoformat() + '.log')))
        for kind, fn in OF.items():
            t = fn(y)
            if t[3] == y:   # the period ended yesterday
                jobs.append(t + (P(OUTROOT, kind, t[1] + '.log'),))
    else:
        raise ValueError
except (ValueError, IndexError, AttributeError):
    print(__doc__); sys.exit(1)

# ------------------------------------------------------------------ sources
HIST = P(STATE, 'JOBS_HISTORY.csv')
if not os.path.exists(HIST):
    print('No history yet (%s missing) - nothing to report.' % HIST); sys.exit(2)
raw = open(HIST, 'rb').read()
SHA = hashlib.sha256(raw).hexdigest()
def ts(s):
    try: return dt.datetime.strptime(s.strip()[:19], '%Y-%m-%dT%H:%M:%S')
    except ValueError: return None
RUNS = []
for row in csv.reader(raw.decode('utf-8', 'replace').splitlines()):
    if len(row) < 4: continue
    end = ts(row[0])
    if end is None: continue
    try: dur = float(row[5]) if len(row) > 5 and row[5] else 0.0
    except ValueError: dur = 0.0
    RUNS.append(dict(end=end, start=end - dt.timedelta(seconds=dur), job=row[1].strip(), status=row[3].strip().upper(),
                     log=row[4].strip() if len(row) > 4 else '', dur=dur))
RUNS.sort(key=lambda r: r['end'])
FIRST_DAY = RUNS[0]['end'].date() if RUNS else TODAY
JT = {}
if os.path.exists(P(APP_HOME, 'jobs_table.csv')):
    for r in csv.DictReader(open(P(APP_HOME, 'jobs_table.csv'), encoding='utf-8', errors='replace')):
        JT[r['JOB_ID']] = r
SCHED = {}
if os.path.exists(P(APP_HOME, 'schedules.csv')):
    for r in csv.DictReader(open(P(APP_HOME, 'schedules.csv'), encoding='utf-8', errors='replace')):
        if r.get('ENABLED', '1').strip() == '1': SCHED[r['JOB_ID']] = r['SCHEDULE'].strip()
OPS = json.load(open(P(HERE, 'daily_log_opsmap.json'), encoding='utf-8'))
FAMNAME = {'SECOPS': 'SecOps · security operations', 'BANKOPS': 'Banking operations', 'ITOPS': 'ITOps · the WEF engine',
           'CLOUDOPS': 'CloudOps', 'GITOPS': 'GitOps / DevOps'}
APPNAME = {'INFRA': 'Infrastructure', 'PKI': 'Internal PKI', 'DNS': 'Internal DNS', 'ES': 'Elasticsearch', 'LS': 'Logstash',
           'KB': 'Kibana', 'WAZ': 'Wazuh', 'WAG': 'Wazuh agent', 'FB': 'Filebeat', 'MB': 'Metricbeat', 'BEATS': 'Beats',
           'BEAC': 'Transactions'}
failed = lambda r: 'ECHEC' in r['status']
human = lambda r: r['status'].startswith('FORCE') or 'MARQUE' in r['status']

# the plan: what must run by itself
def cron_every(e):
    m = re.match(r'^\*/(\d+) \* \* \* \*$', e)
    if m: return int(m.group(1))
    return 60 if re.match(r'^0 \* \* \* \*$', e) else None
PLAN = [('INFRA_004_HEALTH_GUARDIAN', 'every 5 min', ('every', 5))]
for j, e in sorted(SCHED.items()):
    n = cron_every(e)
    if n and j != 'INFRA_004_HEALTH_GUARDIAN': PLAN.append((j, 'every %s' % ('%d min' % n if n < 60 else 'hour'), ('every', n)))
PLAN += [('WAZ_041_ALERT_CANARY', 'daily 06:00', ('at', 6)), ('INFRA_005_DISK_HYGIENE', 'Sunday 03:00', ('sunday', 3))]

def regs(name, a, b):
    f = P(STATE, name)
    if not os.path.exists(f): return []
    out = []
    for ln in open(f, encoding='utf-8', errors='replace').read().splitlines()[1:]:
        m = re.match(r'\s*(\d{4}-\d{2}-\d{2})T?(\d{2}:\d{2})?', ln)
        if m and a <= D(m.group(1)) <= b:
            out.append((m.group(1), m.group(2) or '', ln))
    return out

# ------------------------------------------------------------------ helpers
def hm(t): return t.strftime('%H:%M') if t else '--:--'
def dur(s):
    s = int(round(s or 0))
    return '%dh%02d' % (s // 3600, s % 3600 // 60) if s >= 3600 else '%d:%02d' % (s // 60, s % 60)
def cut(s, n): s = str(s); return s if len(s) <= n else s[:n - 1] + '…'
def pct(a, b): return '%d%%' % round(100.0 * a / b) if b else '-'
def delta(a, b):
    if not b: return ''
    d = 100.0 * (a - b) / b
    return '%+d%%' % round(d) if abs(d) >= 1 else '='
def rule(ch='─'): return ch * W
def title(n, t, sub=''):
    s = '%s  %s' % (n, t) if n else t
    return ['', s + ('   ' + sub if sub else ''), rule('─')]
def app_of(job):
    name = JT.get(job, {}).get('JOB_NAME', '')
    p = name.split('_')
    return (p[1], p[2]) if len(p) >= 3 and p[0] == 'WEF' else (job.split('_')[0], '?')
def tail(path, n=6):
    try:
        with open(path, 'rb') as f:
            f.seek(0, 2); size = f.tell(); f.seek(max(0, size - 4096))
            lines = f.read().decode('utf-8', 'replace').splitlines()
        return [l.rstrip() for l in lines if l.strip()][-n:]
    except OSError:
        return None

def verdict(job, rule_, day, runs_day):
    rs = runs_day.get((job, day), [])
    wend = min(NOW, dt.datetime.combine(day + dt.timedelta(1), dt.time()))
    window = max(0.0, (wend - dt.datetime.combine(day, dt.time())).total_seconds() / 60)
    kind, v = rule_
    first = min((r['start'] for r in rs), default=None)
    last = max((r['end'] for r in rs), default=None)
    if kind == 'every':
        exp = int(window // v)
        if exp == 0: return 'NOT DUE', '', exp, rs, first, last
        miss = exp - len(rs)
        return ('OK', '', exp, rs, first, last) if len(rs) >= 0.9 * exp - 1 else ('LATE', '%d missed' % miss, exp, rs, first, last)
    if kind == 'sunday' and day.weekday() != 6: return 'NOT DUE', '', 0, rs, first, last
    due = dt.datetime.combine(day, dt.time(v))
    if wend < due: return 'NOT YET', 'due %s' % hm(due), 1, rs, first, last
    if not rs: return 'MISSED', 'due %s' % hm(due), 1, rs, first, last
    if first > due + dt.timedelta(minutes=15):
        m = int((first - due).total_seconds() // 60)
        return 'LATE', '+%d:%02d' % (m // 60, m % 60), 1, rs, first, last
    return 'OK', '', 1, rs, first, last

# ------------------------------------------------------------------ one report
def build(kind, key, a, b):
    days = [a + dt.timedelta(n) for n in range((b - a).days + 1)]
    days = [d for d in days if d <= TODAY]
    nodata = [d for d in days if d < FIRST_DAY]
    days = [d for d in days if d >= FIRST_DAY] or [min(b, TODAY)]
    R = [r for r in RUNS if a <= r['end'].date() <= b]
    span = (b - a).days + 1
    pa, pb = a - dt.timedelta(span), a - dt.timedelta(1)
    PR = [r for r in RUNS if pa <= r['end'].date() <= pb]
    runs_day = defaultdict(list)
    for r in R + PR: runs_day[(r['job'], r['end'].date())].append(r)
    FA = [r for r in R if failed(r)]
    HU = [r for r in R if human(r)]
    chg = regs('CHANGE_LOG.csv', a, b); cfg = regs('CONFIG_AUDIT_TRAIL.csv', a, b); inc = regs('INCIDENTS.csv', a, b)
    # failures still open = last run of that job in the period is a failure
    lastrun = {}
    for r in R: lastrun[r['job']] = r
    still = sorted({j for j, r in lastrun.items() if failed(r)})
    # plan verdicts
    pv = []
    for job, rhythm, rl in PLAN:
        vs = [verdict(job, rl, d, runs_day) for d in days]
        pv.append((job, rhythm, rl, vs))
    late_items = [(job, d, v) for job, _, _, vs in pv for d, v in zip(days, vs) if v[0] in ('LATE', 'MISSED')]

    L = []
    head = {'day': 'DAILY LOG', 'week': 'WEEKLY REVIEW', 'month': 'MONTHLY REVIEW', 'quarter': 'QUARTERLY REVIEW',
            'semester': 'HALF-YEAR REVIEW', 'year': 'ANNUAL REVIEW', 'period': 'PERIOD REVIEW'}[kind]
    when = a.strftime('%A %d/%m/%Y') if kind == 'day' else '%s  →  %s   (%s, %d days)' % (a.strftime('%d/%m/%Y'), b.strftime('%d/%m/%Y'), key, span)
    L.append(rule('═'))
    left = 'WEF · %s · %s' % (head, when)
    L.append(left + org.rjust(W - len(left)))
    open_ = kind == 'day' and a == TODAY
    L.append('%s · built %s on %s · JOBS_HISTORY.csv %d runs · sha256 %s'
             % ('LIVE (every 15 min)' if open_ else 'CLOSED', NOW.strftime('%Y-%m-%d %H:%M'),
                socket.gethostname(), len(R), SHA[:12]))
    if nodata:
        L.append('history starts %s: %d day(s) before it are not judged' % (FIRST_DAY.strftime('%d/%m/%Y'), len(nodata)))
    L.append(rule('═'))
    # verdict
    bad = []
    if still: bad.append('%d job(s) still failing' % len(still))
    if late_items: bad.append('%d late / missed in the plan' % len(late_items))
    if not R: bad.append('NO RUN RECORDED - is the engine writing?')
    hum = len(HU) + len(chg) + len(cfg)
    if bad:
        L.append('VERDICT   ▲ ACTION   ' + '  ·  '.join(bad) + ('  ·  %d human action(s)' % hum if hum else ''))
    else:
        L.append('VERDICT   ✓ CLEAN    the plan ran on time, nothing is failing' + ('  ·  %d human action(s), all traced' % hum if hum else ''))

    # 1 at a glance
    L += title('1', 'GLANCE')
    ok = len(R) - len(FA)
    avg = sum(r['dur'] for r in R) / len(R) if R else 0
    pavg = sum(r['dur'] for r in PR) / len(PR) if PR else 0
    pfa = sum(1 for r in PR if failed(r))
    touched = sum(1 for o in OPS if any(r['job'] in o['jobs'] for r in R))
    L.append('   runs %-7d ok %-7d failed %-5d by hand %-5d jobs %-5d operations active %d/%d'
             % (len(R), ok, len(FA), len(HU), len({r['job'] for r in R}), touched, len(OPS)))
    L.append('   success %-4s   avg duration %-7s   runs %s   failures %s   avg duration %s'
             % (pct(ok, len(R)), dur(avg), delta(len(R), len(PR)) or '-', delta(len(FA), pfa) or ('=' if pfa == len(FA) else '-'), delta(avg, pavg) or '-'))
    if kind == 'day':
        sh = []
        for lab, h0, h1 in (('06-14', 6, 14), ('14-22', 14, 22), ('22-06', 22, 30)):
            rs = [r for r in R if h0 <= (r['end'].hour + (24 if r['end'].hour < 6 else 0)) < h1]
            sh.append('%s: %d runs %d ko %d hand' % (lab, len(rs), sum(map(failed, rs)), sum(map(human, rs))))
        L.append('   shifts    ' + ' | '.join(sh))
        hours = Counter(r['end'].hour for r in R)
        if hours:
            bars = ''.join(' ▁▂▃▄▅▆▇█'[min(8, round(8 * hours.get(h, 0) / max(hours.values())))] for h in range(24))
            L.append('   per hour  00 %s 23   busiest %02dh (%d runs)' % (bars, hours.most_common(1)[0][0], hours.most_common(1)[0][1]))
    else:
        # day-by-day (or month-by-month for long periods)
        L.append('')
        if span <= 62:
            L.append('   %-12s %6s %6s %6s %8s %8s  %s' % ('day', 'runs', 'failed', 'hand', 'late', 'avg', ''))
            mx = max([sum(1 for r in R if r['end'].date() == d) for d in days] or [1]) or 1
            for d in days:
                rs = [r for r in R if r['end'].date() == d]
                lt = sum(1 for x in late_items if x[1] == d)
                L.append('   %-12s %6d %6d %6d %8s %8s  %s' % (d.strftime('%a %d/%m'), len(rs), sum(map(failed, rs)), sum(map(human, rs)),
                         lt or '', dur(sum(r['dur'] for r in rs) / len(rs)) if rs else '', '█' * round(30 * len(rs) / mx)))
        else:
            L.append('   %-12s %6s %6s %6s %8s %8s' % ('month', 'runs', 'failed', 'hand', 'late', 'avg'))
            for mkey in sorted({d.strftime('%Y-%m') for d in days}):
                rs = [r for r in R if r['end'].strftime('%Y-%m') == mkey]
                lt = sum(1 for x in late_items if x[1].strftime('%Y-%m') == mkey)
                L.append('   %-12s %6d %6d %6d %8s %8s' % (mkey, len(rs), sum(map(failed, rs)), sum(map(human, rs)), lt or '',
                         dur(sum(r['dur'] for r in rs) / len(rs)) if rs else ''))

    # 2 the plan
    L += title('2', 'PLAN')
    if kind == 'day':
        L.append('     %-28s %-13s %6s %5s %6s %6s  %s' % ('job', 'rhythm', 'expect', 'ran', 'first', 'last', 'verdict'))
        for job, rhythm, rl, vs in pv:
            v, why, exp, rs, f_, l_ = vs[0]
            L.append('   %s %-28s %-13s %6s %5d %6s %6s  %s' % (dot(v), cut(job, 28), rhythm, exp if exp else '-', len(rs), hm(f_), hm(l_),
                     (v + '  ' + why).strip() + (' → see 5' if v in ('LATE', 'MISSED') else '')))
    else:
        L.append('   %-34s %-14s %6s %8s %6s %7s  %s' % ('job', 'rhythm', 'due', 'on time', 'late', 'missed', 'on-time rate'))
        for job, rhythm, rl, vs in pv:
            due = [v for v in vs if v[0] not in ('NOT DUE', 'NOT YET')]
            on = sum(1 for v in due if v[0] == 'OK'); lt = sum(1 for v in due if v[0] == 'LATE'); ms = sum(1 for v in due if v[0] == 'MISSED')
            L.append('   %-34s %-14s %6d %8d %6d %7d  %s' % (cut(job, 34), rhythm, len(due), on, lt, ms, pct(on, len(due))))
        if late_items:
            L.append('   late or missed: ' + ', '.join('%s %s %s' % (d.strftime('%d/%m'), j.split('_')[0] + '_' + j.split('_')[1], v[1] or v[0])
                                              for j, d, v in late_items[:12]) + (' …' if len(late_items) > 12 else ''))

    # 3 the factory tree
    L += title('3', 'FACTORY')
    byjob = defaultdict(list)
    for r in R: byjob[r['job']].append(r)
    covered = set()
    idle = []
    cur = [None, None]
    for o in OPS:
        rs = [r for j in o['jobs'] for r in byjob.get(j, [])]
        covered.update(o['jobs'])
        if not rs:
            idle.append(o['id']); continue
        if o['fam'] != cur[0]:
            cur = [o['fam'], None]; L.append(''); L.append(FAMNAME.get(o['fam'], o['fam']).upper())
        if o['disc'] != cur[1]:
            cur[1] = o['disc']; L.append('  └─ ' + o['disc'])
        nko = sum(map(failed, rs))
        L.append('       └─ %-9s %-52s %4d run%s %s' % (o['id'], cut(o['title'], 52), len(rs), 's' if len(rs) > 1 else ' ',
                 ('✓' if not nko else '✗ %d failed' % nko)))
        for j in o['jobs']:
            js = byjob.get(j)
            if not js: continue
            L.append('            ' + job_line(j, js, kind))
    other = sorted(j for j in byjob if j not in covered)
    if other:
        L.append(''); L.append('ENGINE JOBS OUTSIDE THE OPERATIONS MAP  (guardians, build and run lines)')
        cur_app = None
        for j in sorted(other, key=lambda j: (app_of(j)[1], app_of(j)[0], j)):
            ap, line = app_of(j)
            if (ap, line) != cur_app:
                cur_app = (ap, line); L.append('  └─ %s line · %s' % (line, APPNAME.get(ap, ap)))
            L.append('       ' + job_line(j, byjob[j], kind))
    if idle:
        L.append('')
        L += textwrap.wrap('not run in this %s (%d): %s' % ('day' if kind == 'day' else 'period', len(idle), ', '.join(idle)),
                           W, initial_indent='   ', subsequent_indent='      ')

    # 4 failures with their sysout
    L += title('4', 'FAILURES')
    if not FA:
        L.append('   none')
    shown = FA[-12:] if kind == 'day' else FA[-10:]
    if kind != 'day' and FA:
        rec = Counter(r['job'] for r in FA).most_common(8)
        L.append('   by job: ' + ', '.join('%s ×%d' % (j, n) for j, n in rec))
        L.append('   the last %d:' % len(shown))
    for r in shown:
        after = [x for x in RUNS if x['job'] == r['job'] and x['end'] > r['end']]
        nxt = after[0] if after else None
        fate = ('then OK at %s (%s)' % (nxt['end'].strftime('%d/%m %H:%M'), nxt['status']) if nxt and not failed(nxt)
                else 'STILL FAILING' if not nxt else 'failed again at %s' % nxt['end'].strftime('%d/%m %H:%M'))
        L.append('   %s → %s  %-34s %-11s %s' % (r['start'].strftime('%d/%m %H:%M'), hm(r['end']), cut(r['job'], 34), r['status'], fate))
        t = tail(r['log']) if r['log'] else None
        L.append('        log  %s' % (r['log'] or '(no log path)'))
        if t:
            for ln in t: L.append('        │ ' + cut(ln, W - 10))
        elif r['log']:
            L.append('        │ (log not readable from here)')

    # 5 human actions
    L += title('5', 'ACTIONS')
    if not (HU or chg or cfg or inc): L.append('   none - the factory ran alone')
    for r in HU[-15:]:
        L.append('   %s  %-34s %s' % (r['end'].strftime('%d/%m %H:%M'), cut(r['job'], 34), r['status']))
    for d, t, ln in chg[-15:]:
        f = next(csv.reader([ln]))
        L.append('   %s %s  order   %-30s %s' % (d[8:10] + '/' + d[5:7], t, cut(f[1] if len(f) > 1 else '', 30), cut(f[2] if len(f) > 2 else '', 40)))
    for d, t, ln in cfg[-15:]:
        f = next(csv.reader([ln]))
        L.append('   %s %s  lever   %-30s %s → %s' % (d[8:10] + '/' + d[5:7], t, cut(f[1] if len(f) > 1 else '', 30),
                 cut(f[2] if len(f) > 2 else '', 18), cut(f[3] if len(f) > 3 else '', 18)))
    for d, t, ln in inc[-15:]:
        L.append('   %s %s  incident %s' % (d[8:10] + '/' + d[5:7], t, cut(ln[len(d):].lstrip(' ,T0123456789:+'), 80)))
    if late_items and kind == 'day':
        L.append('   late or missed in the plan: write why in the incident register if it was not the machine')

    # 6 handover (day) / 7 trajectory
    if kind == 'day':
        L += title('6', 'HANDOVER')
        L.append('   still failing   ' + (', '.join(still) if still else 'nothing'))
        nxt = []
        base = dt.datetime.combine(a, dt.time(23, 59)) if a < TODAY else NOW
        for job, rhythm, (k, v) in PLAN:
            if k == 'at':
                t = dt.datetime.combine(base.date(), dt.time(v))
                if t < base: t += dt.timedelta(1)
                nxt.append((t, job))
            if k == 'sunday':
                dd = base.date() + dt.timedelta((6 - base.weekday()) % 7)
                t = dt.datetime.combine(dd, dt.time(v))
                if t < base: t += dt.timedelta(7)
                nxt.append((t, job))
        L.append('   next in plan    ' + '   '.join('%s %s' % (t.strftime('%a %H:%M'), j) for t, j in sorted(nxt)))
        L.append('   always running  ' + ', '.join('%s (%s)' % (j, r) for j, r, (k, _) in PLAN if k == 'every'))
    L += title('7' if kind == 'day' else '6', 'TRAJECTORY')
    opp = []
    pb_ = defaultdict(list)
    for r in PR: pb_[r['job']].append(r['dur'])
    drift = []
    for j, rs in byjob.items():
        if len(rs) >= 2 and len(pb_.get(j, [])) >= 2:
            x = sum(r['dur'] for r in rs) / len(rs); y = sum(pb_[j]) / len(pb_[j])
            if y >= 5 and x > 1.3 * y: drift.append((x / y, j, x, y))
    for ratio, j, x, y in sorted(drift, reverse=True)[:5]:
        opp.append('slower   %-34s %s → %s (%+d%%) - look before it fails' % (cut(j, 34), dur(y), dur(x), round(100 * (ratio - 1))))
    for j, n in Counter(r['job'] for r in FA).most_common():
        if n >= 3: opp.append('repeats  %-34s %d failures - fix one cause, not %d replays' % (cut(j, 34), n, n))
    for job, rhythm, rl, vs in pv:
        due = [v for v in vs if v[0] not in ('NOT DUE', 'NOT YET')]
        if due and sum(1 for v in due if v[0] == 'OK') < len(due):
            opp.append('rhythm   %-34s on time %s - check the scheduler first' % (cut(job, 34), pct(sum(1 for v in due if v[0] == 'OK'), len(due))))
    if kind != 'day' and idle:
        opp.append('idle     %d operation(s) never ran this period - needed? scheduled? or a line still to build' % len(idle))
    if hum and len(R):
        opp.append('by hand  %d human action(s) for %d runs - each repeated one is a candidate to automate' % (hum, len(R)))
    L += ['   ' + o for o in opp] or ['   nothing to report - steady']
    L.append('')
    L.append(rule('═'))
    L.append('Built by the server from what really ran - nobody typed it. Keep 12 months (PCI DSS 10.5.1).')
    L.append('ISO 27001 A.5.37 procedures run & traced · A.8.15 logging · A.8.16 monitoring · ITIL 4 monitoring')
    L.append(rule('═'))
    out = []
    for ln in L:
        if vlen(ln) <= W:
            out.append(ln); continue
        ind = len(ln) - len(ln.lstrip(' '))
        out += textwrap.wrap(ln, W, initial_indent='', subsequent_indent=' ' * (ind + 6), drop_whitespace=True)
    return '\n'.join(paint(ln) for ln in out) + '\n'

def job_line(j, js, kind):
    nko = sum(map(failed, js))
    if kind == 'day':
        last = js[-1]
        if len(js) == 1:
            t = '%s → %s  %7s' % (hm(last['start']), hm(last['end']), dur(last['dur']))
        else:
            t = '%s → %s  ×%-5d' % (hm(js[0]['start']), hm(last['end']), len(js))
        res = 'OK' if not nko else ('%s' % last['status'] if len(js) == 1 else '%d failed, last %s' % (nko, last['status']))
        return '%-32s %s  avg %-5s %s' % (cut(j, 32), t, dur(sum(r['dur'] for r in js) / len(js)), res)
    return '%-32s ×%-5d avg %-5s max %-5s last %s %s' % (cut(j, 32), len(js), dur(sum(r['dur'] for r in js) / len(js)),
            dur(max(r['dur'] for r in js)), js[-1]['end'].strftime('%d/%m %H:%M'), ('✓' if not nko else '✗ %d failed' % nko))

written = []
for kind, key, a, b, out in jobs:
    txt = build(kind, key, a, b)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f: f.write(txt)
    written.append(out)
    if kind == 'day' and a == TODAY and not out.endswith('TODAY.log'):
        with open(P(OUTROOT, 'TODAY.log'), 'w', encoding='utf-8') as f: f.write(txt)
if not args:
    sys.stdout.write(open(written[0], encoding='utf-8').read())
for w in written: print('written: ' + w)
