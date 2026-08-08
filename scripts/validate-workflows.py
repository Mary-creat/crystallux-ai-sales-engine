#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Static checks on n8n workflow JSON before shipping it to the VPS.

    python scripts/validate-workflows.py                 # everything
    python scripts/validate-workflows.py path/to/wf.json # specific files

Catches the failure modes this repo has actually hit:

  * invalid JSON
  * connections naming a node that does not exist (silent dead branch)
  * $('Node Name') referring to a node that does not exist
  * credentials carrying an `id` -- must be name-only, n8n resolves by name
    on import (see docs feedback_workflow_credentials)
  * duplicate webhook paths or workflow ids across files, which is how the
    live instance ended up with squatted webhook registrations
  * Code nodes whose JavaScript does not parse (needs node on PATH)
  * Code nodes using $input.all() while set to runOnceForEachItem, the bug
    behind commits 0fb1b2d and fb3c8eb

Exit 0 clean, 1 on any problem.
"""
import io
import json
import os
import re
import subprocess
import sys
import tempfile

REF_RE = re.compile(r"\$\('([^']+)'\)")
ALL_RE = re.compile(r"\$input\.all\(\)")


def iter_workflows(paths):
    if paths:
        for p in paths:
            yield p
        return
    for root, _dirs, files in os.walk('workflows'):
        for f in sorted(files):
            if f.endswith('.json'):
                yield os.path.join(root, f)


def node_js_ok(src, tmpdir, tag):
    """Return None if the JS parses, else the parser message."""
    path = os.path.join(tmpdir, tag + '.js')
    # async, because n8n Code nodes permit top-level await and a plain function
    # wrapper would report every one of them as a syntax error.
    io.open(path, 'w', encoding='utf-8').write('async function __n(){\n' + src + '\n}\n')
    try:
        r = subprocess.run(['node', '--check', path],
                           capture_output=True, text=True)
    except (OSError, FileNotFoundError):
        return None                      # no node available; skip quietly
    if r.returncode == 0:
        return None
    return (r.stderr or '').strip().split('\n')[0][:160]


def main(argv):
    paths = [p.replace('\\', '/') for p in argv[1:]]
    problems = []
    webhook_owner = {}
    id_owner = {}
    checked = 0

    tmpdir = tempfile.mkdtemp(prefix='clxwf')

    for path in iter_workflows(paths):
        norm = path.replace('\\', '/')
        name = os.path.basename(norm)
        try:
            d = json.load(io.open(norm, encoding='utf-8'))
        except ValueError as e:
            problems.append('%s: invalid JSON -- %s' % (name, e))
            continue
        checked += 1

        nodes = d.get('nodes', [])
        names = set(n.get('name') for n in nodes)

        wid = d.get('id')
        if wid:
            if wid in id_owner:
                problems.append('%s: workflow id %r also used by %s'
                                % (name, wid, id_owner[wid]))
            else:
                id_owner[wid] = name

        adj = {}
        for src, conn in (d.get('connections') or {}).items():
            if src not in names:
                problems.append('%s: connection from unknown node %r' % (name, src))
            adj.setdefault(src, [])
            for out in conn.get('main', []):
                for c in (out or []):
                    if c.get('node') not in names:
                        problems.append('%s: connection to unknown node %r'
                                        % (name, c.get('node')))
                    else:
                        adj[src].append(c['node'])

        # Unreachable nodes. Rewiring a chain can orphan a node while leaving
        # its own outgoing connections intact, so nothing else here notices --
        # and an orphaned IF means a validation gate silently stops running.
        triggers = [n.get('name') for n in nodes
                    if 'trigger' in n.get('type', '').lower()
                    or n.get('type', '').endswith('webhook')]
        if triggers:
            seen, stack = set(), list(triggers)
            while stack:
                cur = stack.pop()
                if cur in seen:
                    continue
                seen.add(cur)
                stack.extend(adj.get(cur, []))
            for orphan in sorted(names - seen):
                if orphan:
                    problems.append('%s: node %r is unreachable from any trigger'
                                    % (name, orphan))

        for n in nodes:
            nname = n.get('name', '?')
            params = n.get('parameters', {})
            blob = json.dumps(params, ensure_ascii=False)

            for cred_type, cred in (n.get('credentials') or {}).items():
                if isinstance(cred, dict) and 'id' in cred:
                    problems.append('%s: node %r credential %s carries an id; '
                                    'use name only' % (name, nname, cred_type))

            for ref in REF_RE.findall(blob):
                if ref not in names:
                    problems.append('%s: node %r references unknown node $(%r)'
                                    % (name, nname, ref))

            if n.get('type', '').endswith('webhook'):
                wpath = params.get('path')
                if wpath:
                    if wpath in webhook_owner:
                        problems.append('%s: webhook path %r also served by %s'
                                        % (name, wpath, webhook_owner[wpath]))
                    else:
                        webhook_owner[wpath] = name

            if n.get('type', '').endswith('.code'):
                js = params.get('jsCode', '')
                mode = params.get('mode', 'runOnceForAllItems')
                if ALL_RE.search(js) and mode == 'runOnceForEachItem':
                    problems.append('%s: node %r uses $input.all() but runs '
                                    'once per item' % (name, nname))
                err = node_js_ok(js, tmpdir, '%s_%s' % (
                    os.path.splitext(name)[0][:24], n.get('id', 'x')))
                if err:
                    problems.append('%s: node %r JS does not parse -- %s'
                                    % (name, nname, err))

    for p in problems:
        print('  ' + p)
    print()
    print('%d workflow(s) checked, %d problem(s)' % (checked, len(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
