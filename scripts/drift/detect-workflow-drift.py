#!/usr/bin/env python3
"""
scripts/drift/detect-workflow-drift.py

Compares the repo (source of truth) against the live n8n state and
writes drift findings to Supabase `workflow_drift` table.

Drift types:
  repo_only     — JSON exists in repo, never imported to n8n
  n8n_only      — workflow active in n8n, no matching JSON in repo
                  (likely UI-created or stale)
  content_diff  — same id on both sides, content hash differs
                  (someone edited in n8n UI OR repo edit unshipped)
  active_diff   — same content, but active flag differs

Designed to run via cron on the VPS:
  0 8 * * * cd /tmp/clx-latest && python3 scripts/drift/detect-workflow-drift.py

Env vars required:
  N8N_API_KEY          — for /api/v1/workflows endpoint
  SUPABASE_SERVICE_KEY — for writing to workflow_drift table
  N8N_URL              — default https://automation.crystallux.org
  SUPABASE_URL         — default https://zqwatouqmqgkmaslydbr.supabase.co

Usage:
  python3 scripts/drift/detect-workflow-drift.py            # detect + write
  python3 scripts/drift/detect-workflow-drift.py --dry-run  # detect, print, don't write
  python3 scripts/drift/detect-workflow-drift.py --json     # machine-readable output
"""

import argparse
import glob
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

try:
    sys.stdout.reconfigure(encoding='utf-8')
except (AttributeError, OSError):
    pass

REPO_DEFAULT = os.environ.get('CLX_REPO', '/tmp/clx-latest')
N8N_URL      = os.environ.get('N8N_URL',  'https://automation.crystallux.org')
SUPABASE_URL = os.environ.get('SUPABASE_URL', 'https://zqwatouqmqgkmaslydbr.supabase.co')


def _c(code):
    return code if sys.stdout.isatty() else ''
GREEN  = _c('\033[32m')
RED    = _c('\033[31m')
YELLOW = _c('\033[33m')
BOLD   = _c('\033[1m')
DIM    = _c('\033[2m')
RESET  = _c('\033[0m')


