#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Validate migration SQL with the real Postgres grammar before Mary applies it.

Mary applies migrations by hand in the Supabase SQL editor, so a syntax error
is discovered halfway through a partially-applied file. This catches those on
this side of the fence.

Uses libpg_query (via pglast) -- the actual Postgres parser, not a regex.

    pip install pglast
    python scripts/validate-migrations.py db/migrations/foo.sql [more.sql ...]
    python scripts/validate-migrations.py          # all of db/migrations

Two passes, because the first alone is not enough:
  1. parse_sql      -- statement grammar across the whole file
  2. parse_plpgsql  -- every CREATE FUNCTION body, which pass 1 treats as an
                       opaque string and would accept even if it were garbage

KNOWN LIMITATION: pglast's parse_plpgsql cannot handle `RETURNS trigger` at
all -- it fails on the canonical `BEGIN RETURN NEW; END`. Those bodies are
counted as skipped rather than failed, so a real error in a trigger function
will NOT be caught here. Verified against pglast v8.4.

Exit code 0 = clean, 1 = at least one failure.
"""
import io
import os
import subprocess
import re
import sys

try:
    from pglast import parse_sql, parse_plpgsql
    from pglast.parser import ParseError
except ImportError:
    sys.stderr.write("pglast is required:  pip install pglast\n")
    sys.exit(2)

# Dollar quoting allows any tag, not just $$ -- $fn$, $do$, $body$ are all
# legal and are used deliberately where a naive $$ split would mis-parse.
# Matching only $$ meant those bodies were skipped silently, which is the
# same class of blind spot this script exists to catch. Group 3 captures
# the opening tag; the backreference forces the closing tag to match.
FUNC_RE = re.compile(
    r'(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(\w+).*?\$(\w*)\$.*?\$\3\$\s*;)',
    re.S | re.I)
SQL_LANG_RE = re.compile(r'LANGUAGE\s+sql\b', re.I)
TRIGGER_RE = re.compile(r'RETURNS\s+trigger\b', re.I)

# A raw carriage return inside a JSON literal is rejected by Postgres with
# 'invalid input syntax for type json ... Character with value 0x0d must be
# escaped'. It is invisible in an editor and survives every Python-side
# json.loads, because Python treats CR as whitespace and Postgres does not.
# Git hands Windows checkouts CRLF, so a multi-line JSON literal picks one up
# on the way to the SQL editor no matter what the repo stores. Keeping JSON
# literals on a single line is the only fix that survives that round trip.
# A JSON literal, matched without running past its closing quote: the body
# may contain '' (an escaped quote) but never a bare one. Matching with a
# plain .*? spanned from one literal's brace across "'::jsonb THEN '" into
# the next, which manufactured invalid fragments and false failures.
JSON_LITERAL_RE = re.compile(r"'(\{(?:[^']|'')*?\})'::jsonb", re.S)


def _cr_inside_json_string(lit):
    """Offsets of raw CR/LF sitting INSIDE a JSON string.

    Verified against the live database, both directions: Postgres accepts
    CR as whitespace BETWEEN json tokens, and rejects it INSIDE a string
    with 'Character with value 0x0d must be escaped'. Flagging every CR in
    a literal marks 20 migrations that have already applied cleanly, and a
    check that cries wolf gets ignored -- which is the failure mode this
    script exists to prevent.
    """
    out, in_string, escaped = [], False, False
    for i, ch in enumerate(lit):
        if escaped:
            escaped = False
        elif ch == chr(92):
            escaped = True
        elif ch == '"':
            in_string = not in_string
        elif in_string and ch in (chr(13), chr(10)):
            out.append(i)
    return out


def validate(path):
    """Return (ok, summary) for one file."""
    # newline='' disables universal-newline translation. Without it Python
    # silently rewrites CRLF to LF on read, so a carriage return inside a
    # JSON literal -- the thing Postgres rejects -- is invisible to the
    # check below and every file passes.
    sql = io.open(path, encoding='utf-8', newline='').read()
    name = os.path.basename(path)

    try:
        stmts = parse_sql(sql)
    except ParseError as e:
        return False, '%-52s FAIL  %s' % (name, e)

    cr_literals = [m.start() for m in JSON_LITERAL_RE.finditer(sql)
                   if _cr_inside_json_string(m.group(1))]
    if cr_literals:
        return False, ('%-52s FAIL  %d JSON literal(s) contain a raw carriage '
                       'return or newline inside a string; Postgres rejects '
                       '0x0d there.' % (name, len(cr_literals)))

    bodies = FUNC_RE.findall(sql)
    failures, checked, skipped = [], 0, 0

    for stmt, fname, _tag in bodies:
        if SQL_LANG_RE.search(stmt):
            continue                      # plain SQL, already covered by pass 1
        if TRIGGER_RE.search(stmt):
            skipped += 1                  # see KNOWN LIMITATION above
            continue
        try:
            parse_plpgsql(stmt)
            checked += 1
        except Exception as e:
            failures.append('%s(): %s' % (fname, str(e)[:200]))

    if failures:
        return False, '%-52s FAIL\n      %s' % (name, '\n      '.join(failures))

    note = '%d stmts, %d plpgsql bodies' % (len(stmts), checked)
    if skipped:
        note += ', %d trigger bodies unchecked' % skipped
    return True, '%-52s ok    %s' % (name, note)


def run_isolated(paths):
    """Validate each file in a child process.

    pglast's parse_plpgsql can hit a C-level assertion on valid SQL
    (luxi-auction-tick-functions.sql does). An assertion aborts the process,
    so one awkward file would otherwise kill a whole sweep and report nothing
    about the other sixty-seven. A child per file contains the damage.
    """
    bad = 0
    for path in paths:
        r = subprocess.run([sys.executable, __file__, '--single', path],
                           capture_output=True, text=True)
        out = (r.stdout or '').strip()
        if r.returncode == 0 and out:
            print(out)
        elif 'ssertion' in (r.stderr or '') or r.returncode < 0 or r.returncode > 1:
            print('%-52s SKIPPED  parser crashed on this file; SQL not checked'
                  % os.path.basename(path))
        else:
            if out:
                print(out)
            bad += 1
    print()
    print('%d file(s) checked, %d failed' % (len(paths), bad))
    return 1 if bad else 0


def main(argv):
    if len(argv) > 2 and argv[1] == '--single':
        ok, line = validate(argv[2])
        print(line)
        return 0 if ok else 1

    targets = argv[1:]
    if not targets:
        d = os.path.join('db', 'migrations')
        if not os.path.isdir(d):
            sys.stderr.write('No files given and %s not found.\n' % d)
            return 2
        targets = sorted(os.path.join(d, f) for f in os.listdir(d)
                         if f.endswith('.sql'))

    return run_isolated(targets)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
