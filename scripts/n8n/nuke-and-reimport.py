#!/usr/bin/env python3
"""
scripts/n8n/nuke-and-reimport.py — DESTRUCTIVE

Resets n8n's workflow state to match the repo exactly. Use when the
live n8n has accumulated orphan rows / stale webhook_entity / failed
activations / inconsistent state that surgical fixes can't resolve.

Phases:
  1. Pre-flight  — container present, volume detected, file count
  2. CONFIRM     — refuses to run without --confirm-destructive
  3. Stop n8n
  4. Sidecar SQL — TRUNCATE workflow_entity + webhook_entity +
                   execution_entity via Alpine sidecar (no sqlite3
                   needed in n8n container)
  5. Start n8n, wait for CLI readiness
  6. Import      — copies the whole `workflows/` directory into the
                   container in one docker-cp, then loops calling
                   `n8n import:workflow --input=<path>` for every JSON
  7. Activate    — per folder policy. Default: activate every workflow
                   in workflows/api/{admin,avatars,public,client,
                   insurance-mga,carriers,sentinel,distribution,
                   briefing,booking,messaging,email,reports,
                   supervisor,training,completeness,content,video,
                   agent,ciro} and (with --activate-roots) the
                   root-level Sales Engine workflows.
  8. Final restart — flushes the in-memory webhook map so n8n
                     re-reads workflow_entity and registers every
                     active workflow's webhook deterministically.
  9. Probe       — hits a curated list of admin + public endpoints
                   with a junk Bearer token. Reports HEALTHY (401 +
                   body) / BAD-INPUT (400) / EMPTY-200 / NOT-FOUND /
                   N8N-500 counts + per-endpoint table.

What this DOES NOT touch:
  - n8n credentials (stored in a separate table, untouched)
  - n8n env vars
  - n8n users / sessions / API keys
  - Supabase / Postgres data
  - Anything outside n8n's `workflow_entity` / `webhook_entity` /
    `execution_entity` tables

What this LOSES:
  - Workflow execution history (the execution_entity table is wiped)
  - Any workflow manually created in the n8n UI that isn't in the repo
    (per CLAUDE.md, the repo is the source of truth so this should
    be empty in practice)

Usage:
  bash scripts/n8n/nuke-and-reimport.sh                 # interactive prompt
  python3 scripts/n8n/nuke-and-reimport.py \\
    --confirm-destructive                                 # non-interactive
  python3 scripts/n8n/nuke-and-reimport.py \\
    --confirm-destructive --activate-roots                # also activate Sales Engine cron workflows
  python3 scripts/n8n/nuke-and-reimport.py --dry-run    # plan only
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
DEFAULT_BASE = os.environ.get('CLX_WEBHOOK_BASE', 'https://automation.crystallux.org/webhook')
DEFAULT_CONTAINER = os.environ.get('CLX_N8N_CONTAINER', 'n8n')
N8N_DATA_PATH = '/home/node/.n8n'
N8N_DB_FILE = 'database.sqlite'

# Folders whose workflows are activated by default in step 7.
# Cover everything Mary uses from the admin + dashboards + public surfaces.
DEFAULT_ACTIVATE_FOLDERS = [
    'workflows/api/admin',
    'workflows/api/avatars',
    'workflows/api/public',
    'workflows/api/client',
    'workflows/api/insurance-mga',
    'workflows/api/carriers',
    'workflows/api/sentinel',
    'workflows/api/distribution',
    'workflows/api/briefing',
    'workflows/api/booking',
    'workflows/api/messaging',
    'workflows/api/email',
    'workflows/api/reports',
    'workflows/api/supervisor',
    'workflows/api/training',
    'workflows/api/completeness',
    'workflows/api/content',
    'workflows/api/video',
    'workflows/api/agent',
    'workflows/api/ciro',
    'workflows/api/auth',
    'workflows/api/goals',
    'workflows/api/rebook',
    'workflows/api/archetype-seeds',
]

# Root-level workflows (Sales Engine Phase 1-9 + utilities). Off by default
# — Mary activates the 9-station Sales Engine via --activate-roots when she's
# ready to flip lead discovery + outreach + booking on.
ROOT_WORKFLOW_GLOBS = ['workflows/clx-*.json']

# Endpoints we probe in step 9. Update as new public-facing endpoints land.
PROBE_ENDPOINTS = [
    'admin/list-leads', 'admin/list-clients', 'admin/client-detail',
    'admin/system-health', 'admin/workflow-status', 'admin/billing-summary',
    'admin/audit-log', 'admin/comms-log', 'admin/market-intelligence',
    'admin/onboarding-pipeline',
    'admin/smart-quote/list', 'admin/smart-quote/flow',
    'admin/avatar-content/list', 'admin/avatar-schedule',
    'admin/luxi/auctions', 'admin/luxi/auctions/manage', 'admin/luxi/place-bid',
    'admin/ciro/alerts',
    'maxi/industries', 'maxi/industry-detail',
    'avatars/list', 'avatars/route',
    'api/carriers/status-check', 'api/carriers/commission-calc',
    'api/carriers/reconciliation', 'api/carriers/submission', 'api/carriers/update',
    'api/sentinel/health/summary', 'api/sentinel/security/summary',
    'api/sentinel/cost/summary',
    'public/quote/fetch', 'public/mga/apply', 'public/quote/respond',
]


def _c(code):
    return code if sys.stdout.isatty() else ''
GREEN  = _c('\033[32m')
RED    = _c('\033[31m')
YELLOW = _c('\033[33m')
DIM    = _c('\033[2m')
BOLD   = _c('\033[1m')
RESET  = _c('\033[0m')


# ───────────────────────────────────────────────────────────────────
# Docker helpers
# ───────────────────────────────────────────────────────────────────
def dx(container, *cmd, stdin=None, timeout=60):
    """`docker exec` returning CompletedProcess."""
    full = ['docker', 'exec']
    if stdin is not None:
        full.append('-i')
    full.extend([container, *cmd])
    return subprocess.run(full, input=stdin, capture_output=True, text=True, timeout=timeout)


def find_n8n_volume(container):
    r = subprocess.run(
        ['docker', 'inspect', container, '--format', '{{ json .Mounts }}'],
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
            return {'type': m.get('Type', 'volume'),
                    'source': m.get('Name') or m.get('Source')}
    for m in mounts or []:
        if (m.get('Destination') or '').endswith('/.n8n'):
            return {'type': m.get('Type', 'volume'),
                    'source': m.get('Name') or m.get('Source')}
    return None


def wait_ready(container, timeout=180):
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = dx(container, 'n8n', 'list:workflow', timeout=12)
        if r.returncode == 0:
            return True
        time.sleep(2)
    return False


# ───────────────────────────────────────────────────────────────────
# Workflow inventory
# ───────────────────────────────────────────────────────────────────
def index_workflows(repo_root, activate_roots):
    """Return [(file_path, top_level_id, name, folder_rel, should_activate)]"""
    rows = []
    activate_dirs_abs = {os.path.normpath(os.path.join(repo_root, d))
                        for d in DEFAULT_ACTIVATE_FOLDERS}
    files = glob.glob(os.path.join(repo_root, 'workflows', '**', '*.json'), recursive=True)
    for f in sorted(files):
        try:
            d = json.load(open(f, encoding='utf-8'))
        except Exception:
            continue
        wf_id = d.get('id')
        name  = d.get('name', '')
        folder = os.path.dirname(os.path.normpath(f))
        is_under_activate = any(folder == d or folder.startswith(d + os.sep)
                                for d in activate_dirs_abs)
        # Root-level workflows (directly in workflows/, not in api/) only
        # activate when --activate-roots is passed.
        is_root_level = os.path.dirname(os.path.relpath(f, repo_root)) == 'workflows'
        if is_root_level:
            should_activate = activate_roots
        else:
            should_activate = is_under_activate
        rows.append({
            'file': f,
            'id': wf_id,
            'name': name,
            'rel': os.path.relpath(f, repo_root).replace('\\', '/'),
            'should_activate': should_activate,
        })
    return rows


# ───────────────────────────────────────────────────────────────────
# Phases
# ───────────────────────────────────────────────────────────────────
def phase_sidecar_truncate(volume, dry_run):
    """TRUNCATE workflow + webhook + execution tables via Alpine sidecar."""
    vol_arg = f'{volume["source"]}:/data'
    sql = (
        "DELETE FROM webhook_entity;\n"
        "DELETE FROM execution_entity;\n"
        "DELETE FROM workflow_entity;\n"
        "SELECT 'webhook_entity', COUNT(*) FROM webhook_entity\n"
        " UNION ALL SELECT 'execution_entity', COUNT(*) FROM execution_entity\n"
        " UNION ALL SELECT 'workflow_entity',  COUNT(*) FROM workflow_entity;\n"
    )
    full_sh = (
        'set -e; '
        'apk add --no-cache sqlite >/dev/null 2>&1; '
        f'sqlite3 /data/{N8N_DB_FILE}'
    )
    print(f'  {DIM}sidecar: alpine + sqlite3 against {volume["source"]}:/data{RESET}')
    if dry_run:
        print(f'  {DIM}(DRY-RUN — not executed){RESET}')
        print(f'  SQL:\n{sql}')
        return True
    r = subprocess.run(
        ['docker', 'run', '--rm', '-i', '-v', vol_arg, 'alpine:3.18',
         'sh', '-c', full_sh],
        input=sql, capture_output=True, text=True, timeout=180,
    )
    if r.returncode != 0:
        print(f'  {RED}TRUNCATE failed{RESET}: {r.stderr.strip() or r.stdout.strip()}')
        return False
    # Sidecar output has the row counts after truncate
    print(f'  {GREEN}truncate complete — row counts after:{RESET}')
    for line in r.stdout.strip().splitlines()[-3:]:
        print(f'    {line}')
    return True


def phase_copy_workflows(container, repo_root, dry_run):
    """Single docker cp of the workflows/ directory into /tmp/clx-workflows/ in the container."""
    src = os.path.join(repo_root, 'workflows') + os.sep + '.'
    dest = f'{container}:/tmp/clx-workflows'
    # Pre-clean to avoid mixing in older stale files
    if not dry_run:
        dx(container, 'rm', '-rf', '/tmp/clx-workflows')
    print(f'  docker cp {src} -> {dest}' + (f' {DIM}(DRY){RESET}' if dry_run else ''))
    if dry_run:
        return True
    r = subprocess.run(['docker', 'cp', src, dest], capture_output=True, text=True)
    if r.returncode != 0:
        print(f'  {RED}docker cp failed{RESET}: {r.stderr.strip()}')
        return False
    return True


def phase_import(container, workflows, dry_run):
    """Loop n8n import:workflow over every JSON inside the container."""
    failed = []
    imported = 0
    for wf in workflows:
        rel_inside = '/tmp/clx-workflows/' + wf['rel'].replace('workflows/', '', 1)
        # Trailing newline for progress output without flooding
        if dry_run:
            imported += 1
            continue
        r = dx(container, 'n8n', 'import:workflow', f'--input={rel_inside}', timeout=30)
        if r.returncode != 0:
            err = (r.stderr.strip() or r.stdout.strip())[:160]
            failed.append((wf['rel'], err))
        else:
            imported += 1
        # Progress every 25 files
        if (imported + len(failed)) % 25 == 0:
            sys.stdout.write(f'\r  imported {imported}, failed {len(failed)}…')
            sys.stdout.flush()
    print(f'\r  {GREEN}imported {imported}{RESET}, {RED if failed else DIM}failed {len(failed)}{RESET}')
    if failed:
        print(f'  {YELLOW}First 10 failures:{RESET}')
        for rel, err in failed[:10]:
            print(f'    ✗ {rel}: {err}')
    return failed


def phase_activate(container, workflows, dry_run):
    """Activate every workflow whose should_activate=True via CLI."""
    to_activate = [w for w in workflows if w['should_activate'] and w['id']]
    print(f'  activating {len(to_activate)} workflow(s) (of {len(workflows)} total)' +
          (f' {DIM}(DRY){RESET}' if dry_run else ''))
    failed = []
    activated = 0
    for w in to_activate:
        if dry_run:
            activated += 1
            continue
        r = dx(container, 'n8n', 'update:workflow', f'--id={w["id"]}', '--active=true', timeout=15)
        if r.returncode != 0:
            err = (r.stderr.strip() or r.stdout.strip())[:160]
            failed.append((w['rel'], w['id'], err))
        else:
            activated += 1
        if (activated + len(failed)) % 25 == 0:
            sys.stdout.write(f'\r  activated {activated}, failed {len(failed)}…')
            sys.stdout.flush()
    print(f'\r  {GREEN}activated {activated}{RESET}, {RED if failed else DIM}failed {len(failed)}{RESET}')
    if failed:
        print(f'  {YELLOW}First 10 activation failures:{RESET}')
        for rel, wid, err in failed[:10]:
            print(f'    ✗ {rel} ({wid}): {err}')
    return failed


def phase_probe(base):
    """Probe each PROBE_ENDPOINTS with junk Bearer; classify response."""
    print(f'  probing {len(PROBE_ENDPOINTS)} endpoint(s) at {base}')
    results = []
    for path in PROBE_ENDPOINTS:
        try:
            r = subprocess.run(
                ['curl', '-s', '-o', '/tmp/_nuke_probe', '-w', '%{http_code}',
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
                size = os.path.getsize('/tmp/_nuke_probe')
            except OSError:
                size = 0
        except subprocess.TimeoutExpired:
            code, size = 'TIMEOUT', 0
        if code == '401' and size > 0:
            cls = 'HEALTHY'
        elif code == '400':
            cls = 'BAD-INPUT'
        elif code == '200' and size == 0:
            cls = 'EMPTY-200'
        elif code == '404':
            cls = 'NOT-FOUND'
        elif code == '500':
            cls = 'N8N-500'
        elif code == '502':
            cls = 'HTTP-502'
        else:
            cls = f'HTTP-{code}'
        results.append({'path': path, 'code': code, 'size': size, 'class': cls})
    return results


# ───────────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(
        description='DESTRUCTIVE: reset n8n workflow state to match the repo.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument('--repo', default=REPO_DEFAULT)
    ap.add_argument('--container', default=DEFAULT_CONTAINER)
    ap.add_argument('--base', default=DEFAULT_BASE, help='Webhook base URL for probing.')
    ap.add_argument('--confirm-destructive', action='store_true',
                    help='Required to actually run (not just --dry-run).')
    ap.add_argument('--dry-run', action='store_true',
                    help='Print the plan + counts without touching anything.')
    ap.add_argument('--activate-roots', action='store_true',
                    help='Also activate root-level workflows (Sales Engine Phase 1-9).')
    ap.add_argument('--no-probe', action='store_true', help='Skip the final probe phase.')
    args = ap.parse_args()

    if not args.confirm_destructive and not args.dry_run:
        print(f'{RED}--confirm-destructive required (or use --dry-run to preview){RESET}',
              file=sys.stderr)
        sys.exit(2)

    print(f'{BOLD}NUKE + REIMPORT{RESET}')
    print(f'  Container         : {args.container}')
    print(f'  Repo              : {args.repo}')
    print(f'  Webhook base      : {args.base}')
    print(f'  Activate roots    : {args.activate_roots}')
    print(f'  Mode              : {"DRY-RUN" if args.dry_run else "APPLY (destructive)"}')
    print()

    # Pre-flight
    print(f'{BOLD}Phase 1/8: pre-flight{RESET}')
    if not args.dry_run:
        chk = subprocess.run(
            ['docker', 'inspect', '-f', '{{.State.Running}}', args.container],
            capture_output=True, text=True,
        )
        if chk.returncode != 0:
            print(f'  {RED}container {args.container!r} not found{RESET}'); sys.exit(2)
        print(f'  Container running : {chk.stdout.strip()}')
    volume = find_n8n_volume(args.container) if not args.dry_run else {
        'type': 'volume', 'source': '<volume>'
    }
    if not volume:
        print(f'  {RED}could not detect n8n data volume — aborting{RESET}'); sys.exit(2)
    print(f'  Volume            : {volume["source"]} ({volume["type"]})')
    workflows = index_workflows(args.repo, args.activate_roots)
    activatable = sum(1 for w in workflows if w['should_activate'])
    print(f'  Workflow JSONs    : {len(workflows)} ({activatable} will activate)')
    print()

    # Stop
    print(f'{BOLD}Phase 2/8: stop n8n{RESET}')
    if not args.dry_run:
        subprocess.run(['docker', 'stop', args.container], capture_output=True)
    print(f'  {GREEN}stopped{RESET}' + (f' {DIM}(DRY){RESET}' if args.dry_run else ''))
    print()

    # Sidecar TRUNCATE
    print(f'{BOLD}Phase 3/8: TRUNCATE workflow + webhook + execution tables{RESET}')
    if not phase_sidecar_truncate(volume, args.dry_run):
        print(f'{RED}truncate failed — restarting container{RESET}')
        if not args.dry_run:
            subprocess.run(['docker', 'start', args.container], capture_output=True)
        sys.exit(3)
    print()

    # Start
    print(f'{BOLD}Phase 4/8: start n8n + wait{RESET}')
    if not args.dry_run:
        subprocess.run(['docker', 'start', args.container], capture_output=True)
        if not wait_ready(args.container):
            print(f'{RED}n8n did not come back up within 180s{RESET}'); sys.exit(3)
    print(f'  {GREEN}n8n responsive{RESET}' + (f' {DIM}(DRY){RESET}' if args.dry_run else ''))
    print()

    # Copy
    print(f'{BOLD}Phase 5/8: copy workflows/ into container{RESET}')
    if not phase_copy_workflows(args.container, args.repo, args.dry_run):
        sys.exit(3)
    print()

    # Import
    print(f'{BOLD}Phase 6/8: import {len(workflows)} workflow(s){RESET}')
    import_failures = phase_import(args.container, workflows, args.dry_run)
    print()

    # Activate
    print(f'{BOLD}Phase 7/8: activate workflows per folder policy{RESET}')
    activate_failures = phase_activate(args.container, workflows, args.dry_run)
    print()

    # Final restart
    print(f'{BOLD}Phase 8/8: final restart + probe{RESET}')
    if not args.dry_run:
        subprocess.run(['docker', 'restart', args.container], capture_output=True)
        if not wait_ready(args.container):
            print(f'  {YELLOW}WARN: slow restart; probe may show false NOT-FOUND{RESET}')
        else:
            print(f'  {GREEN}n8n responsive after final restart{RESET}')

    if args.no_probe or args.dry_run:
        print(f'  {DIM}probe skipped{RESET}')
        results = []
    else:
        results = phase_probe(args.base)

    # Summary
    print()
    print('=' * 64)
    print(f'{BOLD} SUMMARY{RESET}')
    print('=' * 64)
    print(f'  Workflows in repo  : {len(workflows)}')
    print(f'  Imported           : {len(workflows) - len(import_failures)}')
    print(f'  Import failures    : {len(import_failures)}')
    print(f'  Activated          : {activatable - len(activate_failures)}')
    print(f'  Activation failures: {len(activate_failures)}')

    if results:
        from collections import Counter
        c = Counter(r['class'] for r in results)
        print()
        print(f'  {BOLD}Endpoint probe ({len(results)} URLs):{RESET}')
        for cls, n in c.most_common():
            color = GREEN if cls in ('HEALTHY', 'BAD-INPUT') else RED
            print(f'    {color}{cls:14}{RESET} {n}')
        unhealthy = [r for r in results if r['class'] not in ('HEALTHY', 'BAD-INPUT')]
        if unhealthy:
            print(f'\n  {YELLOW}Unhealthy endpoints (first 25):{RESET}')
            for r in unhealthy[:25]:
                print(f'    {r["class"]:14}  HTTP {r["code"]:>3}  /{r["path"]}')

    print()
    if results and all(r['class'] in ('HEALTHY', 'BAD-INPUT') for r in results):
        print(f'  {GREEN}{BOLD}ALL CLEAR{RESET} — every probed endpoint is healthy.')
        return 0
    if import_failures or activate_failures or (results and any(r['class'] not in ('HEALTHY', 'BAD-INPUT') for r in results)):
        print(f'  {YELLOW}Issues remain — review counts above. Most NOT-FOUND results after a clean reimport indicate workflows without webhook nodes (correct behavior).{RESET}')
        return 1
    print(f'  {GREEN}OK{RESET}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
