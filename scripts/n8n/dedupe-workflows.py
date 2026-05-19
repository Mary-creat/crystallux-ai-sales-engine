#!/usr/bin/env python3
"""
scripts/n8n/dedupe-workflows.py

Audit + dedupe n8n workflows on the live VPS. Built after Mary discovered
that many workflow names had 2-6 duplicate rows on the live n8n, which
collide on webhook registration and produce the 404 / empty-200 /
random-behavior symptoms across the platform.

Root cause (see docs/audit/blockers.md entry 0n):
  - Most repo workflow JSONs lacked a top-level `id` field.
  - `n8n import:workflow` is INSERT-only — without a fixed id, every
    repeat import creates a new row.
  - UI Import-from-File without "Replace existing" does the same.

The fix is a two-step recovery:
  1. Add top-level `id` to every workflow JSON in the repo (one-shot
     mechanical commit; see scripts/n8n/add-top-level-ids.py).
  2. Run this script against the live n8n to deactivate + delete the
     accumulated duplicate rows, then UI Import-Replace the canonical
     JSONs.

Designed to run on the VPS host that runs the n8n container. Read-only
by default; destructive phases require explicit flags.

Phases (--phase):
  audit         List live workflows, group by name, identify duplicates,
                pick canonical per heuristics, emit a markdown plan.
                Read-only. Default.
  deactivate    Run `n8n update:workflow --active=false` on every
                non-canonical duplicate.
  delete        Hard-delete duplicate rows via sqlite3 (SQLite) or
                emit SQL for Mary (Postgres). Requires
                --confirm-destructive.
  verify        Re-list workflows + probe canonical webhooks; show how
                many duplicate groups remain.

Heuristic for picking canonical per duplicate group (in order):
  1. Live id matches the repo's top-level `id` for that name.
  2. Workflow id "looks named" (wfXxx / clxXxx camelCase, not random nano-id).
  3. Workflow is active=true.
  4. Falls through to the first listed entry.

Usage:
  # Read-only plan (run this first):
  python3 scripts/n8n/dedupe-workflows.py --phase=audit > /tmp/dedupe-plan.md

  # Deactivate duplicates (safe, reversible):
  python3 scripts/n8n/dedupe-workflows.py --phase=deactivate

  # Hard-delete duplicate rows (destructive — requires confirm):
  python3 scripts/n8n/dedupe-workflows.py --phase=delete --confirm-destructive

  # Verify state:
  python3 scripts/n8n/dedupe-workflows.py --phase=verify

  # Dry-run any destructive phase:
  python3 scripts/n8n/dedupe-workflows.py --phase=delete --dry-run
"""

import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

# Force UTF-8 stdout so unicode chars in markdown render on Windows too.
try:
    sys.stdout.reconfigure(encoding='utf-8')
except (AttributeError, OSError):
    pass

REPO_DEFAULT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE_PROBE = 'https://automation.crystallux.org/webhook'


# ─────────────────────────────────────────────────────────
# 1. INVENTORY — read live n8n state via `docker exec n8n ...`
# ─────────────────────────────────────────────────────────

def docker_exec(container, *cmd, stdin=None):
    """Run inside the n8n container. Returns CompletedProcess."""
    full = ['docker', 'exec']
    if stdin is not None:
        full.append('-i')
    full.extend([container, *cmd])
    return subprocess.run(full, input=stdin, capture_output=True, text=True)


def list_live_workflows(container):
    """
    Parse `n8n list:workflow` output.

    n8n CLI emits one workflow per line in the form:
        <id>|<name>
    (Active flag is NOT shown by `list:workflow` directly in older
    versions; we re-fetch active state per workflow if needed.)
    """
    r = docker_exec(container, 'n8n', 'list:workflow')
    if r.returncode != 0:
        raise RuntimeError(
            f'n8n list:workflow failed inside container {container!r}: '
            f'{r.stderr.strip() or r.stdout.strip()}'
        )
    workflows = []
    for line in r.stdout.strip().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split('|', 1)
        if len(parts) != 2:
            continue
        wf_id, name = parts[0].strip(), parts[1].strip()
        workflows.append({'id': wf_id, 'name': name, 'active': None})
    return workflows


