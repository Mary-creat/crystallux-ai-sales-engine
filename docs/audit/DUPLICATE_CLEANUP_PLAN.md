# n8n duplicate-workflow cleanup — generic worksheet + recovery procedure

> **Role:** generic worksheet template + backup/restore procedure. The IDs listed below are from the 2026-05-16 MGA-focused snapshot and may be stale.
> **For the CURRENT pre-computed dedupe plan, see `WORKFLOW_DEDUPE_PLAN.md`** (2026-05-19, 30-duplicate listing, runs via `dedupe-all-workflows.sh`).
> **This doc is still useful for:**
> - The process flow diagram (Section "Process") if you want to understand the cleanup loop.
> - The "How to pick which to keep" heuristic (mirrored in the canonical plan, but documented in more detail here).
> - The **backup/restore procedure** ("What backups exist" section) — load-bearing if a wrong workflow gets deleted.
> - The **historical records table** at the bottom — fill in after each cleanup pass for audit trail.

This is the worksheet Mary fills in after running `scripts/n8n/audit-duplicates.sh`. Each section pre-lists the duplicate groups Mary identified in the 2026-05-16 brief. The empty `Keep` / `Delete` columns get filled from the audit report.

## Process

```
                    ┌──────────────────────────────┐
                    │ 1. Run audit-duplicates.sh   │  read-only; exports backups
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │ 2. Review the report +       │  open each JSON in the
                    │    diff the JSON exports     │  backup dir, pick winner
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │ 3. Fill in this worksheet    │  Keep / Delete per group
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │ 4. Write delete IDs to file  │  one per line
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │ 5. cleanup-duplicates.sh     │  dry-run first, then --execute
                    │    (refuses active=true)     │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │ 6. Smoke + per-webhook check │  verify nothing broken
                    └──────────────────────────────┘
```

## How to pick which to keep

In priority order — apply the first rule that decides:

1. **One row is active=true and serves the webhook.** Keep it. Delete the others.
2. **All rows are active=false** (the common case here — Crystallux dormant-by-default policy):
   - Open every JSON in the backup dir.
   - If exactly one has the correct content (e.g. matches the file in `workflows/api/insurance-mga/`), keep that.
   - If multiple look correct, keep the one with the latest `updatedAt`.
   - If multiple have webhook paths, n8n routes to the most-recently-activated one — but since none are active, the router doesn't care. Keep the one with the cleanest history.
3. **If unsure, delete nothing.** Defer that group until the source-of-truth question is settled.

## Worksheet — Mary fills the Keep / Delete cells

### Advisor-related duplicates

| Workflow name | IDs reported | Keep | Delete | Notes |
|---|---|---|---|---|
| CLX - MGA Insurance Advisor Applications v1 | `gKLUduzlNtlvxPVE`, `NnVWCkqaxVc4xp6d` | | | |
| CLX - MGA Insurance Advisor Commissions v1 | `dSoxeaOwQkfSE8tu`, `cZvFaBrnxR3iCyl8` | | | |
| CLX - MGA Insurance Advisor Leads v1 | `7tQjpvwsq5UAUmOX`, `UXgJRV1prHtQoZwM` | | | If keeping the one with the IF Bad fix (commit 0699af8), check both for a `IF Bad` node — that's the patched copy. |
| CLX - MGA Insurance Advisor Onboarding Start v1 | `ngPBEni4NBGZkavY`, `2e5Eep6CU3g3SJEr` | | | |
| CLX - MGA Insurance Advisor Overview v1 | `80pwgG5Ag42uYEIc`, `XGGrAFuorqVrhzyD` | | | |
| CLX - MGA Insurance Advisor Reviews v1 | `y9DUvmZTwuOQp3Lm`, `iDWIw2FiaS4WvBEr` | | | Same patched-vs-old check as Leads. |
| CLX - MGA Insurance Principal Advisors + Compliance v1 | `XE0YRusclmz8rfqE`, `avJzGlkv4WeGcS2Z` | | | |

### Carrier-related duplicates

