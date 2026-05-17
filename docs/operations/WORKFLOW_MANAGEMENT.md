# n8n workflow management runbook

The single-source-of-truth for "how do I get a workflow into / out of / updated in n8n on the VPS without creating a duplicate."

Codifies the lessons learned in commits `0699af8` (auth fix) and `40a1103` (the import-vs-update gotcha), plus the audit/cleanup tooling from this commit.

## Mental model

There are **two stores** that hold workflow definitions:

| Store | What it is | Authoritative for |
|---|---|---|
| **Git repo** (`workflows/`) | The JSON source files in this repository | Reviewable diff history; what gets shipped |
| **n8n SQLite** (`~/.n8n/database.sqlite` inside the n8n container) | Runtime workflow state — every workflow Crystallux has ever imported | What the live n8n actually executes |

A workflow JSON in git is **not automatically reflected in n8n.** Every change to a JSON file needs an explicit ship step on the VPS. Likewise, a workflow you create in the n8n UI is **not automatically reflected in git** — you have to `export:workflow` and commit the JSON.

When the two diverge, n8n wins for whatever's executing right now. Git wins for "what should be there."

## Three operations

Everything you do on the VPS is one of these three:

### A. First-time import (new workflow → n8n)

When the JSON file is brand new in the repo and the corresponding workflow does NOT exist in n8n yet.

```bash
ssh vps "cd ~/crystallux-deploy && git pull && \
  docker exec n8n n8n import:workflow --input=/data/workflows/api/<group>/<file>.json"
```

Then activate in the n8n UI. `import:workflow` defaults to `active: false`.

**Failure mode:** if the workflow already exists in n8n with the same internal ID, this fails with `SQLITE_CONSTRAINT: workflow_entity.id`. That means it's not a first-time import — go to operation B.

### B. Update an existing workflow (newer JSON → existing n8n row)

When a JSON file in the repo has been changed and you want the live n8n to reflect it. **Do NOT use `import:workflow` for this.**

Two correct paths:

**B1 (recommended for occasional updates) — UI Import-from-File**

1. Open the workflow in the n8n UI by name.
2. **⋮ menu (top right) → "Import from File"** → pick the JSON in the repo.
3. n8n shows a "Replace existing workflow?" prompt. Confirm.
4. Save (Ctrl+S). Re-activate the toggle if it was on.

Takes about 30 seconds per workflow. No API keys involved. Idempotent.

**B2 (for bulk updates) — REST API PATCH**

Requires an n8n personal API key (Settings → API → Create personal access token).

```bash
export N8N_API_KEY="…"
export N8N_BASE="https://automation.crystallux.org"

# Look up the n8n-internal workflow ID by name
WID=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE/api/v1/workflows" \
      | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin)['data'] if w['name']=='CLX - MGA Insurance Advisor Leads v1'))")

# PATCH the workflow with the JSON body
curl -X PATCH -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
     "$N8N_BASE/api/v1/workflows/$WID" \
     --data-binary @workflows/api/insurance-mga/clx-mga-insurance-advisor-leads-v1.json
```

The JSON's top-level `"id"` field is the file's slug — NOT the n8n-internal ID needed for the URL. Always look up the ID by name.

### C. Delete a workflow (remove from n8n entirely)

```bash
docker exec n8n n8n delete:workflow --id=<n8n-internal-id>
```

Use `scripts/n8n/cleanup-duplicates.sh` instead of the bare command — it backs up first, refuses to delete active workflows, and logs everything.

## Avoiding duplicates in the first place

Duplicates happen when:

1. **Same workflow imported twice via CLI** — n8n derives the row's `id` from the JSON's `"id"` field. If the same JSON is imported twice without the file's `id` changing, the second import fails with `SQLITE_CONSTRAINT`. But if you regenerated the JSON (different `id`) before re-importing, n8n inserts a new row with the same `name` — that's the duplicate.
2. **Manual copy in n8n UI** — "Duplicate workflow" in the n8n UI creates a copy with `(Copy)` in the name, easy to spot. Less easy to spot is "Save As" with the same name.
3. **Importing while an old version is still in the trash** — n8n's trash is real rows in `workflow_entity` with a soft-delete flag.

Rules to prevent:

- **Always do operation B for an updated JSON, not operation A.** Operation A is only for brand-new workflows.
- **Keep the JSON's `"id"` field stable across edits.** Don't regenerate IDs when editing a JSON in the repo — that's what makes n8n treat it as a different workflow.
- **Before importing, check for an existing copy:**
  ```bash
  docker exec n8n n8n list:workflow | grep "CLX - MGA Insurance Advisor Leads"
  ```
  If anything comes back, go to operation B (update), not A (import).

## Recovering from `SQLITE_CONSTRAINT: workflow_entity.id`

You ran `import:workflow` and got the constraint error. Steps:

1. **Don't panic and don't delete the existing.** The old workflow is still serving traffic (or is dormant but valid).
2. **Look up the existing copy:**
   ```bash
   docker exec n8n n8n list:workflow | grep "<workflow-name>"
   ```
3. **Update via operation B** — UI Import from File OR REST API PATCH. The existing row's content gets replaced with the JSON; its ID, activations, and execution history are preserved.

## Auditing the current state

```bash
# Full list (id|name format)
docker exec n8n n8n list:workflow

# Filter for active only
docker exec n8n n8n list:workflow --active=true

# Find duplicate names + back up each + write a report
bash scripts/n8n/audit-duplicates.sh
```

The audit script is read-only. It exports every duplicate's JSON to a backup dir and writes a markdown report — see [`docs/audit/DUPLICATE_CLEANUP_PLAN.md`](../audit/DUPLICATE_CLEANUP_PLAN.md) for the worksheet.

## Restoring a deleted workflow

Every deletion via `cleanup-duplicates.sh` writes a backup JSON to a timestamped directory in `/tmp/n8n-cleanup-<ts>/`. To restore:

```bash
docker cp /tmp/n8n-cleanup-<ts>/<id>.json n8n:/tmp/restore.json
docker exec n8n n8n import:workflow --input=/tmp/restore.json
```

The restored workflow keeps its original ID. It comes back `active: false`; re-activate in the UI.

## Quick reference

| You want to … | Run |
|---|---|
| Add a brand-new workflow | `n8n import:workflow --input=<file>` |
| Update an existing workflow (UI) | UI → ⋮ → Import from File |
| Update an existing workflow (script) | REST API `PATCH /api/v1/workflows/<id>` |
| Find duplicate names | `bash scripts/n8n/audit-duplicates.sh` |
| Delete duplicates safely | `bash scripts/n8n/cleanup-duplicates.sh --delete-list=<file>` |
| Check what's active | `docker exec n8n n8n list:workflow --active=true` |
| Get a backup before changing anything | `docker exec n8n n8n export:workflow --id=<id> --output=/tmp/wf-<id>.json` |
| Restore from a backup JSON | `n8n import:workflow --input=<backup>.json` |