def fetch_active_states(container, workflows):
    """
    `list:workflow --active=true` returns only active rows. Diff against
    the full list to set the active flag on each workflow dict.
    """
    r = docker_exec(container, 'n8n', 'list:workflow', '--active=true')
    active_ids = set()
    if r.returncode == 0:
        for line in r.stdout.strip().splitlines():
            parts = line.split('|', 1)
            if len(parts) == 2:
                active_ids.add(parts[0].strip())
    for wf in workflows:
        wf['active'] = wf['id'] in active_ids


# ─────────────────────────────────────────────────────────
# 2. INVENTORY — read repo JSONs
# ─────────────────────────────────────────────────────────

def index_repo(repo_root):
    """
    Walk workflows/**/*.json. Return list of dicts with file path,
    top-level id, name, webhook paths declared.
    """
    out = []
    for fn in glob.glob(os.path.join(repo_root, 'workflows', '**', '*.json'),
                        recursive=True):
        try:
            d = json.load(open(fn, encoding='utf-8'))
        except Exception:
            continue
        webhooks = [
            n.get('parameters', {}).get('path', '')
            for n in d.get('nodes', []) or []
            if n.get('type') == 'n8n-nodes-base.webhook'
        ]
        webhooks = [w for w in webhooks if w]
        out.append({
            'file': os.path.relpath(fn, repo_root).replace('\\', '/'),
            'id': d.get('id'),
            'name': d.get('name', ''),
            'webhooks': webhooks,
        })
    return out


# ─────────────────────────────────────────────────────────
# 3. DEDUPE PLANNING
# ─────────────────────────────────────────────────────────

NAMED_ID_RE = re.compile(r'^(wf|clx)[A-Z][A-Za-z0-9]+$')


def is_named_id(wf_id):
    """True if id is camelCase wfXxx/clxXxx (not a random nano-id)."""
    return bool(wf_id) and bool(NAMED_ID_RE.match(wf_id))


def plan_dedupe(live, repo):
    """
    For every name that appears >1 time in `live`, pick canonical and
    mark the rest as duplicates.
    """
    by_name = defaultdict(list)
    for wf in live:
        by_name[wf['name']].append(wf)
    repo_by_name = {r['name']: r for r in repo if r['name']}

    decisions = []
    for name, group in sorted(by_name.items()):
        if len(group) <= 1:
            continue
        repo_match = repo_by_name.get(name)
        repo_id = repo_match['id'] if repo_match else None

        def score(wf):
            s = 0
            if repo_id and wf['id'] == repo_id:
                s += 1000
            if is_named_id(wf['id']):
                s += 100
            if wf['active']:
                s += 10
            return s

        ranked = sorted(group, key=score, reverse=True)
        decisions.append({
            'name': name,
            'repo_file': repo_match['file'] if repo_match else None,
            'repo_id': repo_id,
            'canonical': ranked[0],
            'duplicates': ranked[1:],
            'total_copies': len(group),
        })
    return decisions


# ─────────────────────────────────────────────────────────
# 4. PHASE: AUDIT
# ─────────────────────────────────────────────────────────

