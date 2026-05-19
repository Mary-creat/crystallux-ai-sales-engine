#!/usr/bin/env python3
"""
scripts/n8n/audit-webhook-endpoints.py

Scans every frontend page for clxApi.adminGet / mgaPost / call / etc.,
extracts the webhook URL it expects, looks up the corresponding workflow
file in workflows/api/, and live-probes the production URL to classify
the live state. Emits a markdown table per URL + a status summary.

Run periodically (especially after a workflow import / cleanup pass)
to confirm which endpoints are: HEALTHY, EMPTY-200 (bug from blockers
0m), NOT-ACTIVE (workflow in repo but inactive), NO-WORKFLOW (TODO),
N8N-500 (server-side), BAD-INPUT (active, needs valid body).

Usage:
  python3 scripts/n8n/audit-webhook-endpoints.py > docs/audit/WEBHOOK_INVENTORY.md
  python3 scripts/n8n/audit-webhook-endpoints.py --json > /tmp/audit.json
  python3 scripts/n8n/audit-webhook-endpoints.py --no-probe   # repo-only, fast
"""

import json, glob, re, subprocess, os, sys, argparse

# Force UTF-8 stdout so unicode characters in the markdown render on
# Windows consoles (which default to cp1252) and unix terminals alike.
try:
    sys.stdout.reconfigure(encoding='utf-8')
except (AttributeError, OSError):
    pass  # older Python or non-reconfigurable stream — fall through

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = 'https://automation.crystallux.org/webhook'

# Frontend → URL prefix
PATTERNS = [
    (re.compile(r"adminGet\(\s*['\"]([^'\"]+)['\"]"),  'admin/'),
    (re.compile(r"adminPost\(\s*['\"]([^'\"]+)['\"]"), 'admin/'),
    (re.compile(r"mgaPost\(\s*['\"]([^'\"]+)['\"]"),   'mga/insurance/'),
    (re.compile(r"postApi\(\s*['\"]([^'\"]+)['\"]"),   'api/'),
    (re.compile(r"postWebhook\(\s*['\"]([^'\"]+)['\"]"), ''),
    (re.compile(r"\.call\(\s*['\"]([^'\"]+)['\"]"),    ''),
]

SCAN_ROOTS = ['admin-dashboard', 'client-dashboard',
              'insurance-mga-dashboard', 'insurer-dashboard']

# Pages use dynamic-suffix patterns (e.g. mgaPost('calculator/'+key)) where
# the audit captures the prefix as a literal. Map to a concrete URL for live
# probing so we get the real workflow state.
DYNAMIC_SUBS = {
    'mga/insurance/calculator/': 'mga/insurance/calculator/dependent-support',
}


def collect_frontend():
    """Return {url: [(file, line), ...]} for every webhook URL the frontend calls."""
    urls = {}
    for root in SCAN_ROOTS:
        for fn in glob.glob(os.path.join(REPO_ROOT, root, '**/*.html'), recursive=True):
            try:
                with open(fn, encoding='utf-8') as f:
                    lines = f.readlines()
            except Exception:
                continue
            for i, ln in enumerate(lines, 1):
                for rx, prefix in PATTERNS:
                    for m in rx.finditer(ln):
                        url = (prefix + m.group(1)).replace('//', '/')
                        if url.startswith('/'):
                            url = url[1:]
                        rel = os.path.relpath(fn, REPO_ROOT).replace('\\', '/')
                        urls.setdefault(url, []).append((rel, i))
    return urls


def collect_workflows():
    """Return {webhook_path: [workflow_file, ...]} from workflow JSONs."""
    paths = {}
    for fn in glob.glob(os.path.join(REPO_ROOT, 'workflows/**/*.json'), recursive=True):
        try:
            d = json.load(open(fn, encoding='utf-8'))
        except Exception:
            continue
        for n in d.get('nodes', []):
            if n.get('type') == 'n8n-nodes-base.webhook':
                p = n.get('parameters', {}).get('path', '')
                if p:
                    rel = os.path.relpath(fn, REPO_ROOT).replace('\\', '/')
                    paths.setdefault(p, []).append(rel)
    return paths


def probe(url):
    """POST with junk Bearer; return (http_code, body_size, body_preview)."""
    try:
        r = subprocess.run([
            'curl', '-s', '-o', '/tmp/_audit_body', '-w', '%{http_code}',
            '--max-time', '8',
            '-X', 'POST',
            '-H', 'Content-Type: application/json',
            '-H', 'Authorization: Bearer junk',
            f'{BASE}/{url}',
            '-d', '{}'
        ], capture_output=True, text=True, timeout=12)
        code = r.stdout.strip() or '0'
        try:
            with open('/tmp/_audit_body', 'r', encoding='utf-8', errors='replace') as f:
                body = f.read()
        except Exception:
            body = ''
        return code, len(body), body[:120]
    except subprocess.TimeoutExpired:
        return 'timeout', 0, ''
    except FileNotFoundError:
        return 'no-curl', 0, ''


