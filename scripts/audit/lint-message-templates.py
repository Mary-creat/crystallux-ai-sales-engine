#!/usr/bin/env python3
"""
scripts/audit/lint-message-templates.py

Scans every workflow JSON + HTML page for customer-facing copy that
violates the rules in docs/handbook/BRAND_VOICE.md.

Usage:
  python3 scripts/audit/lint-message-templates.py             # full repo
  python3 scripts/audit/lint-message-templates.py --fix       # write fixes for trivial issues (em-dashes)
  python3 scripts/audit/lint-message-templates.py --workflows # only workflow JSONs
  python3 scripts/audit/lint-message-templates.py --json      # machine-readable output

What it flags:
  - Em-dashes (U+2014)
  - En-dashes (U+2013) outside number ranges
  - "Hope this finds you well" / "I hope you're doing well"
  - "I wanted to reach out" / "Just touching base"
  - "Sincerely" / "Warmest regards" / "Best regards" sign-offs
  - "The Crystallux Team" attribution
  - Triple-emoji headers
  - "As an AI" disclosures
  - Empty intensifiers (amazing, incredible, absolutely)

What it auto-fixes with --fix:
  - Em-dashes → " — " becomes " - " (or period+space if mid-sentence)
  - No other auto-fixes (changes that need human judgment stay flagged).
"""

import argparse
import glob
import json
import os
import re
import sys
from collections import defaultdict

try:
    sys.stdout.reconfigure(encoding='utf-8')
except (AttributeError, OSError):
    pass

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Patterns: (severity, pattern_name, regex, description, auto_fixable)
PATTERNS = [
    ('high',   'em_dash',           r'—',                                                 'em-dash (AI tell)',                       True),
    ('medium', 'en_dash_outside_range', r'(?<!\d)–(?!\d)',                                'en-dash outside number range',            False),
    ('high',   'generic_opener_hope', r'\bhope\s+(?:this|you|your\s+\w+)\s+(?:finds?\s+you|are?\s+)\s*(?:well|doing\s+well)\b', 'generic "hope this finds you well" opener', False),
    ('high',   'generic_reach_out', r'\bI\s+(?:just\s+)?wanted\s+to\s+reach\s+out\b',     'generic "wanted to reach out" opener',   False),
    ('high',   'just_touching',     r'\bjust\s+touching\s+base\b',                        'generic "just touching base"',           False),
    ('medium', 'stilted_signoff',   r'\b(?:Sincerely|Warm(?:est)?\s+regards|Best\s+regards|Kind(?:ly|est)?\s+regards|Yours\s+truly)\s*,?\s*\n?', 'stilted sign-off', False),
    ('medium', 'team_attribution', r'\bThe\s+Crystallux\s+Team\b',                        'impersonal "The Crystallux Team" attribution', False),
    ('medium', 'triple_emoji',      r'(?:[☀-➿\U0001F300-\U0001FAFF])\s*(?:[☀-➿\U0001F300-\U0001FAFF])\s*(?:[☀-➿\U0001F300-\U0001FAFF])', 'triple-emoji header (auto-gen look)', False),
    ('high',   'ai_disclosure',     r'\b(?:As\s+an\s+AI|I[\'’]m\s+an?\s+AI)\b',      'AI disclosure leaking through',          False),
    ('low',    'empty_intensifier_amazing',    r'\bamazing\b',     'empty intensifier "amazing"',     False),
    ('low',    'empty_intensifier_incredible', r'\bincredible\b',  'empty intensifier "incredible"',  False),
    ('low',    'empty_intensifier_absolutely', r'\babsolutely\b',  'empty intensifier "absolutely"',  False),
]

# Workflow node parameters whose values are customer-facing copy.
# We scan these specifically; everything else gets a broader text scan.
CUSTOMER_FACING_NODE_PARAM_KEYS = {
    'jsonBody', 'body', 'message', 'text', 'html', 'htmlBody', 'subject',
    'emailBody', 'smsBody', 'whatsappBody', 'value'
}

# Files where we EXPECT em-dashes (handbooks, design docs, README)
ALLOWLIST_FILES = {
    'docs/handbook/BRAND_VOICE.md',  # documents the rules themselves
    'scripts/audit/lint-message-templates.py',  # this file
}


def _c(code):
    return code if sys.stdout.isatty() else ''
RED   = _c('\033[31m')
YEL   = _c('\033[33m')
GRN   = _c('\033[32m')
DIM   = _c('\033[2m')
BOLD  = _c('\033[1m')
RESET = _c('\033[0m')


def find_violations_in_text(text):
    out = []
    for severity, name, pattern, description, fixable in PATTERNS:
        for m in re.finditer(pattern, text, flags=re.IGNORECASE):
            out.append({
                'severity': severity,
                'name': name,
                'description': description,
                'match': m.group(0),
                'pos': m.start(),
                'fixable': fixable,
            })
    return out


def scan_workflow(path):
    """Return list of {node, field, violations[]} per problematic text in workflow JSON."""
    findings = []
    try:
        d = json.load(open(path, encoding='utf-8'))
    except Exception:
        return findings
    for n in d.get('nodes', []):
        params = n.get('parameters') or {}
        node_name = n.get('name', 'unnamed')
        # JS code blocks
        if isinstance(params.get('jsCode'), str):
            v = find_violations_in_text(params['jsCode'])
            if v:
                findings.append({'node': node_name, 'field': 'jsCode', 'violations': v})
        # JSON body templates
        if isinstance(params.get('jsonBody'), str):
            v = find_violations_in_text(params['jsonBody'])
            if v:
                findings.append({'node': node_name, 'field': 'jsonBody', 'violations': v})
        # HeaderParameters
        hp = params.get('headerParameters') or {}
        for hpp in (hp.get('parameters') or []):
            val = hpp.get('value')
            if isinstance(val, str):
                v = find_violations_in_text(val)
                if v:
                    findings.append({'node': node_name, 'field': 'header[' + hpp.get('name', '?') + ']', 'violations': v})
    return findings


