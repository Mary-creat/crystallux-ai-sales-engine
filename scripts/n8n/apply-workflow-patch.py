#!/usr/bin/env python3
"""
scripts/n8n/apply-workflow-patch.py

Apply every workflow JSON in a folder to the live n8n. Replaces the
manual UI Import-from-File + "Replace existing" + activate + smoke-test
loop with one batch command.

Designed to run on the VPS host that runs the n8n container. Called by
scripts/n8n/apply-workflow-patch.sh, which handles `git pull` first.

For each *.json file in the target folder:

  1. Parse top-level id, name, webhook paths from the JSON.
  2. Find every live workflow with the same name (these are the old
     versions Mary's dedupe pass deactivated but left in place).
  3. Deactivate + SQL-delete those old rows.
  4. If the new id collides with an existing live row, delete that too
     so the import is clean.
  5. `docker cp` the JSON into the container.
  6. `n8n import:workflow --input=<path>` to load it.
  7. Remember whether the workflow was active pre-patch (any old copy
     active OR JSON says `active: true`).

After all imports:

  8. `docker restart n8n` — clears the in-memory webhook cache so the
     new rows actually register on the bus. Polls until `n8n
     list:workflow` responds again.
  9. `n8n update:workflow --id=X --active=true` for every workflow that
     was active before.
 10. Probe each webhook with a junk Bearer token. HEALTHY = HTTP 401
     with a JSON body (auth-gated + reachable). Anything else gets
     flagged in the summary.

Exit codes:
  0  all files imported + all webhooks HEALTHY (or unprobed)
  1  one or more files failed to import OR one or more webhooks
     returned a non-HEALTHY status

Flags:
  --dry-run         Print intended actions; do not touch the container.
  --no-restart      Skip the docker restart (faster if you're
                    iterating; but webhooks may still be cached from
                    the previous workflow versions).
  --no-probe        Skip the curl smoke test.
  --container=NAME  Docker container name (default: n8n).
  --db-path=PATH    Path to n8n SQLite DB inside the container.
                    Default /home/node/.n8n/database.sqlite.
  --base=URL        Webhook base URL for probing.
                    Default https://automation.crystallux.org/webhook.
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

DEFAULT_BASE = os.environ.get('CLX_WEBHOOK_BASE',
                              'https://automation.crystallux.org/webhook')
DEFAULT_CONTAINER = os.environ.get('CLX_N8N_CONTAINER', 'n8n')
DEFAULT_DB_PATH = os.environ.get('CLX_N8N_DB_PATH',
                                 '/home/node/.n8n/database.sqlite')


# ────────────────────────────────────────────────
# Terminal output — colored when isatty
# ────────────────────────────────────────────────
def _c(code):
    return code if sys.stdout.isatty() else ''
GREEN  = _c('\033[32m')
RED    = _c('\033[31m')
YELLOW = _c('\033[33m')
DIM    = _c('\033[2m')
RESET  = _c('\033[0m')


# ────────────────────────────────────────────────
# n8n container helpers
# ────────────────────────────────────────────────
def dx(container, *cmd, stdin=None):
    """`docker exec` returning CompletedProcess. -i added if stdin given."""
    full = ['docker', 'exec']
    if stdin is not None:
        full.append('-i')
    full.extend([container, *cmd])
    return subprocess.run(full, input=stdin, capture_output=True, text=True)


def dcp(container, host_path, container_path):
    """docker cp host -> container."""
    return subprocess.run(
        ['docker', 'cp', host_path, f'{container}:{container_path}'],
        capture_output=True, text=True,
    )


def list_live_workflows(container):
    """
    Single pass: returns {id: {'name': str, 'active': bool}} for every
    workflow on the live n8n. We call this once and look up by name in
    the file loop.
    """
    out = {}
    r = dx(container, 'n8n', 'list:workflow')
    if r.returncode != 0:
        raise RuntimeError(
            f'n8n list:workflow failed inside container {container!r}: '
            f'{r.stderr.strip() or r.stdout.strip()}'
        )
    for line in r.stdout.strip().splitlines():
        parts = line.split('|', 1)
        if len(parts) != 2:
            continue
        wf_id, name = parts[0].strip(), parts[1].strip()
        out[wf_id] = {'name': name, 'active': False}

    ra = dx(container, 'n8n', 'list:workflow', '--active=true')
    if ra.returncode == 0:
        for line in ra.stdout.strip().splitlines():
            parts = line.split('|', 1)
            if len(parts) == 2 and parts[0].strip() in out:
                out[parts[0].strip()]['active'] = True
    return out


def deactivate(container, wf_id, dry_run):
    print(f'    deactivate {wf_id}' + (DIM + ' (DRY)' + RESET if dry_run else ''))
    if dry_run:
        return True
    r = dx(container, 'n8n', 'update:workflow', f'--id={wf_id}', '--active=false')
    if r.returncode != 0:
        print(f'      {RED}ERR{RESET}: {r.stderr.strip() or r.stdout.strip()}')
        return False
    return True


# Cached delete-capability detection (set once per run)
_DELETE_METHOD = None  # one of: 'cli', 'api', 'sqlite', 'none'


def detect_delete_capability(container, api_url, api_key):
    """
    Probe in order of cleanliness:
      'cli'    n8n CLI delete:workflow (newer n8n versions)
      'api'    REST API DELETE /workflows/:id with X-N8N-API-KEY
      'sqlite' direct sqlite3 on the container DB
      'none'   none available; deletes will be skipped (deactivate only)

    Probes are read-only and fast; cached in _DELETE_METHOD.
    """
    global _DELETE_METHOD
    if _DELETE_METHOD is not None:
        return _DELETE_METHOD

    # 1. CLI — try `n8n delete:workflow --help`. If the command is unknown,
    # exit code is non-zero and stderr/stdout mentions "unknown" or "invalid".
    r = dx(container, 'n8n', 'delete:workflow', '--help')
    combined = (r.stdout + r.stderr).lower()
    if r.returncode == 0 and 'delete:workflow' in combined:
        _DELETE_METHOD = 'cli'
        return _DELETE_METHOD

    # 2. REST API — only if API key + URL configured
    if api_key:
        try:
            check = subprocess.run(
                ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}',
                 '--max-time', '5',
                 '-H', f'X-N8N-API-KEY: {api_key}',
                 f'{api_url.rstrip("/")}/workflows?limit=1'],
                capture_output=True, text=True, timeout=8,
            )
            code = check.stdout.strip()
            if code.startswith('2'):
                _DELETE_METHOD = 'api'
                return _DELETE_METHOD
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

    # 3. sqlite3 — check `which sqlite3` inside container
    r = dx(container, 'sh', '-c', 'command -v sqlite3 || which sqlite3 2>/dev/null')
    if r.returncode == 0 and r.stdout.strip():
        _DELETE_METHOD = 'sqlite'
        return _DELETE_METHOD

    _DELETE_METHOD = 'none'
    return _DELETE_METHOD


def delete_workflow_ids(container, wf_ids, db_path, api_url, api_key, dry_run):
    """
    Best-effort delete. Tries the detected method; on failure does NOT
    abort the caller — old rows just remain deactivated. Returns True if
    everything deleted, False if anything was skipped/failed (caller may
    log but should still proceed with import).
    """
    if not wf_ids:
        return True
    method = detect_delete_capability(container, api_url, api_key)
    label = f'{len(wf_ids)} row(s): {", ".join(wf_ids)}'

    if method == 'none':
        print(f'    {YELLOW}skip-delete{RESET} ({label}) — no delete mechanism '
              f'available (no n8n delete CLI, no N8N_API_KEY, no sqlite3 in container). '
              f'Old rows stay deactivated; import will still proceed.')
        return False

    print(f'    delete via {method} → {label}'
          + (DIM + ' (DRY)' + RESET if dry_run else ''))
    if dry_run:
        return True

    if method == 'cli':
        ok = True
        for wid in wf_ids:
            r = dx(container, 'n8n', 'delete:workflow', f'--id={wid}')
            if r.returncode != 0:
                print(f'      {YELLOW}WARN{RESET} ({wid}): {r.stderr.strip() or r.stdout.strip()}')
                ok = False
        return ok

    if method == 'api':
        ok = True
        for wid in wf_ids:
            try:
                r = subprocess.run(
                    ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}',
                     '--max-time', '15',
                     '-X', 'DELETE',
                     '-H', f'X-N8N-API-KEY: {api_key}',
                     f'{api_url.rstrip("/")}/workflows/{wid}'],
                    capture_output=True, text=True, timeout=18,
                )
                code = r.stdout.strip()
                if not (code.startswith('2') or code == '404'):
                    # 404 is fine (already gone); anything else is a problem
                    print(f'      {YELLOW}WARN{RESET} ({wid}): HTTP {code}')
                    ok = False
            except (subprocess.TimeoutExpired, FileNotFoundError) as e:
                print(f'      {YELLOW}WARN{RESET} ({wid}): {e}')
                ok = False
        return ok

    if method == 'sqlite':
        quoted = ', '.join("'" + w + "'" for w in wf_ids)
        sql = (
            f'DELETE FROM webhook_entity   WHERE workflowId IN ({quoted});\n'
            f'DELETE FROM execution_entity WHERE workflowId IN ({quoted});\n'
            f'DELETE FROM workflow_entity  WHERE id IN ({quoted});\n'
        )
        r = dx(container, 'sqlite3', db_path, stdin=sql)
        if r.returncode != 0:
            # Could be schema mismatch (workflowId vs "workflowId") — try Postgres-quoted form
            sql_pg = sql.replace('workflowId', '"workflowId"')
            r2 = dx(container, 'sqlite3', db_path, stdin=sql_pg)
            if r2.returncode != 0:
                print(f'      {YELLOW}WARN{RESET}: {r.stderr.strip()}')
                return False
        return True

    return False


def import_file(container, container_path, dry_run):
    print(f'    import {container_path}' + (DIM + ' (DRY)' + RESET if dry_run else ''))
    if dry_run:
        return True
    r = dx(container, 'n8n', 'import:workflow', f'--input={container_path}')
    if r.returncode != 0:
        print(f'      {RED}ERR{RESET}: {r.stderr.strip() or r.stdout.strip()}')
        return False
    return True


def activate(container, wf_id, dry_run):
    print(f'  activate {wf_id}' + (DIM + ' (DRY)' + RESET if dry_run else ''))
    if dry_run:
        return True
    r = dx(container, 'n8n', 'update:workflow', f'--id={wf_id}', '--active=true')
    if r.returncode != 0:
        print(f'    {RED}ERR{RESET}: {r.stderr.strip() or r.stdout.strip()}')
        return False
    return True


def restart_and_wait(container, timeout=90):
    """docker restart, then poll until n8n CLI responds again."""
    print(f'\nRestarting container {container!r}...')
    subprocess.run(['docker', 'restart', container], capture_output=True)
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = dx(container, 'n8n', 'list:workflow')
        if r.returncode == 0:
            print(f'  n8n responsive (took {int(time.time() - (deadline - timeout))}s)')
            return True
        time.sleep(2)
    print(f'  {YELLOW}WARN{RESET}: n8n did not come back up within {timeout}s')
    return False


# ────────────────────────────────────────────────
# JSON inspection
# ────────────────────────────────────────────────
def extract_webhook_paths(d):
    return [
        n.get('parameters', {}).get('path', '')
        for n in d.get('nodes', []) or []
        if n.get('type') == 'n8n-nodes-base.webhook'
        and n.get('parameters', {}).get('path')
    ]


# ────────────────────────────────────────────────
# Webhook probing
# ────────────────────────────────────────────────
def probe_webhook(base, path):
    """
    Probe with junk Bearer token. Classify:
      HEALTHY    401 with JSON body — auth-gated, workflow reachable.
      EMPTY-200  200 with 0-byte body — Validate Session halt regression.
      NOT-FOUND  404 — workflow not registered (import/activate failed).
      N8N-500    500 — n8n internal error.
      BAD-INPUT  400 — active, probe lacks fields (also healthy).
    """
    try:
        r = subprocess.run(
            ['curl', '-s', '-o', '/tmp/_apply_probe', '-w', '%{http_code}',
             '--max-time', '8',
             '-X', 'POST',
             '-H', 'Content-Type: application/json',
             '-H', 'Authorization: Bearer junk',
             f'{base}/{path}',
             '-d', '{}'],
            capture_output=True, text=True, timeout=12,
        )
        code = r.stdout.strip() or '000'
        try:
            size = os.path.getsize('/tmp/_apply_probe')
        except OSError:
            size = 0
    except subprocess.TimeoutExpired:
        return 'TIMEOUT', '000', 0
    except FileNotFoundError:
        return 'NO-CURL', '000', 0

    if code == '401' and size > 0:
        return 'HEALTHY', code, size
    if code == '400':
        return 'BAD-INPUT', code, size  # workflow active, probe just lacks fields
    if code == '200' and size == 0:
        return 'EMPTY-200', code, size
    if code == '404':
        return 'NOT-FOUND', code, size
    if code == '500':
        return 'N8N-500', code, size
    return f'HTTP-{code}', code, size


# ────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(
        description='Apply every workflow JSON in a folder to the live n8n.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument('folder', help='Folder containing workflow JSONs.')
    ap.add_argument('--container', default=DEFAULT_CONTAINER)
    ap.add_argument('--db-path', default=DEFAULT_DB_PATH)
    ap.add_argument('--base', default=DEFAULT_BASE,
                    help='Webhook base URL for probing.')
    ap.add_argument('--api-url',
                    default=os.environ.get('CLX_N8N_API_URL',
                                           'http://localhost:5678/api/v1'),
                    help='n8n REST API base URL (used when N8N_API_KEY is set).')
    ap.add_argument('--api-key',
                    default=os.environ.get('N8N_API_KEY', ''),
                    help='n8n API key (X-N8N-API-KEY header) for REST DELETE.')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--no-restart', action='store_true')
    ap.add_argument('--no-probe', action='store_true')
    args = ap.parse_args()

    folder = os.path.abspath(args.folder)
    if not os.path.isdir(folder):
        print(f'ERROR: {folder} is not a directory', file=sys.stderr)
        sys.exit(2)
    files = sorted(glob.glob(os.path.join(folder, '*.json')))
    if not files:
        print(f'No .json files in {folder}')
        return 0

    # Sanity check container is up before doing anything.
    if not args.dry_run:
        check = subprocess.run(
            ['docker', 'inspect', '-f', '{{.State.Running}}', args.container],
            capture_output=True, text=True,
        )
        if check.returncode != 0 or check.stdout.strip() != 'true':
            print(f'ERROR: container {args.container!r} is not running.',
                  file=sys.stderr)
            sys.exit(2)

    print(f'Apply target : {os.path.relpath(folder)}')
    print(f'Files        : {len(files)}')
    print(f'Container    : {args.container}')
    print(f'Webhook base : {args.base}')
    print(f'Mode         : {"DRY-RUN" if args.dry_run else "APPLY"}')
    if not args.dry_run:
        detected = detect_delete_capability(args.container, args.api_url, args.api_key)
        print(f'Delete via   : {detected}'
              + (f"  {DIM}(no delete mechanism — old rows stay deactivated){RESET}"
                 if detected == 'none' else ''))
    print()

    # Build a single name → live-rows index so we only call list:workflow once.
    live = list_live_workflows(args.container) if not args.dry_run else {}
    by_name = defaultdict(list)
    for wid, info in live.items():
        by_name[info['name']].append({'id': wid, 'active': info['active']})

    # ───── Phase 1: per-file delete+import ─────
    results = []
    for f in files:
        rel = os.path.relpath(f)
        try:
            d = json.load(open(f, encoding='utf-8'))
        except Exception as e:
            print(f'{RED}✗{RESET} {rel}: parse failed: {e}')
            results.append({'file': rel, 'status': 'parse-failed'})
            continue
        json_id = d.get('id')
        json_name = d.get('name', '')
        webhook_paths = extract_webhook_paths(d)
        json_active = d.get('active') is True

        print(f'{rel}')
        print(f'  id   : {json_id or "(none)"}')
        print(f'  name : {json_name}')
        if not json_id:
            print(f'  {RED}✗ skipping{RESET} — no top-level id; '
                  f'run scripts/n8n/add-top-level-ids.py --apply first')
            results.append({'file': rel, 'status': 'no-id'})
            continue
        if not json_name:
            print(f'  {RED}✗ skipping{RESET} — no name in JSON')
            results.append({'file': rel, 'status': 'no-name'})
            continue

        live_matches = by_name.get(json_name, [])
        any_active = any(m['active'] for m in live_matches)
        other_id_dupes = [m['id'] for m in live_matches if m['id'] != json_id]
        same_id_present = any(m['id'] == json_id for m in live_matches)

        print(f'  live : {len(live_matches)} workflow(s) match by name; '
              f'{sum(1 for m in live_matches if m["active"])} active')

        # Deactivate every same-name row. ALWAYS works via CLI (no sqlite3
        # needed) and is what actually matters for webhook collision: only
        # active workflows register webhooks, so a deactivated old row stops
        # competing with the new one even if we can't delete it.
        for m in live_matches:
            if m['active']:
                deactivate(args.container, m['id'], args.dry_run)

        # Best-effort delete of old rows (different-id duplicates + same-id).
        # If sqlite3 / API / CLI delete all unavailable, this returns False and
        # we proceed anyway — the deactivated rows are harmless garbage.
        delete_targets = list(other_id_dupes)
        if same_id_present:
            delete_targets.append(json_id)
        delete_workflow_ids(
            args.container, delete_targets, args.db_path,
            args.api_url, args.api_key, args.dry_run,
        )

        # Copy file into container + import. If delete was skipped AND a
        # same-id row exists, the import will likely fail with
        # SQLITE_CONSTRAINT — we report that clearly so Mary knows to do
        # one UI Import-Replace for the affected file.
        container_path = f'/tmp/clx-patch-{os.path.basename(f)}'
        if not args.dry_run:
            cp = dcp(args.container, f, container_path)
            if cp.returncode != 0:
                print(f'  {RED}✗ docker cp failed{RESET}: {cp.stderr.strip()}')
                results.append({'file': rel, 'status': 'cp-failed'})
                continue
        if not import_file(args.container, container_path, args.dry_run):
            if same_id_present and _DELETE_METHOD == 'none':
                print(f'  {YELLOW}→ likely id collision; do ONE UI Import-Replace '
                      f'for this file (id `{json_id}` already exists){RESET}')
            results.append({'file': rel, 'status': 'import-failed'})
            continue

        was_active = any_active or json_active
        print(f'  {GREEN}✓ imported{RESET}{" (will re-activate)" if was_active else " (left inactive)"}')
        results.append({
            'file': rel,
            'status': 'imported',
            'id': json_id,
            'was_active': was_active,
            'webhook_paths': webhook_paths,
        })
        print()

    # ───── Phase 2: restart n8n to flush webhook cache ─────
    if not args.no_restart and not args.dry_run:
        restart_and_wait(args.container)

    # ───── Phase 3: re-activate workflows that were active pre-patch ─────
    to_activate = [r for r in results if r['status'] == 'imported' and r['was_active']]
    if to_activate:
        print(f'\nActivating {len(to_activate)} workflow(s) that were active pre-patch:')
        for r in to_activate:
            activate(args.container, r['id'], args.dry_run)

    # ───── Phase 4: probe webhooks ─────
    if not args.no_probe and not args.dry_run:
        print(f'\nProbing webhooks (junk Bearer token; HEALTHY = 401 + body):')
        for r in results:
            if r['status'] != 'imported':
                continue
            for p in r.get('webhook_paths', []):
                status, code, size = probe_webhook(args.base, p)
                tag = (GREEN + status + RESET) if status in ('HEALTHY', 'BAD-INPUT') \
                       else (RED + status + RESET)
                print(f'  {tag:30}  HTTP {code:>3}  {size:>5}B  /{p}')
                r.setdefault('probe', []).append({
                    'path': p, 'status': status, 'code': code, 'size': size,
                })

    # ───── Summary ─────
    imported = [r for r in results if r['status'] == 'imported']
    failed = [r for r in results if r['status'] != 'imported']

    print()
    print('=' * 62)
    print(' SUMMARY')
    print('=' * 62)
    print(f'  Files processed : {len(results)}')
    print(f'  Imported        : {len(imported)}')
    print(f'  Failed          : {len(failed)}')
    if not args.no_probe and not args.dry_run:
        probes = [p for r in imported for p in r.get('probe', [])]
        healthy = [p for p in probes if p['status'] in ('HEALTHY', 'BAD-INPUT')]
        print(f'  Webhooks probed : {len(probes)}')
        print(f'    HEALTHY       : {len(healthy)}')
        print(f'    Other         : {len(probes) - len(healthy)}')

    overall_ok = (len(failed) == 0)
    if failed:
        print()
        print(f'  {RED}Failed files:{RESET}')
        for r in failed:
            print(f'    ✗ {r["file"]} → {r["status"]}')
    if not args.no_probe and not args.dry_run:
        problems = [(r, p) for r in imported for p in r.get('probe', [])
                    if p['status'] not in ('HEALTHY', 'BAD-INPUT')]
        if problems:
            overall_ok = False
            print()
            print(f'  {YELLOW}Unhealthy probes:{RESET}')
            for r, p in problems:
                print(f'    ⚠ {r["file"]} → /{p["path"]} → {p["status"]} (HTTP {p["code"]})')

    print()
    if overall_ok:
        print(f'  {GREEN}OK{RESET} — all files imported, all probed endpoints healthy.')
        return 0
    print(f'  {YELLOW}Issues detected — review above.{RESET}')
    return 1


if __name__ == '__main__':
    sys.exit(main())