| Workflow name | IDs reported | Keep | Delete | Notes |
|---|---|---|---|---|
| CLX - MGA Insurance Carrier Appointment Create v1 | `niXe08honWo6RyVg`, `50mN2UnzdS7ry8uE` | | | |

### Admin / onboarding duplicates

| Workflow name | IDs reported | Keep | Delete | Notes |
|---|---|---|---|---|
| CLX - Admin Onboarding Pipeline v1 | `mI0BrjuiI0Qtbryd`, `TYmCJvhLKNBt012A`, `UWrTXtY8N377hEcV` | | | 3 copies. The active one (if any) is feeding the admin overview pipeline view. |
| CLX - MGA Insurance Onboarding Completion v1 | `zDPjk6BSLV02MVZZ`, `jZkCGEGxxTOOiRGj` | | | |

### Discovered by audit (not in Mary's pre-list)

Any duplicate name the audit finds that's NOT in the tables above belongs here. Add rows as needed.

| Workflow name | IDs reported | Keep | Delete | Notes |
|---|---|---|---|---|
| _to be filled from audit_ | | | | |

## Execution

Once the worksheet is filled in:

```bash
# 1. Build the delete-ids file from the "Delete" columns above.
cat > /tmp/n8n-delete-ids.txt <<EOF
# Advisor duplicates (older copies)
<id-to-delete>
<id-to-delete>
…
EOF

# 2. Dry run — verify exactly the right workflows would be touched.
bash scripts/n8n/cleanup-duplicates.sh --delete-list=/tmp/n8n-delete-ids.txt
# Read the WOULD-DELETE lines + any REFUSED (active=true) ones.

# 3. Execute.
bash scripts/n8n/cleanup-duplicates.sh --delete-list=/tmp/n8n-delete-ids.txt --execute

# 4. Verify smoke is still passing.
bash tests/audit/smoke-domains.sh
```

## Post-cleanup verification checklist

After execution, verify each affected webhook still resolves to the kept workflow:

- [ ] `bash tests/audit/smoke-domains.sh n8n` — onboarding-status + carriers-list still 401.
- [ ] If `advisor-leads`, `advisor-reviews`, `advisor-overview`, `advisor-applications`, `advisor-commissions` workflows are now active in n8n (one each), probe them:
  ```bash
  for w in advisor-overview advisor-leads advisor-reviews advisor-applications advisor-commissions; do
    printf "%-25s " "$w"
    curl -s -o /dev/null -w "%{http_code}\n" -X POST \
      -H "Content-Type: application/json" -H "Origin: https://mga.crystallux.org" \
      "https://automation.crystallux.org/webhook/mga/insurance/$w" -d '{}'
  done
  # Expect 401 (auth-gated and reachable) for each.
  ```
- [ ] If admin-onboarding-pipeline is in use, open `admin.crystallux.org/pages/onboarding` and confirm the pipeline view still renders.
- [ ] Check the n8n UI executions log for any orphan executions referencing a deleted workflow ID (informational; should be empty for dormant workflows).

## What backups exist

- `audit-duplicates.sh` exports every duplicate's JSON to its `BACKUP_DIR` (defaults to `/tmp/n8n-audit-<ts>/`). This is the **complete pre-cleanup state** — restorable by `n8n import:workflow` against any of the saved files.
- `cleanup-duplicates.sh` re-exports each ID right before deletion to its own `BACKUP_DIR` (defaults to `/tmp/n8n-cleanup-<ts>/`). This is the **moment-of-deletion snapshot** — the most authoritative recovery point.

To restore a deleted workflow from backup:

```bash
docker cp /tmp/n8n-cleanup-<ts>/<deleted-id>.json n8n:/tmp/restore.json
docker exec n8n n8n import:workflow --input=/tmp/restore.json
```

The restored workflow keeps its original ID (the JSON's `id` field). It comes back `active: false`; re-activate in the UI if needed.

## Records (filled in after each cleanup pass)

| Date | Operator | # deleted | # refused | Backup path | Notes |
|---|---|---|---|---|---|
| _yyyy-mm-dd_ | Mary | | | `/tmp/n8n-cleanup-...` | |