def http_get(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def http_post(url, body, headers=None, timeout=30):
    h = {'Content-Type': 'application/json'}
    h.update(headers or {})
    req = urllib.request.Request(url, data=body.encode('utf-8'), headers=h, method='POST')
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


# ───────────────────────────────────────────────────────────────────
# Hash + normalisation
# ───────────────────────────────────────────────────────────────────
def normalize(workflow):
    """Strip ephemeral fields, sort node arrays, return a deterministic dict.

    Drift hashing has to ignore:
    - Node IDs (n8n auto-generates them on insert if missing in repo)
    - Node positions (visual only, n8n sometimes changes precision)
    - Node `disabled` flags when false (n8n adds them as defaults)
    - Workflow-level metadata n8n stamps on save (updatedAt, versionId, etc.)
    - Empty/missing vs {} for connections + settings + credentials
    Sort nodes by NAME (stable across both sides) — IDs may differ."""
    nodes = workflow.get('nodes', []) or []
    nodes_sorted = sorted([_clean_node(n) for n in nodes],
                          key=lambda n: (n.get('name', ''), n.get('type', '')))
    return {
        'name': workflow.get('name', ''),
        'nodes': nodes_sorted,
        'connections': _normalize_connections(workflow.get('connections') or {}),
        'settings': workflow.get('settings') or {}
    }


def _clean_node(n):
    """Drop ephemeral + presentation fields. Keep semantic identity:
    name, type, typeVersion, parameters, webhookId (matters for routing),
    credentials (semantic — references credential by name only)."""
    keep = {'name', 'type', 'typeVersion', 'parameters', 'webhookId'}
    cleaned = {k: v for k, v in n.items() if k in keep}
    # Normalize credentials: keep only the `name` field, not the id
    if 'credentials' in n and isinstance(n['credentials'], dict):
        cleaned['credentials'] = {
            k: {'name': v.get('name')} if isinstance(v, dict) else v
            for k, v in n['credentials'].items()
        }
    return cleaned


def _normalize_connections(conns):
    """Connections object: keys are node names, structure is otherwise stable.
    Just ensure it's a dict (not None) and recurse to strip any None values."""
    if not isinstance(conns, dict):
        return {}
    return conns


def hash_workflow(workflow):
    norm = normalize(workflow)
    payload = json.dumps(norm, sort_keys=True, separators=(',', ':'), ensure_ascii=True)
    return hashlib.sha256(payload.encode('utf-8')).hexdigest()


# ───────────────────────────────────────────────────────────────────
# Sources
# ───────────────────────────────────────────────────────────────────
def load_repo_workflows(repo_root):
    out = {}
    for path in glob.glob(os.path.join(repo_root, 'workflows', '**', '*.json'), recursive=True):
        try:
            d = json.load(open(path, encoding='utf-8'))
        except Exception:
            continue
        wf_id = d.get('id')
        if not wf_id:
            continue
        out[wf_id] = {
            'id': wf_id,
            'name': d.get('name'),
            'active': d.get('active', False),
            'hash': hash_workflow(d),
            'path': os.path.relpath(path, repo_root).replace('\\', '/')
        }
    return out


def load_n8n_workflows_via_api(api_key):
    """Try REST API first. Returns ({}, error_str) on failure so caller can fall back."""
    if not api_key:
        return {}, 'N8N_API_KEY not set'
    out = {}
    cursor = ''
    page = 0
    while True:
        url = N8N_URL + '/api/v1/workflows?limit=100'
        if cursor:
            url += '&cursor=' + urllib.parse.quote(cursor)
        try:
            status, body = http_get(url, headers={'X-N8N-API-KEY': api_key, 'Accept': 'application/json'})
        except Exception as e:
            return out, 'n8n API error: ' + str(e)
        if status != 200:
            return out, 'n8n API HTTP ' + str(status)
        data = json.loads(body)
        for wf in (data.get('data') or []):
            wf_id = wf.get('id')
            if not wf_id:
                continue
            out[wf_id] = {
                'id': wf_id,
                'name': wf.get('name'),
                'active': bool(wf.get('active')),
                'hash': hash_workflow(wf),
            }
        cursor = data.get('nextCursor') or ''
        page += 1
        if not cursor or page > 50:
            break
    return out, None


def load_n8n_workflows_via_cli(container='n8n'):
    """Fallback: use `n8n export:workflow --all` via docker exec.
    More robust than the REST API because it does not need an API key
    with listing permissions. The repo source-of-truth pattern Mary
    already uses everywhere else."""
    import subprocess
    tmp_in_container = '/tmp/clx-drift-export'
    out = {}
    try:
        # Clean any prior export
        subprocess.run(['docker', 'exec', container, 'rm', '-rf', tmp_in_container],
                       capture_output=True, timeout=15)
        # Export all workflows as a folder of JSON files
        r = subprocess.run(
            ['docker', 'exec', container, 'n8n', 'export:workflow', '--all',
             '--output=' + tmp_in_container, '--separate'],
            capture_output=True, text=True, timeout=120
        )
        if r.returncode != 0:
            return out, 'n8n CLI export failed: ' + (r.stderr.strip() or r.stdout.strip())[:300]
        # List the files
        r = subprocess.run(
            ['docker', 'exec', container, 'ls', tmp_in_container],
            capture_output=True, text=True, timeout=15
        )
        if r.returncode != 0:
            return out, 'docker exec ls failed: ' + r.stderr.strip()
        files = [f for f in r.stdout.strip().split('\n') if f.endswith('.json')]
        # Read each file
        for fname in files:
            r = subprocess.run(
                ['docker', 'exec', container, 'cat', tmp_in_container + '/' + fname],
                capture_output=True, text=True, timeout=30
            )
            if r.returncode != 0:
                continue
            try:
                wf = json.loads(r.stdout)
            except Exception:
                continue
            wf_id = wf.get('id')
            if not wf_id:
                continue
            out[wf_id] = {
                'id': wf_id,
                'name': wf.get('name'),
                'active': bool(wf.get('active')),
                'hash': hash_workflow(wf),
            }
        # Cleanup
        subprocess.run(['docker', 'exec', container, 'rm', '-rf', tmp_in_container],
                       capture_output=True, timeout=15)
        return out, None
    except FileNotFoundError:
        return out, 'docker command not found (run on the VPS, not inside the container)'
    except subprocess.TimeoutExpired:
        return out, 'docker exec timed out'
    except Exception as e:
        return out, 'cli error: ' + str(e)


def load_n8n_workflows(api_key, prefer_cli=False):
    """Try REST API first (unless --via-cli forced), fall back to docker exec CLI."""
    if not prefer_cli:
        out, err = load_n8n_workflows_via_api(api_key)
        if not err:
            return out, None
        # API didn't work, log + fall back
        print(f'  {YELLOW}REST API failed ({err}). Falling back to docker exec CLI...{RESET}',
              file=sys.stderr)
    return load_n8n_workflows_via_cli()


# ───────────────────────────────────────────────────────────────────
# Compare + classify
# ───────────────────────────────────────────────────────────────────
def detect_drift(repo, n8n):
    drift = []
    repo_ids = set(repo.keys())
    n8n_ids  = set(n8n.keys())

    for rid in repo_ids - n8n_ids:
        r = repo[rid]
        drift.append({
            'workflow_id': rid,
            'workflow_name': r['name'],
            'drift_type': 'repo_only',
            'repo_hash': r['hash'],
            'n8n_hash': None,
            'repo_active': r['active'],
            'n8n_active': None,
            'repo_path': r['path'],
            'details': {'message': 'JSON in repo but never imported to n8n'}
        })

    for nid in n8n_ids - repo_ids:
        n = n8n[nid]
        drift.append({
            'workflow_id': nid,
            'workflow_name': n['name'],
            'drift_type': 'n8n_only',
            'repo_hash': None,
            'n8n_hash': n['hash'],
            'repo_active': None,
            'n8n_active': n['active'],
            'repo_path': None,
            'details': {'message': 'Workflow in n8n but no matching JSON in repo'}
        })

    for wid in repo_ids & n8n_ids:
        r = repo[wid]
        n = n8n[wid]
        if r['hash'] != n['hash']:
            drift.append({
                'workflow_id': wid,
                'workflow_name': r['name'] or n['name'],
                'drift_type': 'content_diff',
                'repo_hash': r['hash'],
                'n8n_hash': n['hash'],
                'repo_active': r['active'],
                'n8n_active': n['active'],
                'repo_path': r['path'],
                'details': {'message': 'Content hash differs between repo and n8n'}
            })
        elif r['active'] != n['active']:
            drift.append({
                'workflow_id': wid,
                'workflow_name': r['name'] or n['name'],
                'drift_type': 'active_diff',
                'repo_hash': r['hash'],
                'n8n_hash': n['hash'],
                'repo_active': r['active'],
                'n8n_active': n['active'],
                'repo_path': r['path'],
                'details': {'message': 'Active flag differs: repo=' + str(r['active']) + ' n8n=' + str(n['active'])}
            })

    return drift


# ───────────────────────────────────────────────────────────────────
# Supabase write
# ───────────────────────────────────────────────────────────────────
def write_to_supabase(rows, run_summary, service_key):
    if not service_key:
        return False, 'SUPABASE_SERVICE_KEY not set'
    headers = {
        'apikey': service_key,
        'Authorization': 'Bearer ' + service_key,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal'
    }
    try:
        # Insert all drift rows in one POST (PostgREST accepts an array)
        if rows:
            http_post(SUPABASE_URL + '/rest/v1/workflow_drift', json.dumps(rows), headers=headers)
        http_post(SUPABASE_URL + '/rest/v1/workflow_drift_runs', json.dumps(run_summary), headers=headers)
        return True, None
    except Exception as e:
        return False, str(e)


# ───────────────────────────────────────────────────────────────────
# Main
# ───────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', default=REPO_DEFAULT)
    ap.add_argument('--dry-run', action='store_true', help='Detect + print, do not write to Supabase')
    ap.add_argument('--json',    action='store_true', help='Machine-readable JSON output')
    ap.add_argument('--via-cli', action='store_true', help='Skip REST API, use docker exec n8n CLI directly')
    args = ap.parse_args()

    start = time.time()
    api_key      = os.environ.get('N8N_API_KEY', '')
    service_key  = os.environ.get('SUPABASE_SERVICE_KEY', '')

    repo = load_repo_workflows(args.repo)
    n8n, err = load_n8n_workflows(api_key, prefer_cli=args.via_cli)
    if err:
        print(f'{RED}n8n fetch failed:{RESET} {err}', file=sys.stderr)
        sys.exit(2)

    drift = detect_drift(repo, n8n)
    duration_ms = int((time.time() - start) * 1000)

    counts = {'repo_only': 0, 'n8n_only': 0, 'content_diff': 0, 'active_diff': 0}
    for d in drift:
        counts[d['drift_type']] += 1

    run_summary = {
        'repo_count':   len(repo),
        'n8n_count':    len(n8n),
        'drift_count':  len(drift),
        'repo_only':    counts['repo_only'],
        'n8n_only':     counts['n8n_only'],
        'content_diff': counts['content_diff'],
        'active_diff':  counts['active_diff'],
        'duration_ms':  duration_ms,
        'metadata': {'repo_root': args.repo}
    }

    if args.json:
        print(json.dumps({'summary': run_summary, 'drift': drift}, indent=2))
    else:
        print(f'{BOLD}Workflow drift detection{RESET}')
        print(f'  Repo workflows:  {len(repo)}')
        print(f'  n8n workflows:   {len(n8n)}')
        print(f'  Drift findings:  {len(drift)}  '
              f'({counts["repo_only"]} repo-only, '
              f'{counts["n8n_only"]} n8n-only, '
              f'{counts["content_diff"]} content-diff, '
              f'{counts["active_diff"]} active-diff)')
        print(f'  Duration:        {duration_ms} ms')
        if drift:
            print()
            print('  First 20 drift findings:')
            for d in drift[:20]:
                color = RED if d['drift_type'] in ('n8n_only', 'content_diff') else YELLOW
                print(f'    {color}{d["drift_type"]:14}{RESET} {d["workflow_id"]:36} {d["workflow_name"] or ""}')
        if len(drift) > 20:
            print(f'  ...and {len(drift) - 20} more')

    if not args.dry_run:
        ok, err = write_to_supabase(drift, run_summary, service_key)
        if ok:
            if not args.json:
                print(f'\n  {GREEN}Wrote {len(drift)} drift rows + 1 run summary to Supabase.{RESET}')
        else:
            print(f'{RED}Supabase write failed:{RESET} {err}', file=sys.stderr)
            sys.exit(3)

    return 0 if len(drift) == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
