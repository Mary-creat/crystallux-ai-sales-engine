#!/usr/bin/env python3
"""
scripts/n8n/add-top-level-ids.py

Ensures every workflow JSON under workflows/**/*.json has a top-level
`"id"` field. Missing top-level ids are the root cause of the workflow
duplication mess Mary discovered on 2026-05-19 (see
docs/audit/blockers.md entry 0n + docs/audit/WORKFLOW_DEDUPE_PLAN.md):
without a fixed id, every `n8n import:workflow` / UI import creates a
new row instead of updating the existing one.

Derives a deterministic camelCase id from the workflow `name`. Existing
ids are NEVER overwritten — this script only fills in missing ones.

Usage:
  # Audit only — list which files are missing an id, exit 0/1:
  python3 scripts/n8n/add-top-level-ids.py --check

  # Mutate files in place to add deterministic ids:
  python3 scripts/n8n/add-top-level-ids.py --apply

  # Preview the diff without writing:
  python3 scripts/n8n/add-top-level-ids.py --apply --dry-run

Deterministic id derivation from name:
  "CLX - Lead Research v2"        -> "clxLeadResearchV2"
  "CLX - Admin List Clients v1"   -> "clxAdminListClientsV1"
  "CLX - B2C Discovery v2.1"      -> "clxB2cDiscoveryV21"

If multiple JSONs derive the same id (name collision), the script fails
loudly rather than silently producing duplicates — fix the underlying
name conflict in those files first.

CI integration:
  Add `python3 scripts/n8n/add-top-level-ids.py --check` to pre-commit
  / GitHub Actions. Any future workflow JSON without an id will fail
  the build.
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

REPO_DEFAULT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def derive_id(name):
    """
    Deterministic name -> camelCase id.

      "CLX - Lead Research v2"      -> "clxLeadResearchV2"
      "CLX - Admin Workflow Status" -> "clxAdminWorkflowStatus"
      "CLX-Lead import"             -> "clxLeadImport"
    """
    s = name
    # Strip "CLX -" / "CLX-" / "CLX " prefix (and any leading separators).
    s = re.sub(r'^\s*CLX\s*[-:]?\s*', '', s, flags=re.IGNORECASE)
    # Split on runs of non-alphanumerics; drop empties.
    parts = [p for p in re.split(r'[^A-Za-z0-9]+', s) if p]
    if not parts:
        raise ValueError(f'cannot derive id from name: {name!r}')
    # CamelCase: first char of each chunk uppercased, but for chunks like
    # "v2" or "V21" keep the original casing of digits and only uppercase
    # the alpha prefix.
    def cap(chunk):
        # Pull leading alpha run and trailing digits separately so v2 -> V2.
        m = re.match(r'^([A-Za-z]+)(\d*)$', chunk)
        if m:
            alpha, digits = m.group(1), m.group(2)
            return alpha[:1].upper() + alpha[1:].lower() + digits
        # Mixed / odd — just title-case the leading char.
        return chunk[:1].upper() + chunk[1:].lower()
    body = ''.join(cap(p) for p in parts)
    return 'clx' + body


def scan(repo_root):
    """Return list of (path, json_obj, current_id_or_None)."""
    rows = []
    for fn in glob.glob(os.path.join(repo_root, 'workflows', '**', '*.json'),
                        recursive=True):
        try:
            with open(fn, encoding='utf-8') as f:
                # Preserve key order — Python 3.7+ dict preserves insertion.
                d = json.load(f)
        except Exception as e:
            print(f'WARN: skipping {fn}: {e}', file=sys.stderr)
            continue
        rows.append((fn, d, d.get('id')))
    return rows


def check_collisions(rows):
    """
    If we filled in ids deterministically for everything missing one,
    would any collide with each other or with an existing id?
    """
    final_ids = defaultdict(list)
    for fn, d, current in rows:
        if current:
            final_ids[current].append(fn)
        else:
            try:
                final_ids[derive_id(d.get('name', ''))].append(fn)
            except ValueError as e:
                print(f'ERROR: {fn}: {e}', file=sys.stderr)
    collisions = {k: v for k, v in final_ids.items() if len(v) > 1}
    return collisions


def write_with_id_first(path, _d, new_id):
    """
    Insert `"id": "<new_id>",` right after the opening `{` of the file,
    preserving every other byte of original formatting (whitespace,
    line endings, key ordering).

    A JSON parse+serialize roundtrip would reformat the entire file
    (e.g. inline `[200, 300]` -> 3-line array), producing a 200-line
    diff per file and obscuring what actually changed. This text-mode
    insertion produces a 1-line diff per file: the inserted id.
    """
    with open(path, 'rb') as f:
        raw = f.read()
    # Strip + remember UTF-8 BOM if present
    bom = b''
    if raw.startswith(b'\xef\xbb\xbf'):
        bom, raw = raw[:3], raw[3:]
    text = raw.decode('utf-8')
    # Match: opening brace, then the newline (preserving CRLF/LF),
    # then the indentation of the next key.
    m = re.match(r'^(\s*\{)([\r\n]+)([ \t]*)', text)
    if not m:
        raise ValueError(f"file does not start with '{{' + newline: {path}")
    brace, newline, indent = m.group(1), m.group(2), m.group(3)
    head_end = m.end(2)  # cursor right after the newline; preserves the indent
    insertion = f'{indent}"id": "{new_id}",{newline}'
    new_text = text[:head_end] + insertion + text[head_end:]
    with open(path, 'wb') as f:
        f.write(bom + new_text.encode('utf-8'))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    grp = ap.add_mutually_exclusive_group(required=True)
    grp.add_argument('--check', action='store_true',
                     help='Audit only; exit 1 if any JSON lacks a top-level id.')
    grp.add_argument('--apply', action='store_true',
                     help='Fill in missing ids (mutates files in place).')
    ap.add_argument('--dry-run', action='store_true',
                    help='With --apply, show what would change but do not write.')
    ap.add_argument('--repo', default=REPO_DEFAULT)
    args = ap.parse_args()

    rows = scan(args.repo)
    missing = [(fn, d) for fn, d, cur in rows if not cur]

    print(f'Scanned {len(rows)} workflow JSONs.')
    print(f'  With top-level id:    {len(rows) - len(missing)}')
    print(f'  Without top-level id: {len(missing)}')
    print()

    if not missing:
        print('All workflow JSONs have a top-level id. Nothing to do.')
        return 0

    collisions = check_collisions(rows)
    if collisions:
        print('COLLISIONS — fix workflow name conflicts before filling ids:', file=sys.stderr)
        for cid, files in collisions.items():
            print(f'  {cid!r} would be assigned to:', file=sys.stderr)
            for f in files:
                print(f'    {f}', file=sys.stderr)
        return 2

    if args.check:
        print('Files missing top-level id:')
        for fn, d in missing:
            new_id = derive_id(d.get('name', ''))
            rel = os.path.relpath(fn, args.repo).replace('\\', '/')
            print(f'  {rel}  ->  would assign id  {new_id!r}')
        return 1

    # --apply
    print(f'Filling in {len(missing)} ids:')
    for fn, d in missing:
        new_id = derive_id(d.get('name', ''))
        rel = os.path.relpath(fn, args.repo).replace('\\', '/')
        print(f'  {rel}  ->  {new_id}')
        if not args.dry_run:
            write_with_id_first(fn, d, new_id)
    if args.dry_run:
        print('(dry-run — no files written)')
    else:
        print(f'\nDone. {len(missing)} files updated.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
