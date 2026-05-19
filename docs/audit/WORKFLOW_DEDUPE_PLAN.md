# Workflow dedupe — runbook + pre-computed plan

**Status:** ready for Mary to execute on the n8n VPS.
**Generated:** 2026-05-19 from Mary's diagnostic listing of 30 duplicate IDs.

This document combines:
1. The runbook (how to use `scripts/n8n/dedupe-all-workflows.sh`).
2. A **pre-computed dedupe decision per known duplicate** so you can act before the live audit even runs.
3. The prevention rule that stops this from recurring.

If Mary's live n8n state matches the listing she pasted, sections 2 and 3 are all that's needed. Section 1 is the canonical procedure for any future audit-and-dedupe pass.

---

## 1. Runbook — automated procedure

On the VPS host that runs the n8n container, from the repo root:

```bash
git pull origin scale-sprint-v1
chmod +x scripts/n8n/dedupe-all-workflows.sh
./scripts/n8n/dedupe-all-workflows.sh
```

The wrapper sequences four phases and prompts for confirmation between destructive steps:

| Phase | What it does | Reversible? |
|---|---|---|
| 1. AUDIT | `n8n list:workflow` → group by name → pick canonical → write `/tmp/dedupe-plan-*.md` | Yes (read-only) |
| 2. DEACTIVATE | `n8n update:workflow --id=X --active=false` for every duplicate | Yes (re-activate via UI) |
| 3. DELETE | `sqlite3 DELETE FROM workflow_entity WHERE id IN (...)` | **No** — gated on `--confirm-destructive` and an interactive Y/N |
| 4. VERIFY | Re-list workflows, report any groups still duplicated | Read-only |

After phase 4, **UI Import-from-File** every canonical JSON the plan calls out, with the **"Replace existing"** checkbox ticked.

### Canonical-pick heuristic (in order)

1. Live workflow id matches the repo's top-level `id` for the same name.
2. Workflow id "looks named" (camelCase like `wfAdminListLeadsV1`, not a random nano-id like `cM8icq8U30HNvTgK`).
3. Workflow is `active=true`.
4. Falls through to the first listed entry.

---

## 2. Pre-computed plan for the inventory Mary pasted

Based on Mary's 2026-05-19 diagnostic. Each row says "keep this id, delete these ids." After phase 3 you'll re-import the canonical JSON from the repo (column 5).

| Name | Live copies | Keep (id) | Delete (ids) | Re-import from |
|---|---|---|---|---|
| `CLX - Lead Research` (v1) | 4 | (pick most-recent **active** v1) | the other 3 v1 ids | _no canonical v1 in repo — preserve one only if still in use_ |
| `CLX - Lead Research v2` | 2 | (pick **active** one) | the other v2 id | `workflows/clx-lead-research-v2.json` ¹ |
| `CLX - Lead Scoring` (v1) | 5 | (pick most-recent **active** v1) | the other 4 v1 ids | _no canonical v1 in repo — preserve one only if still in use_ |
| `CLX - Lead Scoring v2` | 2 | (pick **active** one) | the other v2 id | `workflows/clx-lead-scoring-v2.json` ¹ |
| `CLX-Lead import` | 2 | `ePbZMZxQrNkcu6SA` (matches repo) ² | the other id | `workflows/clx-lead-import.json` |
| `CLX - Admin List Leads v1` | 3 | _re-import to get `wfAdminListLeads`_ | `sJoZTZMEmmd7fjNU`, `SqkOmhUD1S07nmLs`, `tEqAF4OxVUTYIfNs` | `workflows/api/admin/clx-admin-list-leads.json` |
| `CLX - Admin List Clients v1` | 2 | _re-import to get `wfAdminListClients`_ | `L8jhBjjqpmvCvejo`, `0p5lOtUhsyEWw5ns` | `workflows/api/admin/clx-admin-list-clients.json` |
| `CLX - Client Leads v1` | 2 | _re-import to get named id_ ¹ | `SDmpkWV1vIVHqiq3`, `2rr4tGVT0K2ithXt` | `workflows/api/client/clx-client-leads.json` |
| `CLX - MGA Insurance Advisor Leads v1` | 2 | _re-import to get `wfMgaAdvisorLeadsV1`_ | `7tQjpvwsq5UAUmOX`, `UXgJRV1prHtQoZwM` | `workflows/api/insurance-mga/clx-mga-insurance-advisor-leads-v1.json` |
| `CLX - MAXI Industries List v1` | 3 | `clxMaxiIndustriesV1` (matches repo) | `wfFix0001`, `ij0OYsVjGgs54UXs` | `workflows/api/avatars/clx-maxi-industries-v1.json` |
| `CLX - Avatar List v1` | 2 | `clxAvatarListV1` (matches repo) | `wfFix0004` | `workflows/api/avatars/clx-avatar-list-v1.json` |

**Totals: 11 name groups, ~16 rows to delete after dedupe.**

Notes:
- ¹ Some repo JSONs still have non-canonical ids (`clx-lead-research-v2` is kebab-case; `clx-client-leads.json` has no top-level id at all). Run `python3 scripts/n8n/add-top-level-ids.py --apply` BEFORE the re-import so every JSON ships with a stable camelCase id (`clxLeadResearchV2`, `wfClientLeads`, etc.).
- ² `ePbZMZxQrNkcu6SA` is a random nano-id that already happens to match what the lead-import JSON has. If Mary's live row for it isn't the one matching the JSON, swap with `add-top-level-ids.py --apply` and re-import.

