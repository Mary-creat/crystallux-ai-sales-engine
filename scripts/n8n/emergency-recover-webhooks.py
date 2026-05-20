#!/usr/bin/env python3
"""
scripts/n8n/emergency-recover-webhooks.py

Emergency recovery for the webhook_entity blockage Mary hit on
2026-05-19. After apply-workflow-patch.sh ran with `Delete via: none`,
old workflow rows accumulated in webhook_entity with the unique
constraint on (path, method) blocking new workflow activations.
Symptom: 18/22 endpoints return HTTP 404 even though the new
workflows were imported.

This script bypasses the API-key / sqlite3-in-container / n8n-CLI-delete
requirements entirely by using an **Alpine sidecar container** with
the n8n data volume mounted directly. SQL delete then works without
modifying the running n8n container, generating an API key, or any
manual setup beyond `docker`.

Single command for Mary to run:

    bash scripts/n8n/emergency-recover-webhooks.sh

Or for selective recovery:

    python3 scripts/n8n/emergency-recover-webhooks.py \\
        workflows/api/admin/ \\
        workflows/api/carriers/ \\
        workflows/api/sentinel/ \\
        ...

What it does, in order:

  1. INDEX repo: parse every JSON in the requested folders (or all
     of workflows/**/*.json if none specified) and build a map of
     workflow name -> canonical id.
  2. LIST live: query the live n8n via `docker exec n8n n8n list:workflow`.
  3. PLAN: per name in repo, compute IDs to delete (any live row
     with that name whose id is NOT the canonical one) and which
     canonical JSONs need to be imported fresh.
  4. DETECT VOLUME: find the Docker volume mounted at /home/node/.n8n
     inside the n8n container.
  5. STOP n8n briefly.
  6. SIDECAR DELETE: run alpine + sqlite3 with the volume mounted,
     execute DELETE on webhook_entity / execution_entity /
     workflow_entity for the targeted IDs.
  7. START n8n, wait for ready.
  8. IMPORT missing canonical JSONs (those whose names had zero live
     rows after delete).
  9. ACTIVATE every canonical workflow targeted (by folder argument)
     so the webhook actually registers.
 10. PROBE: smoke-test each webhook with a junk Bearer token; report
     HEALTHY / NOT-FOUND / EMPTY-200 / N8N-500.

Estimated downtime: 10-20 seconds while n8n container restarts.

Flags:
  --dry-run    Print the plan without executing anything.
  --no-probe   Skip the post-recovery curl smoke test.
  --container  n8n container name (default: n8n).
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import time
from collections import defaultdict

try:
    sys.stdout.reconfigure(encoding='utf-8')
except (AttributeError, OSError):
    pass

REPO_DEFAULT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_BASE = 'https://automation.crystallux.org/webhook'

# Where the n8n data lives inside its container.
N8N_DATA_PATH = '/home/node/.n8n'
N8N_DB_FILE_IN_VOLUME = 'database.sqlite'  # relative to mount root


def _c(code):
    return code if sys.stdout.isatty() else ''
GREEN  = _c('\033[32m')
RED    = _c('\033[31m')
YELLOW = _c('\033[33m')
DIM    = _c('\033[2m')
BOLD   = _c('\033[1m')
RESET  = _c('\033[0m')


# ────────────────────────────────────────────────────────
# Docker helpers
# ────────────────────────────────────────────────────────
def dx(container, *cmd, stdin=None):
    full = ['docker', 'exec']
    if stdin is not None:
        full.append('-i')
    full.extend([container, *cmd])
    return subprocess.run(full, input=stdin, capture_output=True, text=True)


def find_n8n_volume(container):
    """
    Inspect the n8n container, return the docker volume / bind source
    that holds the SQLite database. Returns dict with:
      type   - 'volume' or 'bind'
      source - volume name or host path
      dest   - container mount destination (always /home/node/.n8n)
    """
    r = subprocess.run(
        ['docker', 'inspect', container,
         '--format', '{{ json .Mounts }}'],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return None
    try:
        mounts = json.loads(r.stdout)
    except Exception:
        return None
    for m in mounts or []:
        if m.get('Destination') == N8N_DATA_PATH:
            return {
                'type':   m.get('Type', 'volume'),
                'source': m.get('Name') or m.get('Source'),
                'dest':   m.get('Destination'),
            }
    # Fallback: any mount destination containing '.n8n'
    for m in mounts or []:
        if m.get('Destination', '').endswith('/.n8n'):
            return {
                'type':   m.get('Type', 'volume'),
                'source': m.get('Name') or m.get('Source'),
                'dest':   m.get('Destination'),
            }
    return None


# ────────────────────────────────────────────────────────
# Repo + live indexing
# ────────────────────────────────────────────────────────
def index_repo(repo_root, folder_args):
    """
    Walk the given folders (or all of workflows/**/*.json if none).
    Return list of dicts: {file, id, name, webhook_paths, requested}.
    `requested=True` means this file came from an explicit folder arg
    and should be activated post-recovery.
    """
    if folder_args:
        files = []
        for folder in folder_args:
            absf = os.path.abspath(folder)
            files.extend(sorted(glob.glob(os.path.join(absf, '**', '*.json'),
                                          recursive=True)))
        requested_set = set(files)
    else:
        files = sorted(glob.glob(os.path.join(repo_root, 'workflows', '**', '*.json'),
                                  recursive=True))
        requested_set = set()  # nothing explicitly requested → nothing auto-activated

    out = []
    for fn in files:
        try:
            d = json.load(open(fn, encoding='utf-8'))
        except Exception as e:
            print(f'  {YELLOW}WARN{RESET}: skip {fn}: {e}')
            continue
        webhooks = [
            n.get('parameters', {}).get('path', '')
            for n in d.get('nodes', []) or []
            if n.get('type') == 'n8n-nodes-base.webhook'
            and n.get('parameters', {}).get('path')
        ]
        out.append({
            'file':           fn,
            'id':             d.get('id'),
            'name':           d.get('name', ''),
            'webhook_paths':  webhooks,
            'requested':      fn in requested_set,
        })
    return out


def list_live(container):
    """Return {id: name} for every live workflow."""
    r = dx(container, 'n8n', 'list:workflow')
    if r.returncode != 0:
        raise RuntimeError(f'n8n list:workflow failed: {r.stderr or r.stdout}')
    out = {}
    for line in r.stdout.strip().splitlines():
        parts = line.split('|', 1)
        if len(parts) == 2:
            out[parts[0].strip()] = parts[1].strip()
    return out


# ────────────────────────────────────────────────────────
# Planning
# ────────────────────────────────────────────────────────
def plan(repo, live):
    """
    Per name in repo, decide:
      - keep   : the canonical live id (if it exists)
      - delete : any other live ids with the same name
      - import : if zero live rows with that name (re-import canonical)
    """
    by_name = defaultdict(list)
    for live_id, name in live.items():
        by_name[name].append(live_id)

    plan = {'delete_ids': set(), 'import_files': [], 'activate_ids': []}
    for wf in repo:
        if not wf['id'] or not wf['name']:
            continue
        live_ids = by_name.get(wf['name'], [])
        if not live_ids:
            # Nothing live; import + (if requested) activate.
            plan['import_files'].append(wf)
            if wf['requested']:
                plan['activate_ids'].append(wf['id'])
            continue
        if wf['id'] in live_ids:
            # Canonical row exists; delete the rest, keep canonical.
            for lid in live_ids:
                if lid != wf['id']:
                    plan['delete_ids'].add(lid)
            if wf['requested']:
                plan['activate_ids'].append(wf['id'])
        else:
            # Old duplicates exist but no canonical id. Delete them all,
            # import the canonical, activate if requested.
            for lid in live_ids:
                plan['delete_ids'].add(lid)
            plan['import_files'].append(wf)
            if wf['requested']:
                plan['activate_ids'].append(wf['id'])
    return plan


# ────────────────────────────────────────────────────────
# Sidecar SQL delete
# ────────────────────────────────────────────────────────
def sidecar_sql_phase(volume, ids_to_delete):
    """
    Run an Alpine sidecar with the n8n data volume mounted, install
    sqlite3, and execute the cleanup SQL:

    (a) DELETE the planned duplicate workflow_entity rows + their
        webhook_entity / execution_entity rows.
    (b) ALWAYS clean orphan webhook_entity rows whose workflowId
        no longer exists in workflow_entity. These orphans accumulate
        from prior failed activations / partial deletes and silently
        block fresh activations from registering their webhook paths
        (unique constraint conflict). This is the fix for "33/69
        endpoints HEALTHY post-recovery" — the 36 unhealthy ones
        were blocked on orphan rows.

    Caller must ensure n8n container is STOPPED before calling, so
    we don't race with the running process on the same SQLite file.
    """
    statements = []

    if ids_to_delete:
        # Quote ids defensively (they're already short alnum but we don't
        # want any embedded single-quote to break out of the SQL string).
        safe = []
        for i in ids_to_delete:
            if "'" in i:
                print(f'  {RED}skip suspicious id with quote{RESET}: {i!r}')
                continue
            safe.append("'" + i + "'")
        quoted = ', '.join(safe)
        statements.extend([
            f'DELETE FROM webhook_entity   WHERE workflowId IN ({quoted});',
            f'DELETE FROM execution_entity WHERE workflowId IN ({quoted});',
            f'DELETE FROM workflow_entity  WHERE id IN ({quoted});',
        ])

    # Always: orphan cleanup. Removes webhook_entity rows pointing at
    # workflow IDs that no longer exist in workflow_entity.
    statements.append(
        'DELETE FROM webhook_entity '
        'WHERE workflowId NOT IN (SELECT id FROM workflow_entity);'
    )

    # Diagnostic counts so the operator can see what got cleaned.
    statements.append('SELECT changes();')  # rows affected by last DELETE
    statements.append('SELECT COUNT(*) FROM webhook_entity;')
    statements.append('SELECT COUNT(*) FROM workflow_entity;')

    sql = '\n'.join(statements) + '\n'

    vol_arg = f'{volume["source"]}:/data'  # same syntax for volume + bind

    full_sh = (
        'set -e; '
        'apk add --no-cache sqlite >/dev/null 2>&1; '
        f'sqlite3 /data/{N8N_DB_FILE_IN_VOLUME}'
    )

    r = subprocess.run(
        ['docker', 'run', '--rm', '-i', '-v', vol_arg, 'alpine:3.18',
         'sh', '-c', full_sh],
        input=sql, capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        print(f'  {RED}sidecar SQL failed{RESET}: {r.stderr.strip() or r.stdout.strip()}')
        return False

    # The trailing 3 SELECTs print as 3 lines (last-DELETE changes,
    # webhook_entity total, workflow_entity total). Show them so Mary
    # can see what shape the DB ended up in.
    lines = [l for l in r.stdout.strip().splitlines() if l.strip()]
    if len(lines) >= 3:
        orphans_cleaned, wh_total, wf_total = lines[-3], lines[-2], lines[-1]
        print(f'  orphan webhook_entity rows cleaned: {orphans_cleaned}')
        print(f'  webhook_entity rows remaining     : {wh_total}')
        print(f'  workflow_entity rows remaining    : {wf_total}')
    return True


# ────────────────────────────────────────────────────────
# n8n container lifecycle
# ────────────────────────────────────────────────────────
def stop_container(container):
    print(f'  stop {container}...')
    r = subprocess.run(['docker', 'stop', container], capture_output=True, text=True)
    return r.returncode == 0


def start_container(container):
    print(f'  start {container}...')
    r = subprocess.run(['docker', 'start', container], capture_output=True, text=True)
    return r.returncode == 0


def wait_ready(container, timeout=120):
    print(f'  waiting for n8n CLI to respond (up to {timeout}s)...')
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = dx(container, 'n8n', 'list:workflow')
        if r.returncode == 0:
            return True
        time.sleep(3)
    return False


# ────────────────────────────────────────────────────────
# Import + Activate
# ────────────────────────────────────────────────────────
def import_workflow(container, host_path, dry_run):
    container_path = f'/tmp/clx-emergency-{os.path.basename(host_path)}'
    if dry_run:
        return True
    cp = subprocess.run(
        ['docker', 'cp', host_path, f'{container}:{container_path}'],
        capture_output=True, text=True,
    )
    if cp.returncode != 0:
        return False
    r = dx(container, 'n8n', 'import:workflow', f'--input={container_path}')
    return r.returncode == 0


def activate(container, wf_id, dry_run):
    if dry_run:
        return True
    r = dx(container, 'n8n', 'update:workflow', f'--id={wf_id}', '--active=true')
    return r.returncode == 0


# ────────────────────────────────────────────────────────
# Probe
# ────────────────────────────────────────────────────────
def probe(base, path):
    try:
        r = subprocess.run(
            ['curl', '-s', '-o', '/tmp/_emerg_probe', '-w', '%{http_code}',
             '--max-time', '8', '-X', 'POST',
             '-H', 'Content-Type: application/json',
             '-H', 'Authorization: Bearer junk',
             f'{base}/{path}', '-d', '{}'],
            capture_output=True, text=True, timeout=12,
        )
        code = r.stdout.strip() or '000'
        try:
            size = os.path.getsize('/tmp/_emerg_probe')
        except OSError:
            size = 0
    except subprocess.TimeoutExpired:
        return 'TIMEOUT', '000', 0
    if code == '401' and size > 0:
        return 'HEALTHY', code, size
    if code == '400':
        return 'BAD-INPUT', code, size
    if code == '200' and size == 0:
        return 'EMPTY-200', code, size
    if code == '404':
        return 'NOT-FOUND', code, size
    if code == '500':
        return 'N8N-500', code, size
    return f'HTTP-{code}', code, size


# ────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(
        description='Emergency: recover broken webhook routing via Alpine sidecar.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument('folders', nargs='*',
                    help='Workflow folders whose JSONs should be activated post-recovery. '
                         'Cleanup happens for ALL repo workflows regardless.')
    ap.add_argument('--repo', default=REPO_DEFAULT)
    ap.add_argument('--container', default='n8n')
    ap.add_argument('--base', default=DEFAULT_BASE)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--no-probe', action='store_true')
    ap.add_argument('--no-import', action='store_true',
                    help='Skip the import phase (use if all canonical workflows '
                         'are already on the live n8n and only the cleanup is needed).')
    args = ap.parse_args()

    print(f'{BOLD}Emergency webhook recovery{RESET}')
    print(f'  Container       : {args.container}')
    print(f'  Repo            : {args.repo}')
    print(f'  Activate folders: {", ".join(args.folders) if args.folders else "(none — cleanup only)"}')
    print(f'  Mode            : {"DRY-RUN" if args.dry_run else "APPLY"}')
    print()

    # 1. Sanity: docker present + container exists
    if not args.dry_run:
        ck = subprocess.run(['docker', 'inspect', '-f', '{{.State.Running}}', args.container],
                            capture_output=True, text=True)
        if ck.returncode != 0:
            print(f'{RED}ERROR{RESET}: container {args.container!r} not found.')
            sys.exit(2)
        running = ck.stdout.strip() == 'true'
        print(f'  Container state : {"running" if running else "stopped"}')

    # 2. Find volume
    volume = find_n8n_volume(args.container) if not args.dry_run else \
             {'type': 'volume', 'source': '<volume-name>', 'dest': N8N_DATA_PATH}
    if not volume:
        print(f'{RED}ERROR{RESET}: could not locate n8n data volume. Mounts:')
        subprocess.run(['docker', 'inspect', args.container, '--format',
                        '{{ range .Mounts }}{{ println .Source .Destination .Type }}{{ end }}'])
        sys.exit(2)
    print(f'  n8n data volume : {volume["source"]} ({volume["type"]} -> {volume["dest"]})')
    print()

    # 3. Index repo + list live
    print('Indexing repo + live state...')
    repo = index_repo(args.repo, args.folders)
    print(f'  Repo workflows  : {len(repo)}')
    requested = [w for w in repo if w['requested']]
    print(f'  Requested       : {len(requested)} (will activate post-recovery)')

    if not args.dry_run:
        try:
            live = list_live(args.container)
        except RuntimeError as e:
            print(f'{RED}ERROR{RESET}: {e}')
            sys.exit(2)
    else:
        live = {}
    print(f'  Live workflows  : {len(live)}')

    # 4. Plan
    p = plan(repo, live)
    print()
    print(f'Plan:')
    print(f'  Delete (live ids that duplicate a repo name): {len(p["delete_ids"])}')
    print(f'  Import (canonical not yet on live)          : {len(p["import_files"])}')
    print(f'  Activate (requested via folder args)        : {len(p["activate_ids"])}')
    print()

    if not p['delete_ids'] and not p['import_files'] and not p['activate_ids']:
        print(f'  {GREEN}Nothing to do.{RESET}')
        return 0

    if args.dry_run:
        if p['delete_ids']:
            print('  Would delete:')
            for i in sorted(p['delete_ids'])[:30]:
                print(f'    {i}  ({live.get(i, "?")})')
            if len(p['delete_ids']) > 30:
                print(f'    ... and {len(p["delete_ids"]) - 30} more')
        if p['import_files']:
            print('  Would import:')
            for w in p['import_files'][:30]:
                print(f'    {os.path.relpath(w["file"], args.repo)}  ({w["id"]})')
        if p['activate_ids']:
            print('  Would activate:')
            for i in p['activate_ids'][:30]:
                print(f'    {i}')
        return 0

    # 5. STOP n8n
    print(f'{BOLD}Phase 1/5: stop n8n{RESET}')
    if not stop_container(args.container):
        print(f'{RED}ERROR{RESET}: failed to stop n8n.')
        sys.exit(3)
    print(f'  {GREEN}stopped{RESET}')
    print()

    # 6. SIDECAR SQL: delete planned duplicates + clean orphan webhook_entity
    print(f'{BOLD}Phase 2/6: sidecar SQL (delete duplicates + clean orphans){RESET}')
    delete_ok = sidecar_sql_phase(volume, p['delete_ids'])
    if delete_ok:
        if p['delete_ids']:
            print(f'  {GREEN}deleted {len(p["delete_ids"])} duplicate workflow row(s) + cleaned orphans{RESET}')
        else:
            print(f'  {GREEN}no planned deletes; cleaned orphans only{RESET}')
    else:
        print(f'  {RED}sidecar SQL failed — starting n8n back up anyway{RESET}')
    print()

    # 7. START n8n
    print(f'{BOLD}Phase 3/6: start n8n + wait for ready{RESET}')
    if not start_container(args.container):
        print(f'{RED}CRITICAL{RESET}: failed to restart n8n. Check `docker logs n8n`.')
        sys.exit(3)
    if not wait_ready(args.container):
        print(f'{RED}CRITICAL{RESET}: n8n did not come back up within timeout. '
              f'Check `docker logs n8n --tail 200`.')
        sys.exit(3)
    print(f'  {GREEN}n8n responsive{RESET}')
    print()

    # 8. IMPORT missing canonical
    print(f'{BOLD}Phase 4/6: import + activate{RESET}')
    if not args.no_import:
        for w in p['import_files']:
            ok = import_workflow(args.container, w['file'], args.dry_run)
            tag = GREEN + '✓' + RESET if ok else RED + '✗' + RESET
            print(f'  {tag} import {os.path.relpath(w["file"], args.repo)}')
    # Activate every requested workflow (now that webhook_entity is clean).
    for wf_id in p['activate_ids']:
        ok = activate(args.container, wf_id, args.dry_run)
        tag = GREEN + '✓' + RESET if ok else RED + '✗' + RESET
        print(f'  {tag} activate {wf_id}')
    print()

    # 9. FINAL RESTART — flushes the in-memory webhook map so n8n
    # re-reads workflow_entity (with active=true now set) on boot and
    # registers every webhook cleanly. CLI activate is unreliable at
    # triggering in-process webhook registration on some n8n versions;
    # the restart is the belt-and-suspenders fix.
    if not args.dry_run:
        print(f'{BOLD}Phase 5/6: final restart to flush webhook registrations{RESET}')
        subprocess.run(['docker', 'restart', args.container], capture_output=True)
        if not wait_ready(args.container, timeout=120):
            print(f'{YELLOW}WARN{RESET}: n8n slow to come back; probe may show false NOT-FOUND')
        else:
            print(f'  {GREEN}n8n responsive after final restart{RESET}')
        print()

    # 10. PROBE
    if not args.no_probe:
        print(f'{BOLD}Phase 6/6: probe webhooks{RESET}')
        # Build set of webhook paths to probe (from requested workflows).
        paths = []
        repo_by_id = {w['id']: w for w in repo}
        for wf_id in p['activate_ids']:
            w = repo_by_id.get(wf_id)
            if not w:
                continue
            for path in w['webhook_paths']:
                paths.append((path, wf_id))
        results = defaultdict(list)
        for path, wf_id in paths:
            status, code, size = probe(args.base, path)
            tag = GREEN + status + RESET if status in ('HEALTHY', 'BAD-INPUT') \
                  else RED + status + RESET
            print(f'  {tag:30}  HTTP {code:>3}  {size:>5}B  /{path}')
            results[status].append(path)

        print()
        print(f'{BOLD}Probe summary:{RESET}')
        for status, plist in sorted(results.items()):
            print(f'  {status:>12} : {len(plist)}')

        unhealthy = sum(len(v) for k, v in results.items()
                        if k not in ('HEALTHY', 'BAD-INPUT'))
        if unhealthy:
            print(f'\n  {YELLOW}{unhealthy} endpoint(s) still unhealthy.{RESET} If they\'re')
            print(f'  NOT-FOUND, the workflow may still be inactive — try:')
            print(f'    docker exec n8n n8n list:workflow --active=true | grep <id>')
            return 1

    print(f'\n  {GREEN}{BOLD}RECOVERY COMPLETE{RESET}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