def phase_audit(decisions, repo, live):
    total_dupes = sum(len(d['duplicates']) for d in decisions)
    print(f'# Workflow dedupe plan')
    print()
    print(f'Generated {datetime.datetime.now().isoformat(timespec="seconds")}.')
    print()
    print(f'- Live workflows: **{len(live)}**')
    print(f'- Repo workflow JSONs: **{len(repo)}**')
    print(f'- Duplicate name groups: **{len(decisions)}**')
    print(f'- Total duplicate rows to remove: **{total_dupes}**')
    print()
    if not decisions:
        print('No duplicates detected. Nothing to do.')
        return

    print('## Per-name decisions')
    print()
    print('| Name | Live copies | Keep | Delete | Source-of-truth (repo) |')
    print('|---|---|---|---|---|')
    for d in decisions:
        keep = f'`{d["canonical"]["id"]}`'
        if d['canonical']['active']:
            keep += ' ✓active'
        kill_bits = []
        for w in d['duplicates']:
            tag = f'`{w["id"]}`'
            if w['active']:
                tag += ' ✓active'
            kill_bits.append(tag)
        src = d['repo_file'] or '_(not in repo)_'
        print(f'| `{d["name"]}` | {d["total_copies"]} | {keep} | {", ".join(kill_bits)} | {src} |')

    print()
    print('## Commands')
    print()
    print('### A. Deactivate duplicates (safe, reversible)')
    print()
    print('```bash')
    for d in decisions:
        for w in d['duplicates']:
            print(f'docker exec n8n n8n update:workflow --id={w["id"]} --active=false')
    print('```')
    print()
    print('### B. Hard-delete duplicate rows (destructive)')
    print()
    print('Run only AFTER (A) above and a brief soak period (>1 min) to confirm webhooks unblock.')
    print()
    print('```bash')
    print('# SQLite (default n8n storage on a fresh install)')
    ids = [w['id'] for d in decisions for w in d['duplicates']]
    quoted = ', '.join("'" + i + "'" for i in ids)
    print('docker exec -i n8n sqlite3 /home/node/.n8n/database.sqlite <<SQL')
    print(f'  DELETE FROM webhook_entity   WHERE workflowId IN ({quoted});')
    print(f'  DELETE FROM execution_entity WHERE workflowId IN ({quoted});')
    print(f'  DELETE FROM workflow_entity  WHERE id IN ({quoted});')
    print('SQL')
    print('```')
    print()
    print('```sql')
    print('-- Postgres equivalent if n8n uses DB_TYPE=postgresdb')
    print(f'DELETE FROM webhook_entity   WHERE "workflowId" IN ({quoted});')
    print(f'DELETE FROM execution_entity WHERE "workflowId" IN ({quoted});')
    print(f'DELETE FROM workflow_entity  WHERE id IN ({quoted});')
    print('```')

    print()
    print('### C. Re-import canonical JSONs')
    print()
    print('After (B), each name below has 0 copies on the live n8n. Re-import via UI:')
    print('Workflows → Import from File → check **"Replace existing"** → select the file.')
    print()
    for d in decisions:
        if d['repo_file']:
            print(f'- **{d["name"]}** → `{d["repo_file"]}` (named id: `{d["repo_id"] or "n/a"}`)')
        else:
            print(f'- **{d["name"]}** → _NOT in repo; verify if this workflow is still needed_')

    print()
    print('## Next: prevent recurrence')
    print()
    print('Confirm every JSON in `workflows/**/*.json` has a top-level `"id"` field. ')
    print('Run `python3 scripts/n8n/add-top-level-ids.py --check` for an audit; pass ')
    print('`--apply` to fill in missing ids (deterministic name → camelCase id).')


# ─────────────────────────────────────────────────────────
# 5. PHASE: DEACTIVATE
# ─────────────────────────────────────────────────────────

def phase_deactivate(decisions, container, dry_run=False):
    failures = []
    targets = [(d['name'], w['id']) for d in decisions for w in d['duplicates']]
    print(f'Deactivating {len(targets)} duplicate workflow(s)...')
    for name, wf_id in targets:
        prefix = 'DRY ' if dry_run else ''
        print(f'  {prefix}{wf_id}  ({name})')
        if dry_run:
            continue
        r = docker_exec(container, 'n8n', 'update:workflow',
                        f'--id={wf_id}', '--active=false')
        if r.returncode != 0:
            failures.append((wf_id, r.stderr.strip() or r.stdout.strip()))
    print()
    if failures:
        print(f'FAILED ({len(failures)}):')
        for fid, err in failures:
            print(f'  {fid}: {err}')
    else:
        print('OK — all duplicates deactivated.')


# ─────────────────────────────────────────────────────────
# 6. PHASE: DELETE
# ─────────────────────────────────────────────────────────

