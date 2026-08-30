#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Shape a workflow JSON into a body n8n's PUT /api/v1/workflows/{id} accepts.

    python3 scripts/n8n/n8n-put-body.py workflows/api/admin/foo.json > body.json

n8n's REST API is stricter than its own UI export. The export carries
settings keys the API then refuses -- `binaryMode` and `availableInMCP`
are the two that have actually bitten us -- and answers the whole request
with `settings must NOT have additional properties` (HTTP 400). That was
commit 68fad4a: every ship.sh update silently fell through to the slower
CLI path because of two keys nobody sent on purpose.

The API also ignores `active` on this endpoint, which is the property we
want: a deploy updates a workflow's definition and leaves its live
activation state alone. Activation is per-client, per-tier and Mary's
call (CLAUDE.md, dormant-by-default policy).

Emits name + nodes + connections + settings, and nothing else.
"""
import json
import sys

# Everything n8n's PUT accepts under `settings`. Anything else in the
# file stays in the file; it just is not sent.
ALLOWED_SETTINGS = {
    'executionOrder',
    'saveDataErrorExecution',
    'saveDataSuccessExecution',
    'saveManualExecutions',
    'saveExecutionProgress',
    'executionTimeout',
    'errorWorkflow',
    'timezone',
    'callerPolicy',
    'callerIds',
}


def put_body(workflow):
    settings = {
        k: v for k, v in (workflow.get('settings') or {}).items()
        if k in ALLOWED_SETTINGS
    }
    return {
        'name': workflow.get('name'),
        'nodes': workflow.get('nodes', []),
        'connections': workflow.get('connections', {}),
        # n8n rejects an absent settings object, so fall back to the
        # repo-wide default rather than sending {}.
        'settings': settings or {'executionOrder': 'v1'},
    }


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('usage: n8n-put-body.py <workflow.json>\n')
        return 2
    with open(argv[1], encoding='utf-8') as fh:
        workflow = json.load(fh)
    if not workflow.get('name'):
        sys.stderr.write('%s: no top-level "name" -- n8n will reject this\n' % argv[1])
        return 1
    json.dump(put_body(workflow), sys.stdout)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
