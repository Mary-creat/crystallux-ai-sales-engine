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


def unguarded_switches(d):
    """Switch nodes that can silently swallow a request.

    In a responseMode=responseNode workflow, an input matching no Switch branch
    reaches no Respond node and the caller gets a bodyless 200 -- which reads
    as a broken endpoint rather than a rejected request. A fallbackOutput
    routes the miss somewhere instead. Reported as a warning, not a failure:
    several long-standing workflows have this and blocking on them would just
    train people to ignore the tool.
    """
    if not any(n.get('parameters', {}).get('responseMode') == 'responseNode'
               for n in d.get('nodes', [])):
        return []
    out = []
    for n in d.get('nodes', []):
        if n.get('type', '').endswith('.switch'):
            fb = (n.get('parameters', {}).get('options') or {}).get('fallbackOutput')
            if fb in (None, 'none'):
                out.append(n.get('name', '?'))
    return out


def dead_end_nodes(d):
    """Nodes that end a branch reachable from a WEBHOOK without responding.

    Same failure as an unguarded Switch, one step further along: a branch
    runs to its last node, that node is not a Respond node, and the caller
    is left holding a bodyless 200. The repo has hit the empty-200 trap
    four separate times (see CLAUDE.md), so this is a failure rather than
    a warning.

    Reachability is computed from webhook triggers ONLY. A workflow can
    carry both a schedule and a webhook -- clx-b2c-discovery-v2.1 does,
    one entry for the house pool and one for tenant-scoped runs -- and a
    schedule-driven branch has no HTTP caller to answer. Flagging its
    terminal node would be a false positive, and a check that cries wolf
    gets ignored.

    Disabled nodes and the TEST HARNESS / DELIBERATELY DISCONNECTED
    annotations are honoured, same as the unreachable-node check.
    """
    nodes = d.get('nodes', [])
    webhooks = [n.get('name') for n in nodes
                if n.get('type', '').endswith('webhook')
                and n.get('parameters', {}).get('responseMode') == 'responseNode']
    if not webhooks:
        return []

    conns = d.get('connections') or {}

    def outgoing(name):
        return [c.get('node') for br in (conns.get(name, {}).get('main') or [])
                for c in (br or []) if c.get('node')]

    by_name = {n.get('name'): n for n in nodes}

    # Traversal stops AT a Respond node. Once a branch has answered the
    # caller, whatever it does afterwards owes them nothing -- a workflow
    # may legitimately reply 202 and then carry on working, which is what
    # discovery/tenant-scan does. Continuing past the responder would
    # flag every node downstream of an early reply.
    seen, stack = set(), list(webhooks)
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        if 'respondToWebhook' in (by_name.get(cur, {}).get('type') or ''):
            continue
        stack.extend(outgoing(cur))

    out = []
    for n in nodes:
        name = n.get('name')
        if name not in seen:
            continue
        ntype = n.get('type', '')
        if ntype.endswith('webhook') or ntype.endswith('.stickyNote'):
            continue
        if 'respondToWebhook' in ntype:
            continue
        if n.get('disabled'):
            continue
        note = (n.get('notes') or '').upper()
        if 'TEST HARNESS' in note or 'DELIBERATELY DISCONNECTED' in note:
            continue
        if not outgoing(name):
            out.append(name or '?')
    return out


def main(argv):
    paths = [p.replace('\\', '/') for p in argv[1:]]
    problems = []
    warnings = []
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
        for sw in unguarded_switches(d):
            warnings.append('%s: Switch %r has no fallbackOutput; an unmatched '
                            'input answers with an empty 200' % (name, sw))

        for dead in dead_end_nodes(d):
            problems.append('%s: node %r ends a branch without reaching a '
                            'Respond node; the caller gets an empty 200'
                            % (name, dead))

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
            notes_by_name = {n.get('name'): (n.get('notes') or '') for n in nodes}
            for orphan in sorted(names - seen):
                if not orphan:
                    continue
                # An orphan annotated as intentional is a test harness or a
                # retired branch, not a mistake. Anything else is reported.
                note = notes_by_name.get(orphan, '').upper()
                if 'TEST HARNESS' in note or 'DELIBERATELY DISCONNECTED' in note:
                    continue
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
    if warnings:
        print()
        print('  warnings (not failures):')
        for w in warnings:
            print('    ' + w)
    print()
    print('%d workflow(s) checked, %d problem(s), %d warning(s)'
          % (checked, len(problems), len(warnings)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