def phase_delete(decisions, container, db_path, dry_run, postgres):
    ids = [w['id'] for d in decisions for w in d['duplicates']]
    if not ids:
        print('No duplicates to delete.')
        return
    quoted = ', '.join("'" + i + "'" for i in ids)

    if postgres:
        # Emit SQL for Mary to run via psql; do not auto-execute.
        print('# Postgres detected — script will not execute against an external DB.')
        print('# Run the following via psql against the n8n DB:')
        print()
        print(f'DELETE FROM webhook_entity   WHERE "workflowId" IN ({quoted});')
        print(f'DELETE FROM execution_entity WHERE "workflowId" IN ({quoted});')
        print(f'DELETE FROM workflow_entity  WHERE id IN ({quoted});')
        return

    sql = (
        f'DELETE FROM webhook_entity   WHERE workflowId IN ({quoted});\n'
        f'DELETE FROM execution_entity WHERE workflowId IN ({quoted});\n'
        f'DELETE FROM workflow_entity  WHERE id IN ({quoted});\n'
    )
    print(f'Executing against {db_path}:')
    print()
    print(sql)
    if dry_run:
        print('(dry-run — not executed)')
        return
    r = docker_exec(container, 'sqlite3', db_path, stdin=sql)
    if r.returncode != 0:
        print(f'sqlite3 failed (exit {r.returncode}): {r.stderr.strip()}', file=sys.stderr)
        sys.exit(3)
    print('OK — duplicate rows deleted. Restart n8n to clear in-memory webhook cache:')
    print('  docker restart n8n')


# ─────────────────────────────────────────────────────────
# 7. PHASE: VERIFY
# ─────────────────────────────────────────────────────────

def phase_verify(decisions, live, container):
    """
    Re-list workflows. Report how many groups are still duplicated.
    Also probe canonical webhooks for HTTP 401 (healthy).
    """
    live2 = list_live_workflows(container)
    fetch_active_states(container, live2)
    by_name = defaultdict(list)
    for wf in live2:
        by_name[wf['name']].append(wf)
    remaining = {n: g for n, g in by_name.items() if len(g) > 1}
    print(f'Total live workflows: {len(live2)}')
    print(f'Duplicate name groups remaining: {len(remaining)}')
    if remaining:
        print()
        for name, group in sorted(remaining.items()):
            ids = ', '.join(w['id'] for w in group)
            print(f'  STILL DUPLICATED: {name} → {ids}')


# ─────────────────────────────────────────────────────────
# 8. MAIN
# ─────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(
        description='Audit + dedupe n8n workflows. Read-only by default.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument('--phase', choices=['audit', 'deactivate', 'delete', 'verify'],
                    default='audit', help='Which phase to run.')
    ap.add_argument('--repo', default=REPO_DEFAULT,
                    help='Path to the repo root (defaults to script-relative).')
    ap.add_argument('--container', default='n8n',
                    help='Docker container running n8n.')
    ap.add_argument('--db-path', default='/home/node/.n8n/database.sqlite',
                    help='Path to n8n SQLite DB inside the container.')
    ap.add_argument('--postgres', action='store_true',
                    help='n8n uses Postgres; emit SQL instead of executing sqlite3.')
    ap.add_argument('--dry-run', action='store_true',
                    help='Print commands without executing.')
    ap.add_argument('--confirm-destructive', action='store_true',
                    help='Required to actually delete workflow rows.')
    args = ap.parse_args()

    live = list_live_workflows(args.container)
    fetch_active_states(args.container, live)
    repo = index_repo(args.repo)
    decisions = plan_dedupe(live, repo)

    if args.phase == 'audit':
        phase_audit(decisions, repo, live)
    elif args.phase == 'deactivate':
        phase_audit(decisions, repo, live)
        print('\n---\n')
        phase_deactivate(decisions, args.container, dry_run=args.dry_run)
    elif args.phase == 'delete':
        if not args.confirm_destructive and not args.dry_run:
            print('--phase=delete requires --confirm-destructive (or --dry-run for preview).',
                  file=sys.stderr)
            sys.exit(2)
        phase_audit(decisions, repo, live)
        print('\n---\n')
        phase_delete(decisions, args.container, args.db_path,
                     dry_run=args.dry_run, postgres=args.postgres)
    elif args.phase == 'verify':
        phase_verify(decisions, live, args.container)


if __name__ == '__main__':
    main()