def scan_file_text(path):
    try:
        text = open(path, encoding='utf-8').read()
    except Exception:
        return []
    return find_violations_in_text(text)


def apply_em_dash_fix(path):
    """Replace em-dashes with ' - ' or '. ' depending on context. Returns count replaced."""
    try:
        text = open(path, encoding='utf-8').read()
    except Exception:
        return 0
    count = text.count('—')
    if not count:
        return 0
    # Replace " — " (with surrounding spaces) → " - "
    fixed = re.sub(r'\s+—\s+', ' - ', text)
    # Replace standalone "—" → " - "
    fixed = fixed.replace('—', ' - ')
    open(path, 'w', encoding='utf-8').write(fixed)
    return count


def main():
    ap = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--fix', action='store_true', help='Auto-fix em-dashes (no other fixes).')
    ap.add_argument('--workflows', action='store_true', help='Only scan workflow JSONs.')
    ap.add_argument('--pages',     action='store_true', help='Only scan HTML pages.')
    ap.add_argument('--json',      action='store_true', help='Machine-readable JSON output.')
    args = ap.parse_args()

    if args.workflows:
        files = glob.glob(os.path.join(REPO_ROOT, 'workflows', '**', '*.json'), recursive=True)
    elif args.pages:
        files = (
            glob.glob(os.path.join(REPO_ROOT, 'admin-dashboard', 'pages', '**', '*.html'), recursive=True) +
            glob.glob(os.path.join(REPO_ROOT, 'client-dashboard', 'pages', '**', '*.html'), recursive=True) +
            glob.glob(os.path.join(REPO_ROOT, 'insurance-mga-dashboard', '**', '*.html'), recursive=True) +
            glob.glob(os.path.join(REPO_ROOT, 'site', '*.html')) +
            glob.glob(os.path.join(REPO_ROOT, 'insurer-marketing', '*.html'))
        )
    else:
        files = (
            glob.glob(os.path.join(REPO_ROOT, 'workflows', '**', '*.json'), recursive=True) +
            glob.glob(os.path.join(REPO_ROOT, 'admin-dashboard', 'pages', '**', '*.html'), recursive=True) +
            glob.glob(os.path.join(REPO_ROOT, 'client-dashboard', 'pages', '**', '*.html'), recursive=True) +
            glob.glob(os.path.join(REPO_ROOT, 'insurance-mga-dashboard', '**', '*.html'), recursive=True) +
            glob.glob(os.path.join(REPO_ROOT, 'site', '*.html')) +
            glob.glob(os.path.join(REPO_ROOT, 'insurer-marketing', '*.html'))
        )

    all_findings = []
    fixed_em_dashes = 0

    for f in sorted(files):
        rel = os.path.relpath(f, REPO_ROOT).replace('\\', '/')
        if rel in ALLOWLIST_FILES:
            continue
        if f.endswith('.json'):
            wf_findings = scan_workflow(f)
            if wf_findings:
                all_findings.append({'file': rel, 'findings': wf_findings})
        else:
            text_findings = scan_file_text(f)
            if text_findings:
                all_findings.append({'file': rel, 'findings': [{'node': 'text', 'field': 'body', 'violations': text_findings}]})
        if args.fix:
            n = apply_em_dash_fix(f)
            fixed_em_dashes += n

    if args.json:
        print(json.dumps({'findings': all_findings, 'fixed_em_dashes': fixed_em_dashes}, indent=2))
        return 0 if not all_findings else 1

    # Pretty print
    if not all_findings:
        print(f'{GRN}{BOLD}All clean.{RESET} No brand-voice violations found.')
        if args.fix:
            print(f'  {DIM}(--fix had nothing to fix){RESET}')
        return 0

    severity_counts = defaultdict(int)
    pattern_counts = defaultdict(int)
    file_counts = defaultdict(int)

    for f in all_findings:
        for nf in f['findings']:
            for v in nf['violations']:
                severity_counts[v['severity']] += 1
                pattern_counts[v['name']] += 1
                file_counts[f['file']] += 1

    print(f'{BOLD}Brand voice audit — {len(all_findings)} file(s) with violations{RESET}')
    print()
    print('  By severity:')
    for s in ['high', 'medium', 'low']:
        n = severity_counts.get(s, 0)
        color = RED if s == 'high' else (YEL if s == 'medium' else DIM)
        print(f'    {color}{s:6}{RESET} {n}')
    print()
    print('  By pattern (top 10):')
    for name, n in sorted(pattern_counts.items(), key=lambda kv: -kv[1])[:10]:
        print(f'    {name:35} {n}')
    print()
    print('  By file (top 15):')
    for fp, n in sorted(file_counts.items(), key=lambda kv: -kv[1])[:15]:
        print(f'    {n:4}  {fp}')
    print()

    if args.fix and fixed_em_dashes:
        print(f'  {GRN}Auto-fixed {fixed_em_dashes} em-dashes across files. Re-run the lint to see remaining manual fixes.{RESET}')
    elif args.fix:
        print(f'  {DIM}(--fix had nothing to auto-replace; remaining violations need manual edits){RESET}')

    return 1


if __name__ == '__main__':
    sys.exit(main())
