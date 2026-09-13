# -*- coding: utf-8 -*-
"""Every column a workflow selects must exist in the table it selects from.

WHY THIS EXISTS

clients.vertical was selected by five workflows and has never been a
column. clients.daily_digest_opt_in and booking_alerts_opt_in were read
AND written by the Settings page and never existed either. PostgREST
answers 400, n8n turns that into an empty or error payload, and the page
says "Request failed." with nothing behind it to fix -- because the fault
is the schema, not the code.

Read-only. Needs SUPABASE_SERVICE_KEY + SUPABASE_PROJECT_ID in .env.

  python scripts/audit/schema-drift.py
"""
import json, io, os, re, glob, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def load_env():
    p = os.path.join(ROOT, '.env')
    if not os.path.exists(p): return
    for line in io.open(p, encoding='utf-8', errors='ignore'):
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line: continue
        k, v = line.split('=', 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

load_env()
KEY = os.environ.get('SUPABASE_SERVICE_KEY')
PID = os.environ.get('SUPABASE_PROJECT_ID')
if not KEY or not PID:
    print('SUPABASE_SERVICE_KEY / SUPABASE_PROJECT_ID missing from .env')
    sys.exit(2)
BASE = 'https://%s.supabase.co/rest/v1' % PID

_cache = {}
def columns(table):
    """One sample row is enough to learn the column names."""
    if table in _cache: return _cache[table]
    req = urllib.request.Request('%s/%s?select=*&limit=1' % (BASE, table),
                                 headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY})
    try:
        body = json.loads(urllib.request.urlopen(req, timeout=30).read().decode('utf-8'))
        cols = set(body[0].keys()) if body else None   # None = empty table, cannot tell
    except Exception:
        cols = None
    _cache[table] = cols
    return cols

# /rest/v1/<table>?...select=<list>. The list may contain embedded
# resources -- clients(id,name) -- which are joins, not columns, so the
# capture has to include parentheses in order to strip them.
PAT = re.compile(r"/rest/v1/([a-z0-9_]+)\?[^'\"]*?select=([a-zA-Z0-9_,().:*]+)")

def plain_columns(sel):
    """Drop embedded resources, aggregates, aliases and *.

    clients(id,name) is a join. count() is an aggregate. alias:col renames.
    None of them is a column on the parent table, and treating them as one
    is how an audit cries wolf."""
    out, depth, buf = [], 0, ''
    for ch in sel:
        if ch == '(':
            depth += 1
            buf = ''          # the name before '(' was an embed, not a column
            continue
        if ch == ')':
            depth -= 1
            continue
        if depth:
            continue
        if ch == ',':
            if buf: out.append(buf)
            buf = ''
            continue
        buf += ch
    if buf: out.append(buf)
    cleaned = []
    for c in out:
        if not c or c == '*':
            continue
        if ':' in c:            # alias:real_column -- check the real one
            c = c.split(':', 1)[1]
        cleaned.append(c)
    return cleaned

findings, checked, skipped = [], 0, set()
for path in sorted(glob.glob(os.path.join(ROOT, 'workflows', '**', '*.json'), recursive=True)):
    src = io.open(path, encoding='utf-8').read()
    for table, sel in PAT.findall(src):
        cols = columns(table)
        if cols is None:
            skipped.add(table); continue
        checked += 1
        missing = [c for c in plain_columns(sel) if c not in cols]
        if missing:
            findings.append((os.path.relpath(path, ROOT).replace(os.sep, '/'), table, missing))

print()
if findings:
    print('SCHEMA DRIFT -- %d select list(s) name a column that does not exist' % len(findings))
    print()
    for f, table, miss in findings:
        print('  %s' % f)
        print('      %s  ->  %s' % (table, ', '.join(miss)))
else:
    print('No schema drift: every selected column exists.')
print()
print('  %d select list(s) checked across %d table(s)' % (checked, len(_cache)))
if skipped:
    print('  %d table(s) empty or unreadable, so not checked: %s'
          % (len(skipped), ', '.join(sorted(skipped))))
print()
sys.exit(1 if findings else 0)