def classify(code, size, has_workflow):
    if code == '401':
        return 'HEALTHY', 'workflow active + auth-gated (proper 401 with body)'
    if code == '200' and size == 0:
        return 'EMPTY-200', 'workflow halts on Validate Session error; fix in 6e44d0c (re-import to live n8n)'
    if code == '500':
        return 'N8N-500', 'n8n throwing — check `docker logs n8n` (see blockers 0l)'
    if code == '404':
        if has_workflow:
            return 'NOT-ACTIVE', 'workflow file exists in repo but inactive/un-imported on the live n8n'
        return 'NO-WORKFLOW', 'no workflow file in repo (page-authoring TODO)'
    if code == '400':
        return 'BAD-INPUT', 'workflow active; probe sent {} but workflow requires fields'
    if code == '200':
        return 'OK-200', 'returns 200 with body — manually verify auth path'
    return f'HTTP-{code}', ''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--json', action='store_true', help='Emit JSON instead of markdown.')
    ap.add_argument('--no-probe', action='store_true', help='Skip live probing (repo-only audit).')
    args = ap.parse_args()

    frontend = collect_frontend()
    registered = collect_workflows()

    rows = []
    for url in sorted(frontend):
        probe_url = DYNAMIC_SUBS.get(url, url)
        wf_file = (registered.get(probe_url) or registered.get(url) or [None])[0]
        if args.no_probe:
            code, size, body = '?', 0, ''
            status, why = ('UNPROBED', 'live state not probed')
        else:
            code, size, body = probe(probe_url)
            status, why = classify(code, size, bool(wf_file))
        rows.append({
            'url': url,
            'probe_url': probe_url if probe_url != url else None,
            'live_http': code,
            'status': status,
            'why': why,
            'workflow_file': wf_file or '(none)',
            'callers': frontend[url][:3],
        })

    if args.json:
        print(json.dumps(rows, indent=2))
        return

    # Markdown table
    print('# Webhook inventory — frontend ↔ workflow ↔ live state')
    print()
    print(f'Auto-generated by `scripts/n8n/audit-webhook-endpoints.py`.  ')
    print(f'**{len(frontend)}** frontend-called URLs · **{len(registered)}** registered workflow paths in repo.')
    print()
    print('## Status legend')
    print()
    print('| Status | Meaning | Mary action |')
    print('|---|---|---|')
    print('| `HEALTHY` | 401 with JSON body — auth-gated, reachable | none |')
    print('| `EMPTY-200` | 200 with 0-byte body — Validate Session halt | UI Import-from-File the workflow (fix in commit 6e44d0c) |')
    print('| `NOT-ACTIVE` | 404 — workflow in repo but not active on live n8n | Activate in n8n UI |')
    print('| `NO-WORKFLOW` | 404 — no workflow JSON in repo | Author the workflow (TODO) |')
    print('| `N8N-500` | 500 with HTML body — n8n throwing | Check `docker logs n8n` (blockers 0l) |')
    print('| `BAD-INPUT` | 400 — workflow active, probe lacks required fields | None — workflow is healthy |')
    print()
    print('## Endpoint table')
    print()
    print('| Frontend URL | Live HTTP | Status | Workflow file |')
    print('|---|---|---|---|')
    for r in rows:
        note = f' _(probed as `{r["probe_url"]}`)_' if r['probe_url'] else ''
        wf = r['workflow_file']
        wf_short = wf.split('/')[-1] if wf != '(none)' else '_(none)_'
        print(f'| `{r["url"]}`{note} | {r["live_http"]} | **{r["status"]}** | {wf_short} |')

    print()
    print('## Summary')
    from collections import Counter
    c = Counter(r['status'] for r in rows)
    print()
    for k, v in c.most_common():
        pct = round(100 * v / len(rows)) if rows else 0
        print(f'- **{k}** — {v} ({pct}%)')

    print()
    print('## Next actions (Mary)')
    print()
    print('1. **For every `EMPTY-200` row**: UI Import-from-File the listed workflow into n8n. The fix in commit `6e44d0c` adds `neverError: true` to the Validate Session node — once imported, the row flips to `HEALTHY`. Status will recompute on next run of this script.')
    print('2. **For every `NOT-ACTIVE` row that matters**: activate via the n8n UI toggle. Many of these are pages you don\'t use actively yet (training, goals, sentinel sub-features) — only activate the ones you need for the current demo path.')
    print('3. **For `NO-WORKFLOW` rows**: those are page-authoring TODOs; they exist as graceful-failure paths in the page JS (the comment in `dashboard-home.html` says "reuse … if it exists"). No platform regression — just unfinished features.')
    print('4. **For `N8N-500` rows**: SSH and run `docker logs n8n --tail 300 | grep -A 6 <endpoint>`. Most common cause is a missing DB table or unconfigured credential (see blockers `0l`).')


if __name__ == '__main__':
    main()