### Exact destructive command

After deactivation, the SQLite DELETE for the **known random ids only** (preserves whichever v1 / v2 / `lead import` row Mary picked):

```bash
docker exec -i n8n sqlite3 /home/node/.n8n/database.sqlite <<'SQL'
  -- Phase B (run after Mary picks one v1 + one v2 to keep for Lead Research / Scoring)
  DELETE FROM webhook_entity   WHERE workflowId IN (
    'sJoZTZMEmmd7fjNU','SqkOmhUD1S07nmLs','tEqAF4OxVUTYIfNs',
    'L8jhBjjqpmvCvejo','0p5lOtUhsyEWw5ns',
    'SDmpkWV1vIVHqiq3','2rr4tGVT0K2ithXt',
    '7tQjpvwsq5UAUmOX','UXgJRV1prHtQoZwM',
    'wfFix0001','ij0OYsVjGgs54UXs',
    'wfFix0004'
  );
  DELETE FROM execution_entity WHERE workflowId IN (
    'sJoZTZMEmmd7fjNU','SqkOmhUD1S07nmLs','tEqAF4OxVUTYIfNs',
    'L8jhBjjqpmvCvejo','0p5lOtUhsyEWw5ns',
    'SDmpkWV1vIVHqiq3','2rr4tGVT0K2ithXt',
    '7tQjpvwsq5UAUmOX','UXgJRV1prHtQoZwM',
    'wfFix0001','ij0OYsVjGgs54UXs',
    'wfFix0004'
  );
  DELETE FROM workflow_entity  WHERE id IN (
    'sJoZTZMEmmd7fjNU','SqkOmhUD1S07nmLs','tEqAF4OxVUTYIfNs',
    'L8jhBjjqpmvCvejo','0p5lOtUhsyEWw5ns',
    'SDmpkWV1vIVHqiq3','2rr4tGVT0K2ithXt',
    '7tQjpvwsq5UAUmOX','UXgJRV1prHtQoZwM',
    'wfFix0001','ij0OYsVjGgs54UXs',
    'wfFix0004'
  );
SQL

docker restart n8n
```

For Lead Research v1 (4 copies), Lead Research v2 (2 copies), Lead Scoring v1 (5 copies), Lead Scoring v2 (2 copies), `CLX-Lead import` (2 copies): the wrapper script's audit phase will tell Mary which is active and pick the canonical automatically.

---

## 3. Re-import canonical JSONs (after deletes)

In the n8n UI: **Workflows → Import from File** → tick **"Replace existing"** → select the file. Order matters less than completeness — do all 9:

1. `workflows/api/admin/clx-admin-list-leads.json` → id `wfAdminListLeads`
2. `workflows/api/admin/clx-admin-list-clients.json` → id `wfAdminListClients`
3. `workflows/api/client/clx-client-leads.json` → id _(set by add-top-level-ids)_
4. `workflows/api/insurance-mga/clx-mga-insurance-advisor-leads-v1.json` → id `wfMgaAdvisorLeadsV1`
5. `workflows/api/avatars/clx-maxi-industries-v1.json` → id `clxMaxiIndustriesV1`
6. `workflows/api/avatars/clx-avatar-list-v1.json` → id `clxAvatarListV1`
7. `workflows/clx-lead-import.json` → id `ePbZMZxQrNkcu6SA`
8. `workflows/clx-lead-research-v2.json` → id _(set by add-top-level-ids)_
9. `workflows/clx-lead-scoring-v2.json` → id _(set by add-top-level-ids)_

Each is currently in repo `active: false`. After import, activate via the UI toggle if it was active before, OR leave inactive if it wasn't on the original demo path.

### Verify

```bash
# Re-run the live audit. Rows should flip from EMPTY-200 / NOT-ACTIVE → HEALTHY.
python3 scripts/n8n/audit-webhook-endpoints.py > docs/audit/WEBHOOK_INVENTORY.md

# Spot-check specific webhooks
curl -X POST -H 'Authorization: Bearer junk' \
  https://automation.crystallux.org/webhook/admin/list-leads -d '{}'
# Expect: HTTP 401 with JSON body (not 200 with empty body, not 404).
```

---

## 4. Prevention — every JSON must have a top-level `id`

The recurrence vector for this whole mess is in `docs/audit/blockers.md` entry 0n. Short version:

- n8n's CLI `import:workflow` is INSERT-only.
- Without a top-level `id`, every import creates a new row.
- UI Import-from-File without **"Replace existing"** does the same.

Two enforcement rules going forward:

1. **Every workflow JSON in `workflows/**/*.json` has a top-level `"id"` field** — a stable camelCase string like `wfAdminListLeadsV1` or `clxMaxiIndustriesV1`. Run `python3 scripts/n8n/add-top-level-ids.py --check` in CI; fail the build if any JSON is missing one.
2. **Always import via UI with "Replace existing" checked**, not via `docker exec n8n import:workflow`. The CLI is fine for first-time seeding on a fresh n8n install; never use it to update an existing workflow.

This commit adds top-level ids to all 197 repo JSONs that were missing one. Going forward the dedupe should never need to run again.
