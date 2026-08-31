#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compare the LIVE n8n workflow definition against the repo, node by node.

    python scripts/n8n/compare-live-vs-repo.py workflows/clx-lead-research-v2.json
    python scripts/n8n/compare-live-vs-repo.py            # every workflow with a top-level id

Three deploys reported success while the live behaviour said otherwise, and
each answer had to be reconstructed from column values and timestamps hours
later. That reconstruction was wrong once. This reads what is actually
running instead of inferring it.

Reports, per workflow:
  * active state
  * nodes present live but not in the repo, and the reverse
  * nodes whose parameters differ, with the first differing key named
  * whether the live definition matches the repo at all

Exit 0 when everything matches, 1 on any difference, 2 when the API is
unreachable -- so CI can gate on drift once a working key exists.

Reads N8N_URL and N8N_API_KEY from .env. Never prints either.
"""
import io
import json
import os
import sys
import urllib.error
import urllib.request

INTERESTING = ('parameters', 'credentials', 'type', 'disabled', 'onError',
               'alwaysOutputData')


def env():
    cfg = {}
    path = '.env'
    if os.path.exists(path):
        for line in io.open(path, encoding='utf-8', errors='ignore'):
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    url = (cfg.get('N8N_URL') or os.environ.get('N8N_URL') or
           'https://automation.crystallux.org').rstrip('/')
    key = cfg.get('N8N_API_KEY') or os.environ.get('N8N_API_KEY') or ''
    return url, key


def fetch(url, key, wid):
    req = urllib.request.Request(url + '/api/v1/workflows/' + wid,
                                 headers={'X-N8N-API-KEY': key,
                                          'Accept': 'application/json'})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=30).read().decode('utf-8')), None
    except urllib.error.HTTPError as e:
        return None, 'HTTP %s' % e.code
    except Exception as e:                                    # noqa: BLE001
        return None, str(e)[:120]


def first_difference(a, b, path=''):
    """Name the first place two node bodies diverge, rather than dumping both."""
    if type(a) is not type(b):
        return path or '(type)'
    if isinstance(a, dict):
        for k in sorted(set(list(a.keys()) + list(b.keys()))):
            if k not in a:
                return (path + '.' + k).lstrip('.') + ' (only live)'
            if k not in b:
                return (path + '.' + k).lstrip('.') + ' (only repo)'
            d = first_difference(a[k], b[k], (path + '.' + k).lstrip('.'))
            if d:
                return d
        return None
    if isinstance(a, list):
        if len(a) != len(b):
            return (path or '(list)') + ' length %d vs %d' % (len(a), len(b))
        for i, (x, y) in enumerate(zip(a, b)):
            d = first_difference(x, y, '%s[%d]' % (path, i))
            if d:
                return d
        return None
    return None if a == b else (path or '(value)')


def compare(path, url, key):
    repo = json.load(io.open(path, encoding='utf-8'))
    wid = repo.get('id')
    name = os.path.basename(path)
    if not wid:
        print('  %-46s SKIP  no top-level id' % name)
        return 0

    live, err = fetch(url, key, wid)
    if err:
        print('  %-46s UNREADABLE  %s' % (name, err))
        return 2

    problems = []
    live_nodes = {n.get('name'): n for n in live.get('nodes', [])}
    repo_nodes = {n.get('name'): n for n in repo.get('nodes', [])}

    for missing in sorted(set(repo_nodes) - set(live_nodes)):
        problems.append('node %r is in the repo and NOT live' % missing)
    for extra in sorted(set(live_nodes) - set(repo_nodes)):
        problems.append('node %r is live and NOT in the repo' % extra)

    for n in sorted(set(live_nodes) & set(repo_nodes)):
        a = dict((k, live_nodes[n].get(k)) for k in INTERESTING)
        b = dict((k, repo_nodes[n].get(k)) for k in INTERESTING)
        # n8n returns credentials with an id it assigned; the repo carries
        # name only by convention, so compare on name alone.
        for side in (a, b):
            creds = side.get('credentials') or {}
            side['credentials'] = dict(
                (t, (c or {}).get('name')) for t, c in creds.items())
        d = first_difference(a, b)
        if d:
            problems.append('node %r differs at %s' % (n, d))

    state = 'active' if live.get('active') else 'INACTIVE'
    if problems:
        print('  %-46s DRIFT (%s)' % (name, state))
        for p in problems[:12]:
            print('        ' + p)
        if len(problems) > 12:
            print('        ... and %d more' % (len(problems) - 12))
        return 1

    print('  %-46s matches repo (%s, %d nodes)' % (name, state, len(repo_nodes)))
    return 0


def main(argv):
    url, key = env()
    if not key:
        print('N8N_API_KEY is not set in .env')
        return 2

    paths = argv[1:]
    if not paths:
        paths = []
        for root, _d, files in os.walk('workflows'):
            for f in sorted(files):
                if f.endswith('.json'):
                    paths.append(os.path.join(root, f))

    print('Comparing %d workflow(s) against %s\n' % (len(paths), url))
    worst = 0
    for p in paths:
        worst = max(worst, compare(p.replace('\\', '/'), url, key))
    print()
    print({0: 'live matches repo', 1: 'DRIFT FOUND', 2: 'could not read n8n'}[worst])
    return worst


if __name__ == '__main__':
    sys.exit(main(sys.argv))
