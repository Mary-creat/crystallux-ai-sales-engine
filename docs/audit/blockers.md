# Audit blockers — actions needed from Mary before re-audit

These are items I (Claude) cannot complete autonomously because they
require either Supabase access, VPS access, or Cloudflare cache control.
Apply each, then re-run `tests/audit/dashboard-audit.js all` to verify.

---

## 0s. Emergency recovery left 36/69 endpoints still 404 — orphan webhook_entity + missing final restart (added 2026-05-20)

After the first `emergency-recover-webhooks.sh` run cleaned 80 duplicate rows + activated 69 canonical workflows, Mary's probe showed **33 endpoints HEALTHY, 36 still NOT-FOUND**. Two latent bugs:

1. **Orphan `webhook_entity` rows** — webhook_entity rows pointing at workflowIds that no longer exist in workflow_entity (from prior partial deletes, failed activations, or UI Import-Replace operations that didn't fully cascade). They occupy webhook paths without a backing workflow. New activations targeting those same paths silently fail the unique-constraint INSERT into webhook_entity.

2. **CLI `update:workflow --active=true` is unreliable for in-process webhook registration.** It sets the flag in the DB and returns exit 0, but the running n8n process doesn't always re-register the webhook in its in-memory map. n8n's boot-time registration (from workflow_entity rows with active=true) IS reliable. So a restart AFTER all activations is the deterministic fix.

**Patch (this commit):**

The sidecar SQL phase now ALWAYS runs an orphan-cleanup statement regardless of whether there are planned deletes:

```sql
DELETE FROM webhook_entity
WHERE workflowId NOT IN (SELECT id FROM workflow_entity);
```

And the script gained Phase 5/6 — a final `docker restart n8n` after all activations, so n8n boots fresh with every active workflow's webhook registered cleanly.

The sidecar phase also prints diagnostic counts (orphans cleaned, webhook_entity total, workflow_entity total) so the operator can see the actual DB state post-cleanup, not just trust the script's claims.

**Mary re-runs:**

```bash
bash scripts/n8n/emergency-recover-webhooks.sh
```

Same command as before. Expected result: the 36 previously-404 endpoints should flip HEALTHY because:
- their workflow's active=true was set
- webhook_entity is clean (no orphan blocking the path)
- final restart registered the webhooks on boot from clean state

---

## 0r. Emergency recovery via Alpine sidecar (added 2026-05-19, supersedes 0q's recovery steps)

When `apply-workflow-patch.sh` ran with `Delete via : none`, the dedupe pass had already deactivated old workflow rows but their `webhook_entity` entries remained — blocking new workflow activations from registering. Mary ended up with **18 of 22 endpoints returning HTTP 404** even though the import phase claimed success for every file.

The clean fix (`0q`) is to generate an n8n API key in the UI. That requires Mary to be able to navigate Settings → API → Create API Key, copy it, and `export N8N_API_KEY=`. **If for any reason that's not viable** (n8n version too old to surface the API page, time pressure, lost session, etc.), this script bypasses every prerequisite:

```bash
# Single command. Restarts n8n briefly (~10-20s downtime) and recovers state.
bash scripts/n8n/emergency-recover-webhooks.sh
```

What it does, without ANY container modification or env setup:

1. `git pull` (unless `--no-pull`).
2. Indexes every workflow JSON in the requested folders (defaults to the 9 affected: admin, carriers, sentinel, training, briefing, completeness, supervisor, reports, content).
3. Lists live workflows via `docker exec n8n n8n list:workflow`.
4. Plans which live IDs are duplicates of repo workflow names (and not the canonical id).
5. Locates the n8n data volume via `docker inspect`.
6. **`docker stop n8n`** briefly.
7. **`docker run --rm -v <volume>:/data alpine:3.18 sh -c 'apk add --no-cache sqlite && sqlite3 /data/database.sqlite ...'`** — installs sqlite3 inside a one-shot Alpine sidecar with the n8n volume mounted, then SQL-deletes the conflicting `workflow_entity` + `webhook_entity` + `execution_entity` rows. The n8n container itself is unmodified.
8. `docker start n8n`, polls until ready.
9. Imports any canonical workflows that don't yet exist on live.
10. Activates every canonical id whose folder was passed in.
11. Probes each webhook with a junk Bearer token; reports HEALTHY / NOT-FOUND / EMPTY-200 / N8N-500 with counts.

Targeted use (one folder only):

```bash
bash scripts/n8n/emergency-recover-webhooks.sh workflows/api/admin/
```

Cleanup-only (no activation):

```bash
# Pass --dry-run first to preview what would change:
python3 scripts/n8n/emergency-recover-webhooks.py --dry-run
# Then run for real (no folder args = cleanup all duplicates, activate nothing):
python3 scripts/n8n/emergency-recover-webhooks.py
```

Why an Alpine sidecar works when `docker exec n8n apk add sqlite` doesn't:

The official n8n image runs as user `node` with no apk write access. `docker exec -u root n8n apk add` MIGHT work on some images but the n8n process holds an exclusive SQLite write-lock while running — even with sqlite3 installed in-container, the SQL DELETE would race with the live process. The sidecar approach sidesteps both problems: a separate container with its own root + a stopped n8n that's not holding the lock.

---

## 0q. webhook_entity rows from deactivated workflows block new webhook registration → NOT-FOUND / EMPTY-200 across the board (added 2026-05-19)

**Hit immediately after `0p` fix shipped.** Mary's `apply-workflow-patch.sh` re-runs on the 7 broken folders + the admin folder ALL imported successfully but every probed webhook returned NOT-FOUND or EMPTY-200. Including the new `/admin/comms-log` for the CIRO viewer.

**Diagnosis: TWO problems combined into one symptom.**

1. **`webhook_entity` has a UNIQUE constraint on (webhook_path, http_method).** Deactivating a workflow does NOT remove its `webhook_entity` row — only proper DELETE via REST API / sqlite3 / `n8n delete:workflow` does. With `Delete via : none` (no API key, no sqlite3, no CLI delete in this n8n version), the old rows stuck around. When the script then activated a new workflow with the SAME webhook path, the INSERT into webhook_entity failed silently → the new webhook never registered → routing falls through to the old row pointing at a deactivated workflow → EMPTY-200 (workflow halts on entry) or NOT-FOUND (if even the stale row got cleaned eventually).

2. **The script's `--activate=auto` default was too conservative.** It only re-activated workflows whose prior copies were active. The dedupe pass left every duplicate inactive. New workflows (no prior version) also stayed inactive. So even setting aside problem #1, every newly-imported workflow stayed inactive → NOT-FOUND on probe.

**Fixes (this commit):**

- New `--activate` flag with three modes:
  - `auto` (still default): activate if prior was active OR no prior exists. This now also picks up brand-new workflows like `comms-log`.
  - `all`: force-activate every imported workflow regardless of prior state. Recommended for patch runs.
  - `none`: leave everything inactive.
- Header banner now prints a yellow `WARNING: no delete mechanism available` block whenever `Delete via : none` is detected — with the exact 3-step API key setup inline. No more silent acceptance of the broken path.
- End-of-run "Unhealthy probes" section now categorizes NOT-FOUND / EMPTY-200 / N8N-500 with specific remediation per status, AND prints the API-key-setup block again with a copy-paste re-run command.

**What Mary does to actually fix the live n8n:**

```
# 1. n8n UI → Settings → API → Create an API key. Copy.
echo 'export N8N_API_KEY="<paste>"' >> ~/.bashrc
source ~/.bashrc

# 2. Verify the script now sees the API
python3 scripts/n8n/apply-workflow-patch.py workflows/api/admin/ --dry-run
# Header should read: Delete via : api

# 3. Re-run on every affected folder with --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/admin/         --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/sentinel/      --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/training/      --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/briefing/      --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/completeness/  --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/supervisor/    --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/reports/       --no-pull --activate=all
bash scripts/n8n/apply-workflow-patch.sh workflows/api/content/       --no-pull --activate=all
```

This time the script will: properly DELETE the old conflicting `workflow_entity` + `webhook_entity` rows via REST API, then import + activate each workflow so its webhook actually registers. Probes should flip to HEALTHY.

`apk add sqlite` in the container does NOT work — the official n8n image runs as user `node`, no apk write access. API key is the cleanest path.

---

## 0p. apply-workflow-patch.sh: sqlite3 absent in stock n8n container → import was being skipped on every file (added 2026-05-19)

**What Mary hit:** Running `bash scripts/n8n/apply-workflow-patch.sh workflows/api/sentinel/` after the carriers folder worked manually. Every file in sentinel/training/briefing/completeness/supervisor/reports/content reported `delete-failed` and skipped import. Total: 35 workflows unpatched on the live n8n.

**Why:** The stock `n8nio/n8n` Docker image is Alpine-based and doesn't ship sqlite3. The original script (4e37f3c) used `docker exec n8n sqlite3 …` to delete duplicate rows, which silently failed, and the script treated that failure as a blocker.

But the SQL delete was only cleanup of already-deactivated duplicate rows — it wasn't a prerequisite for import. Deactivated old rows don't register webhooks, so they don't collide with the new import. Treating the delete failure as a hard blocker was a bug.

**Fix (this commit):** The script now:

1. Detects available delete mechanism on the first call:
   - n8n CLI `delete:workflow` (newer n8n versions)
   - REST API `DELETE /api/v1/workflows/:id` (if `N8N_API_KEY` env var set)
   - sqlite3 (if installed in the container)
   - none (gracefully degrade to deactivate-only)
2. Always deactivates same-name workflows (CLI-only, always works).
3. Tries to delete them via the detected method.
4. Proceeds with import even if delete fails. Old rows stay deactivated and harmless.
5. If a same-id row exists AND delete is unavailable AND import fails with collision: prints a clear hint that the file needs one UI Import-Replace.

Mary can now re-run all 7 broken folders:

```bash
bash scripts/n8n/apply-workflow-patch.sh workflows/api/sentinel/
bash scripts/n8n/apply-workflow-patch.sh workflows/api/training/  --no-pull
bash scripts/n8n/apply-workflow-patch.sh workflows/api/briefing/  --no-pull
bash scripts/n8n/apply-workflow-patch.sh workflows/api/completeness/ --no-pull
bash scripts/n8n/apply-workflow-patch.sh workflows/api/supervisor/ --no-pull
bash scripts/n8n/apply-workflow-patch.sh workflows/api/reports/   --no-pull
bash scripts/n8n/apply-workflow-patch.sh workflows/api/content/   --no-pull
```

**Optional but cleanest:** set up an n8n API key once so the script can hard-delete duplicates instead of leaving deactivated garbage. In n8n UI → Settings → API → Generate API Key, then on the VPS:

```bash
echo 'export N8N_API_KEY=n8n_api_…'   >> ~/.bashrc
echo 'export CLX_N8N_API_URL=http://localhost:5678/api/v1' >> ~/.bashrc
source ~/.bashrc
```

The script picks up `N8N_API_KEY` automatically and switches `Delete via : api` (visible in the header).

---

## 0o. Auto-unwrap bug in 23 admin-gated workflows → spurious "Session expired" 401s (added 2026-05-19)

**Root cause of Mary's "Carrier page: HTTP 401 Session expired" report after the dedupe pass.** Same trap that hit the avatar tranche (memory: `n8n-httprequest-autounwrap-trap`). httpRequest 4.2 auto-unwraps single-row PostgREST responses, so `$input.item.json` for a successful `validate_session(p_token)` is the row object `{user_id, email, user_role, client_id, expires_at}` — note **no `id` field**.

The broken pattern that landed in 23 workflows:

```js
const row = Array.isArray(rows) ? rows[0] : (rows && rows.id ? rows : null);
```

For a valid session: `rows = { user_id: '...', user_role: 'admin', ... }`, `rows.id` is undefined, so `row = null`, so returns 401 "Invalid session". Frontend renders any 401 as "Session expired. Please sign in again." across all three dashboards (`shared/api.js`).

**Fix:** mechanical text replacement to match the canonical MAXI / MGA carriers-list pattern:

```js
const row = Array.isArray(rows) ? rows[0] : (rows && (rows.user_id || rows.id) ? rows : null);
```

Scope: 23 files, 24 sites. All 5 carriers/ workflows, all 8 sentinel/ workflows, 3 training/, 2 briefing/, 2 completeness/, 1 supervisor/, 1 reports/, 1 content/. Mary needs to UI Import-Replace these 23 — most importantly:

- `workflows/api/carriers/clx-carriers-status-check-v1.json` (the page Mary reported)
- All 4 other `workflows/api/carriers/*` (same bug, same impact)

False positive (intentionally left alone): `workflows/clx-booking-v2.json` — that one's a leads-table query where `rows.id` IS correct (leads have an `id` column).

**Lesson:** the canonical row-check should always be `(rows.user_id || rows.id)` when reading validate_session output. Add to the lint script next time we touch CI.

---

## 0n. Workflow duplication on live n8n (added 2026-05-19)

**Root cause of the "404 webhook not registered" / random behavior / lead generation failure cluster Mary diagnosed on 2026-05-19.** Many workflow names had 2-6 duplicate rows on the live n8n. Two workflows with the same webhook path collide at registration — only one wins, the others 404. Which one wins is non-deterministic across n8n restarts, so the symptoms appear random.

**Why duplicates accumulated:**

1. `n8n import:workflow` is INSERT-only. There is no `update:workflow` import path on the CLI side; the only way to update an existing workflow is via the UI's "Replace existing" checkbox on Import from File.
2. **197 of 271 repo workflow JSONs lacked a top-level `id` field.** Without a fixed id, every import (CLI or UI without "Replace existing") creates a fresh row. We re-imported during cleanups and rebuilds; each pass added duplicates.

Mary's 2026-05-19 diagnostic listed 30 duplicate rows across 11 names — examples: `CLX - Lead Research` (4 v1 + 2 v2 copies), `CLX - Lead Scoring` (5 v1 + 2 v2 copies), `CLX - Admin List Leads v1` (3 copies), `CLX - MAXI Industries List v1` (3 copies, including `wfFix0001` + `clxMaxiIndustriesV1` + a random nano-id).

**Fix (this commit):**

- All 197 repo JSONs received a deterministic top-level `id` (camelCase derived from name, e.g. `clxAuthValidateSessionV1`). Script: `scripts/n8n/add-top-level-ids.py`. CI hook: `python3 scripts/n8n/add-top-level-ids.py --check` returns non-zero if any JSON is missing one.
- New dedupe tooling: `scripts/n8n/dedupe-workflows.py` (audit / deactivate / delete / verify phases) + `scripts/n8n/dedupe-all-workflows.sh` wrapper. Pre-computed plan for Mary's listed inventory: `docs/audit/WORKFLOW_DEDUPE_PLAN.md`.

**Action required from Mary on the VPS (after pulling this commit):**

```bash
# 1. Audit (read-only)
python3 scripts/n8n/dedupe-workflows.py --phase=audit

# 2. Full sequenced pass (prompts before destructive steps)
./scripts/n8n/dedupe-all-workflows.sh

# 3. UI Import-from-File the 11 canonical JSONs listed in WORKFLOW_DEDUPE_PLAN.md
#    (with "Replace existing" checked)

# 4. Verify all webhooks return 401 with a body (not empty-200, not 404)
python3 scripts/n8n/audit-webhook-endpoints.py > docs/audit/WEBHOOK_INVENTORY.md
```

**Prevention rules going forward:**

1. Every workflow JSON in `workflows/**/*.json` must have a top-level `"id"` field. CI check: `python3 scripts/n8n/add-top-level-ids.py --check`.
2. Always import via UI with "Replace existing" checked. Never use `docker exec n8n n8n import:workflow` to update an existing workflow — only to seed a fresh n8n.
3. Re-run `audit-webhook-endpoints.py` after every workflow change pass; flag any new `NOT-ACTIVE` row that wasn't there before.

---

## 0m. Validate Session httpRequest halts workflows on Supabase error → empty 200 (added 2026-05-19)

**Root cause of Mary's "no data" regression across admin pages.** When the
`Validate Session` httpRequest node in admin / MGA workflows hits a non-2xx
response from Supabase's `validate_session(p_token)` RPC, n8n's HTTP node
(default `options: {}`, no `neverError`) halts workflow execution. Webhook
node in `responseMode: responseNode` then falls back to **HTTP 200 with an
empty body** because no Respond node ever fires.

Reproducible with a junk Bearer token (which DOES reach Validate Session,
unlike the no-token case which produces an empty `token` field and Supabase
returns a clean empty array):

```bash
# Healthy expectation:
curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer junkjunkjunk" \
  https://automation.crystallux.org/webhook/admin/list-leads -d '{}'
# was returning:   HTTP 200, 0 bytes
# now (after fix): HTTP 401, {"ok":false,"error":"Invalid or expired session"}
```

Repo-wide impact (probed 2026-05-19): 9 admin endpoints + 45 MGA endpoints
returned empty 200 on junk token. Page JS sees `{ok: true, data: {}}` and
renders empty — no error visible to the user.

**Fix:** add `options.response.response.neverError: true` to every Validate
Session httpRequest node. Supabase's error response then flows as data into
the next Code node (Check Admin / Check Role / Check Session), which already
gracefully returns `{ok: false, status: 401, error: 'Invalid or expired
session'}` for any non-row input. IF branch fires Respond 4xx with proper
JSON body.

Both files patched as one mechanical sweep in this commit. Mary's apply
path: UI Import-from-File for each affected workflow she's actually using
(starting with `clx-admin-list-leads`, `clx-admin-system-health`,
`clx-admin-audit-log` — those drive the Overview / Sales Engine / Audit
log pages that showed empty after theme deploy).

**Why this surfaced now:** the bug pre-dates the theme change in `7fb51c0`.
Mary's symptom timing (admin pages empty after theme apply) was
coincidence — what changed was that the new dark theme made the *page
chrome* render before *data load*, so the empty-data state is now
visible-but-styled instead of hidden by a longer light-theme load. The
underlying workflows behaved identically before.

---

## 0l. Webhooks returning HTML 500 (added 2026-05-18, expanded 2026-05-19)

Mary's testing report flags pages that show "failed data" / "Network error" — the actual cause is n8n returning HTML 500 on specific webhooks **before** their workflows ever execute. Same failure pattern as 0h — the workflow JSON is fine, n8n's server is throwing.

| Webhook | Response | Affected page(s) |
|---|---|---|
| `POST /webhook/api/sentinel/cost/summary` | HTTP 500, HTML body | `/pages/sentinel.html` (Costs tab) |
| `POST /webhook/api/content/attribution-run` | HTTP 500, HTML body | `/pages/content-performance.html` (Attribution row) |
| `POST /webhook/api/training/topics` | HTTP 500, HTML body | `/pages/training-topics.html` |
| `POST /webhook/mga/insurance/advisor/overview` | HTTP 500, HTML body | `https://mga.crystallux.org/advisor/overview` (added 2026-05-19) |

Probed from outside (no auth header) on 2026-05-18 — all three return n8n's default `<!DOCTYPE html>...Internal Server Error` page. Other /api/* endpoints in the same set (`/api/carriers/status-check`, `/api/sentinel/health/summary`, validate-session, etc.) return clean 401 JSON, so the failure is per-workflow, not n8n-wide.

The new MAXI + avatar webhooks all return clean 401 JSON — they are NOT in this set. Mary's "Network error on MAXI" is a separate issue (most likely the schema migrations haven't been applied yet, so the workflow hits a missing `maxi_industries` table; once `psql -f db/migrations/avatars-platform-schema.sql` runs, MAXI data should flow).

**Diagnostic on the VPS:**

```bash
ssh vps "docker logs n8n --tail 300 | grep -A 8 -E \
  'api/sentinel/cost/summary|api/content/attribution-run|api/training/topics'"
```

Look for the stack trace immediately after the inbound webhook log. Most likely causes given the pattern (same workflow shape as the MGA 500s in 0h):

1. **Missing DB table or RPC** — the workflow references a Supabase table that was never migrated. Check `docs/architecture/migrations/` for a related schema file that may not have been applied.
2. **Credential not configured** — the workflow references a credential name n8n can't resolve (e.g. an Anthropic key that wasn't seeded into n8n's credentials store).
3. **n8n needs a restart** — sometimes credential changes / env-var changes don't take effect until the container is restarted. `docker restart n8n` is cheap to try.

**After fixing the root cause, re-probe to verify:**

```bash
for ep in api/sentinel/cost/summary api/content/attribution-run api/training/topics; do
  printf "%-35s " "$ep"
  curl -s -o /dev/null -w "%{http_code}\n" -X POST \
    -H "Content-Type: application/json" -H "Origin: https://admin.crystallux.org" \
    "https://automation.crystallux.org/webhook/$ep" -d '{}'
done
# Expect 401 (auth-gated, reachable) for each.
```

Once these flip from 500 to 401, the affected pages will show "Session expired" (if Mary needs to re-log) or actual data (if her session is valid).

**Side benefit shipped in 393de91:** `admin-dashboard/shared/api.js` now distinguishes HTML-500 (n8n internal error) from JSON-500 (workflow error) in the user-facing message. Future failures of this shape will tell the operator "check docker logs n8n" instead of a generic "Server error."

---

## 0k. Updating an existing n8n workflow ≠ `import:workflow` (added 2026-05-16)

**Operational gotcha discovered while applying the auth-fix commit `0699af8`.** `docker exec n8n n8n import:workflow --input=…` only INSERTS new workflows. If the workflow already exists in n8n's SQLite DB (same `id`), the command fails with `SQLITE_CONSTRAINT: workflow_entity.id`. There is no `update:workflow` CLI command in stable n8n.

**Use cases vs. correct path:**

| Situation | Right way |
|---|---|
| Brand-new workflow (never been imported here before) | `docker exec n8n n8n import:workflow --input=<file>` — works |
| Workflow already in n8n, you have a newer JSON to ship | **n8n UI** → open the workflow → ⋮ → **Import from File** → confirm replace → save → re-activate |
| Same as above but scripted | n8n REST API: `PATCH /rest/workflows/{id}` with the JSON body. Needs an n8n API key in the VPS, and a name→ID lookup (the JSON's `"id"` field is the file's slug, NOT n8n's internal workflow ID). |
| Bulk replacement of many workflows | Build `scripts/n8n-update-workflow.sh` as a one-time op tool — see notes at end of this section |

**For the 9 workflows in commit `0699af8`** (`carriers-list` + 8 advisor / quote / carrier siblings): all are `active: false`. Recommended ops path is **defer until the moment you activate each one**. When you open a workflow in the UI to flip its toggle, do the Import from File at the same time — 30 sec per workflow.

**For the 7 calculators in 0j below:** same — they're dormant, don't update them until the structural fix lands. When that commit ships, do UI import-replace on each.

**If/when bulk updates become a recurring need** (e.g. a code-mod across 50 workflows), the right tool is a shell script over the REST API:

```bash
# Sketch only — not committed yet
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
  https://automation.crystallux.org/api/v1/workflows \
  | jq -r '.data[] | select(.name == "CLX - MGA Insurance Carriers List v1") | .id'
# → use that id in:
curl -X PATCH -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" \
  https://automation.crystallux.org/api/v1/workflows/<id> \
  --data-binary @workflows/api/insurance-mga/clx-mga-insurance-carriers-list-v1.json
```

Build this only if the activation workload gets heavy enough to justify the tool. For one-off updates it's UI-faster.

**Do NOT use `n8n import:workflow --separate` to work around the constraint** — that flag is for splitting a multi-workflow file, it doesn't enable updates.

**Do NOT do direct SQLite UPDATEs** on `workflow_entity` unless you understand n8n's credential encryption (encrypted at rest with a key in `~/.n8n/config`; mismatching encryption keys leave credentials unreadable).

---

## 0j. 7 MGA calculator workflows have no auth error path (added 2026-05-16)

While fixing `carriers-list` to reject unauthenticated requests properly, a sweep of `workflows/api/insurance-mga/` found 16 workflows with the same "missing IF Bad early-return" bug. Nine are patched in this commit (`carriers-list` + 8 siblings — all use the same Webhook → Extract → Validate Session → Check (Role|Session) → IF OK → Respond OK/4xx skeleton, fix was mechanical). The 7 LLQP **calculator workflows are a different shape entirely** — they have NO error path at all:

```
Webhook → Extract → Validate Session → Calculate → Respond
```

No IF check, no Respond 4xx node. When called without a token, `Extract` produces `{_unauthorized:true, status:401}` but nothing acts on it — `Validate Session` is called regardless, errors out (or returns junk), and `Calculate` runs against malformed input. Depending on `responseMode`, the webhook returns HTTP 200 with calculator output (data leak) or HTTP 500.

Affected files:
- `clx-mga-insurance-calculator-business-key-person-v1.json`
- `clx-mga-insurance-calculator-dependent-support-v1.json`
- `clx-mga-insurance-calculator-education-v1.json`
- `clx-mga-insurance-calculator-final-expenses-v1.json`
- `clx-mga-insurance-calculator-income-replacement-v1.json`
- `clx-mga-insurance-calculator-mortgage-debt-v1.json`
- `clx-mga-insurance-calculator-total-needs-v1.json`

**Fix shape** (each needs 3 changes, not 2):
1. Insert an `IF Bad` node after Extract — same JSON as in the patched 9
2. Insert a new `Respond 4xx` node (none exists) — clone from `clx-mga-insurance-onboarding-status-v1.json`
3. Insert an `IF OK` between `Validate Session` and `Calculate` (currently the calculator runs even if validate-session returned `{ok:false}` — there's no check that the session is actually valid)
4. Rewire: `Extract → IF Bad`, IF Bad-true → Respond 4xx, IF Bad-false → Validate Session, Validate Session → IF OK, IF OK-true → Calculate, IF OK-false → Respond 4xx

This is roughly 30 minutes per workflow if scripted with the same pattern. Holding the fix because:
- Risk of getting the IF OK condition wrong (need to check the `validate_session` RPC response shape; calculator workflows don't have a Check Session node to copy from)
- These workflows are all dormant — no live exposure yet
- They should be fixed in one focused commit with explicit verification, not bundled with the mechanical 9-workflow sweep

**Verification once fix lands** (and after Mary re-imports each on the VPS):
```bash
for w in business-key-person dependent-support education final-expenses \
         income-replacement mortgage-debt total-needs; do
  printf "%-30s " "$w"
  curl -s -o /dev/null -w "%{http_code}\n" -X POST \
    -H "Content-Type: application/json" -H "Origin: https://mga.crystallux.org" \
    "https://automation.crystallux.org/webhook/mga/insurance/calculator-$w" -d '{}'
done
# Expect 401 for every line.
```

---

## 0i. Cloudflare CDN serving stale admin /shared/* cache (added 2026-05-16)

**The auth.js fix IS deployed to the Cloudflare Pages origin** — but the CDN edge cache is still serving the pre-fix file because `admin-dashboard/_headers` sets `Cache-Control: public, max-age=86400, must-revalidate` on `/shared/*`. The edge holds the old object for up to 24 hours before it will revalidate. `must-revalidate` only kicks in after expiry; it does not force re-check inside the TTL.

This is the real cause of Mary's "your fix didn't work" symptom. The previous routing fix (`1b983dc`) likely had the same cache issue.

**Proof (run from any terminal):**

```bash
# Cached (what users see) — pre-fix code:
curl -s https://admin.crystallux.org/shared/auth.js | grep -c "Role inventory"
# → 0  (stale)

# Cache-busted (origin, what Pages actually shipped):
curl -s "https://admin.crystallux.org/shared/auth.js?cb=$RANDOM" | grep -c "Role inventory"
# → 1  (the fix IS there)

# Headers confirm CDN hit:
curl -sI https://admin.crystallux.org/shared/auth.js | grep cf-cache-status
# → cf-cache-status: HIT
```

Client dashboard (`app.crystallux.org`) is already serving the fixed version — its cache rolled. Admin is the laggard.

**The 60-second fix — purge the Cloudflare cache for admin shared assets:**

1. Cloudflare dashboard → `crystallux.org` zone → **Caching** → **Configuration** → **Custom Purge**.
2. Choose **Purge by URL**. Enter:
   ```
   https://admin.crystallux.org/shared/auth.js
   https://admin.crystallux.org/shared/api.js
   https://admin.crystallux.org/shared/components.js
   https://admin.crystallux.org/shared/copilot.js
   https://admin.crystallux.org/shared/nav.html
   https://admin.crystallux.org/shared/layout.css
   ```
3. Click **Purge**. Next page load fetches fresh from origin.

Alternative if no Custom Purge access: **Purge Everything** for the zone (heavier but simpler).

**Verify** with `bash tests/audit/smoke-domains.sh deploy` — expect all three deploy-marker checks to pass.

**Optional follow-up:** consider lowering `/shared/*` max-age from 86400 to e.g. 300 in `admin-dashboard/_headers` and `client-dashboard/_headers`. 5-minute TTL with revalidation would give us fast deploys without sacrificing meaningful cache hit rate (these files are byte-versioned through deploy already; ETag-based revalidation is cheap). Not landing that in this commit — it's a policy change Mary should weigh.

---

## 0h. n8n returning HTTP 500 on MGA webhooks (added 2026-05-16)

`POST /webhook/mga/insurance/onboarding-status` and `POST /webhook/mga/insurance/carriers-list` both return **HTTP 500 with n8n's HTML "Internal Server Error" page** — not 404, not a workflow error envelope. `POST /webhook/auth/validate-session` returns a proper JSON 401 from the same host, so n8n itself is up; the failure is per-workflow.

This is why `mga.crystallux.org/advisor/onboarding` shows "Failed to fetch" and `mga.crystallux.org/principal/carriers` shows "data error" — the catch path in `clxApi.mgaPost` turns a network/500 into one of those strings.

**Most likely cause given that the workflow JSON exists, `active: false`, and validate-session works:** the workflow has never been imported into the n8n instance, OR was imported but the credentials/Postgres schema it depends on aren't seeded yet. Both MGA pages already hint at this in their own empty states ("Run POST /webhook/mga/insurance/onboarding-curriculum-seed", "Run POST /webhook/mga/insurance/carrier-seed").

**Diagnose on the VPS:**

```bash
ssh vps "docker logs n8n --tail 300 | grep -A 8 -E 'onboarding-status|carriers-list'"
```

If logs show "workflow not registered" → import + activate:

```bash
ssh vps "cd ~/crystallux-deploy && git pull && \
  for f in clx-mga-insurance-onboarding-status-v1.json \
           clx-mga-insurance-onboarding-curriculum-seed-v1.json \
           clx-mga-insurance-onboarding-advance-v1.json \
           clx-mga-insurance-onboarding-completion-v1.json \
           clx-mga-insurance-carriers-list-v1.json \
           clx-mga-insurance-carrier-seed-digital-friendly-v1.json; do \
    docker exec n8n n8n import:workflow --input=/data/workflows/api/insurance-mga/\$f; \
  done"
```

Then activate each in the n8n UI. After activating the `*-seed-*` workflows, **hit each seed webhook once** from a terminal (with `INTERNAL_EMAIL_SECRET`) to populate `onboarding_curriculum` and `mga_carriers` rows.

**Verify after activation:**

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -H "Origin: https://mga.crystallux.org" \
  https://automation.crystallux.org/webhook/mga/insurance/onboarding-status \
  -d '{}'
# Expect: 401 (no session token) — proves the webhook is registered and reaches the auth gate.
```

---

## 0g. Tier-1 workflow activation list (added 2026-05-16)

Per Mary's 2026-05-16 brief, the following workflows must be active for the platform's core flows. None will be auto-activated from this repo — per CLAUDE.md, activation is Mary's manual step on the n8n VPS. Listed here so the set survives context compaction.

| Workflow | Purpose | Status check |
|---|---|---|
| `clx-auth-validate-session-v1` | Session gate for every dashboard | ✓ confirmed active (returns 401 JSON) |
| `clx-auth-login-v1` | Magic-link login | Verify in n8n UI |
| `clx-mga-insurance-lead-capture-v1` | MGA marketing form submit | Required before `insurance.crystallux.org/contact.html` works |
| `clx-mga-insurance-advisor-onboarding-start-v1` | Advisor onboarding entry | Required for new advisor signups |
| `clx-mga-insurance-onboarding-status-v1` | Advisor onboarding read | See 0h above (currently 500-ing) |
| `clx-mga-insurance-onboarding-curriculum-seed-v1` | Seed 30-day curriculum (one-shot) | Hit once after activation |
| `clx-mga-insurance-onboarding-advance-v1` | Advance a curriculum day | Needs status workflow live first |
| `clx-mga-insurance-onboarding-completion-v1` | Day 30 sign-off | Needs status workflow live first |
| `clx-mga-insurance-carriers-list-v1` | MGA carrier roster read | See 0h above |
| `clx-mga-insurance-carrier-seed-digital-friendly-v1` | Seed 8 default carriers (one-shot) | Hit once after activation |
| `clx-admin-onboarding-pipeline-v1` | Admin onboarding board feed | Confirm exactly one active copy |
| `clx-carriers-status-check-v1` | Admin Carriers status (cron Mon 08:00) | See blockers entry 0f |
| `clx-carriers-update-v1` | Admin Carriers row update | See blockers entry 0f |
| Sentinel workflows (~21) | Health / cost / security / remediation | See blockers entry 0d |

**Duplicate cleanup** (mentioned in Mary's brief — also a manual VPS step):
- `CLX - Admin Onboarding Pipeline v1` — 3 copies reported; keep newest, delete the older two via the n8n UI (Workflows → Sort by updated → delete duplicates).
- `CLX - Advisor Onboarding Start` — 2 copies; keep newest.
- `CLX - Onboarding Completion` — 2 copies; keep newest.

I will not touch the workflow JSONs in this repo for these — the duplicates are server-side n8n state, not source files.

---

## 0f. Carrier ops console — activation steps (added 2026-05-15)

Carrier-management section at `admin.crystallux.org/pages/carriers/*` is BUILT but DORMANT. Activation steps:

1. **Apply the migration:**
   ```bash
   psql "$DATABASE_URL" -f db/migrations/carrier-management-schema.sql
   ```
   Idempotent. Creates 4 tables (`carriers`, `carrier_submissions`, `carrier_commissions`, `carrier_reconciliations`) and seeds 23 Canadian carriers under the Crystallux Financial Services tenant (20 in `not_applied`, 3 in `pending`: PolicyMe, Walnut, Apollo).

2. **Import + activate the 5 workflows on n8n VPS:**
   ```bash
   ssh vps "cd ~/crystallux-deploy && git pull && \
     for f in clx-carriers-status-check-v1.json \
              clx-carriers-update-v1.json \
              clx-carriers-submission-tracker-v1.json \
              clx-carriers-commission-calculator-v1.json \
              clx-carriers-reconciliation-v1.json; do \
       docker exec n8n n8n import:workflow --input=/data/workflows/api/carriers/\$f; \
     done"
   ```
   In the n8n UI, activate all 5. `clx-carriers-status-check-v1` runs as cron Mon 08:00 + on-demand webhook; the others are webhook-only and auto-activate on first call.

3. **Open** `admin.crystallux.org/pages/carriers/overview.html` — should show 23 carriers, "Active appointments: 0", "Pending: 3", "Not applied: 20".

4. **Tune carrier records** as appointments roll in: edit each carrier on the Appointments page to set agent code + expected_commission_pct when activation comes through.

Built but DORMANT per Mary's brief — activate only after first carrier approval. See `docs/architecture/CARRIER_MANAGEMENT.md` (architecture) and `docs/handbook/CARRIER_OPS_GUIDE.md` (Mary's playbook).

---

## 0e. MGA marketing site — Cloudflare SSL fix (BLOCKING — added 2026-05-14)

`insurance.crystallux.org` returns `ERR_TOO_MANY_REDIRECTS` because Cloudflare SSL/TLS mode is set to "Flexible" on the `crystallux.org` zone, while the Cloudflare Pages origin force-redirects HTTP→HTTPS. The combination is a loop.

**60-second fix (no code change):**

1. Cloudflare dashboard → select `crystallux.org` zone.
2. Left sidebar → **SSL/TLS** → **Overview**.
3. Change encryption mode from **Flexible** to **Full (strict)** (or **Full** if strict gives any cert-mismatch error).
4. Wait 60 seconds for propagation.
5. Clear cookies for `insurance.crystallux.org`, or test in an incognito window.

If the loop persists after the SSL flip, check Cloudflare → **Rules** → **Page Rules** and delete any "Always Use HTTPS" rule scoped to `insurance.crystallux.org/*` — Cloudflare Pages handles HTTPS natively and a redundant page-rule redirect can cause the loop.

Other MGA-marketing items (non-blocking but needed before public launch):

- **FSRA licence number** for Crystallux Inc. to fill into `about.html` Section 1 + `disclosure.html` Section 1 (currently "License # to be added on FSRA confirmation").
- **E&O carrier name + policy number** to fill into `disclosure.html` Section 5 (only the $2M minimum is currently stated).
- **Carrier appointment reconciliation** — remove any carrier name from the home carrier strip + product pages where Crystallux doesn't have an active appointment yet.
- **Calendly embed code** on `contact.html` (placeholder block currently in place).
- **Email aliases live:** `clients@crystallux.org`, `complaints@`, `privacy@`, `compliance@`, `career@`.
- **Lead-capture workflow import + activate** on n8n VPS:
  ```bash
  docker exec n8n n8n import:workflow \
    --input=/data/workflows/api/insurance-mga/clx-mga-insurance-lead-capture-v1.json
  ```
  Then activate in the n8n UI.

---

## 0d. Sentinel Phase 4 — Auto-remediation deploy (added 2026-05-13)

Phase 4 takes the alerts from Phases 1–3 and either auto-executes safe
remediations (pause workflow, resume workflow, block IP) or writes
pending approval rows for destructive actions (account lockout,
credential revocation) that Mary must approve from the dashboard.

1. **Apply the migration:**
   ```bash
   psql "$DATABASE_URL" -f db/migrations/sentinel-remediation-schema.sql
   ```
   Idempotent. Seeds 6 playbooks. Sets `sentinel_modules.status='active'`
   for `auto_remediation`.

2. **Re-import the 3 new remediation workflows + activate orchestrator:**
   ```bash
   ssh vps "cd ~/crystallux-deploy && git pull && \
     for f in clx-sentinel-remediation-orchestrator-v1.json \
              clx-sentinel-action-approve-v1.json \
              clx-sentinel-remediation-summary-v1.json; do \
       docker exec n8n n8n import:workflow --input=/data/workflows/api/sentinel/\$f; \
     done"
   ```
   In the n8n UI, activate **remediation-orchestrator** (cron */5 min).
   The 2 webhook-only workflows auto-activate on first call.

3. **(Optional) Wire `is_ip_blocked()` into new auth/webhook workflows.**
   At the top of any new validate-session step:
   ```
   SELECT is_ip_blocked('{{ $json.source_ip }}') AS blocked;
   ```
   If true, return 403. The 7 protected v2/v3 production workflows
   are NOT modified — Phase 4 is opt-in.

4. **Mark essential workflows explicitly.** Run once after the
   migration so `is_essential=true` rows exist for auth + billing
   webhook breakers:
   ```sql
   UPDATE sentinel_workflow_breakers
      SET is_essential = true
    WHERE workflow_name ILIKE 'CLX - Auth %'
       OR workflow_name ILIKE '%Stripe Webhook%';
   ```
   The orchestrator's URL filter (`&is_essential=eq.false`) guarantees
   these are never auto-paused even if a playbook somehow matches.

Verify by opening `admin.crystallux.org/pages/sentinel.html` →
Remediation tab. Playbooks render immediately. As alerts fire, the
orchestrator will populate the pending-approvals table and the
recent-actions history.

---

## 0c. Sentinel Phase 3 — Security monitoring deploy (added 2026-05-13)

Phase 3 detects brute-force, session anomalies, API abuse, privilege denials,
rate-limit breaches, and credential rotation overdue.

1. **Apply the migration:**
   ```bash
   psql "$DATABASE_URL" -f db/migrations/sentinel-security-schema.sql
   ```
   Idempotent. Seeds 15 credentials + 7 detection rules. Sets
   `sentinel_modules.status='active'` for `security_monitoring`.

2. **Re-import the 5 new security workflows + activate 2 crons:**
   ```bash
   ssh vps "cd ~/crystallux-deploy && git pull && \
     for f in clx-sentinel-security-event-log-v1.json \
              clx-sentinel-security-detector-v1.json \
              clx-sentinel-credential-age-check-v1.json \
              clx-sentinel-security-summary-v1.json \
              clx-sentinel-credential-rotate-record-v1.json; do \
       docker exec n8n n8n import:workflow --input=/data/workflows/api/sentinel/\$f; \
     done"
   ```
   In the n8n UI, activate **security-detector** (cron */10 min) and
   **credential-age-check** (cron 06:00 daily). The 3 webhook-only
   workflows auto-activate on first call.

3. **(Optional, later) Wire security-event-log into new workflows.**
   Phase 3 is value-additive — any new workflow that handles auth can
   POST to `/webhook/api/sentinel/security/event` with
   `{ master_token, event_type: 'session_rejected' | 'login_failed' |
   'webhook_auth_failed' | 'privilege_denied', user_email, source_ip,
   user_agent, details: {...} }` when it detects a security signal.
   The existing 7 protected v2/v3 production workflows are NOT
   modified — they keep current behavior.

4. **First-time credential rotation walkthrough.** After deploying,
   the credential inventory shows `last_rotated_at = NULL` for every
   row. Click "Mark rotated" on each credential to baseline. From
   then on, the daily check fires only when a credential actually
   approaches its `rotation_interval_days` from `last_rotated_at`.

Verify by opening `admin.crystallux.org/pages/sentinel.html` → Security
tab. Posture score + credential inventory render immediately.

---

## 0b. Sentinel Phase 2 — Health monitoring deploy (added 2026-05-13)

Phase 2 detects workflow silence, error-rate spikes, latency spikes, and
external-endpoint outages. Three pieces Mary must do:

1. **Apply the migration:**
   ```bash
   psql "$DATABASE_URL" -f db/migrations/sentinel-health-schema.sql
   # Or paste contents into Supabase SQL editor.
   ```
   Idempotent — re-runnable. Verifies by setting `sentinel_modules.status='active'` for `health_monitoring`.

2. **Set `N8N_API_KEY` env var** in the n8n container's `.env`. Generate from n8n UI → Settings → n8n API → "Create an API key". This is the key the workflow-health collector uses to call `/api/v1/executions`. Without it the collector returns 401 and no health rows get written.

3. **Re-import the 4 new health workflows + activate the 3 cron workflows:**
   ```bash
   ssh vps "cd ~/crystallux-deploy && git pull && \
     for f in clx-sentinel-health-workflow-collector-v1.json \
              clx-sentinel-health-endpoint-collector-v1.json \
              clx-sentinel-health-analyzer-v1.json \
              clx-sentinel-health-summary-v1.json; do \
       docker exec n8n n8n import:workflow --input=/data/workflows/api/sentinel/\$f; \
     done"
   ```
   Then in the n8n UI, activate the 2 collectors and the analyzer (3 total — summary is webhook-only, auto-activates on first call).

Verify by opening `admin.crystallux.org/pages/sentinel.html` → Health tab.
Within 10-15 min the first health rows + endpoint pings appear.

---

## 0. Sentinel live-dashboard re-import (added 2026-05-13)

Two new workflows + 5 rewritten vendor collectors + 1 updated summary
workflow need to be (re-)imported into n8n on the VPS.

```bash
ssh vps "cd ~/crystallux-deploy && git pull && \
  for f in clx-sentinel-cost-collector-twilio-v1.json \
           clx-sentinel-cost-collector-vapi-v1.json \
           clx-sentinel-cost-collector-heygen-v1.json \
           clx-sentinel-cost-collector-openai-v1.json \
           clx-sentinel-cost-collector-supabase-v1.json \
           clx-sentinel-cost-summary-v1.json \
           clx-sentinel-budget-update-v1.json; do \
    docker exec n8n n8n import:workflow --input=/data/workflows/api/sentinel/\$f; \
  done"
```

Then, in n8n UI, activate the 6 cost collectors (cron 06:00 daily).
The 2 new dashboard webhooks (cost-summary, budget-update) stay
DORMANT-default but are called only on demand from the dashboard —
n8n auto-activates a webhook-only workflow when its endpoint is hit.

Optional (for live OpenAI numbers, otherwise OpenAI shows $0 until
manually entered each month): set `OPENAI_ADMIN_API_KEY` in n8n's
env (`.env` for the n8n container — admin-scoped key, starts with
`sk-admin-`).

Verify by opening `admin.crystallux.org/pages/sentinel.html` → Costs
tab — should populate from live data within seconds.

---

## 1. Apply test-client SQL migration

**File:** `db/migrations/test-client-account.sql`

The audit harness needs `testclient@crystallux.org` to exist. Without
it, the entire client-side audit (7 pages + tenant isolation tests)
cannot run.

```bash
# Supabase SQL editor → paste the file's contents → Run
# OR via psql:
psql "$DATABASE_URL" -f db/migrations/test-client-account.sql
```

Verify by running the SELECT at the bottom of the migration — the
`password_verifies` column should return `true`.

---

## 2. Apply Calendly + notification-email migration

**File:** `db/migrations/update-calendly-info.sql`

Brand consolidation for Crystallux Insurance Network. Idempotent.

```sql
-- Run in Supabase SQL editor or:
psql "$DATABASE_URL" -f db/migrations/update-calendly-info.sql
```

---

## 3. Re-deploy client workflows on VPS

**Affected:** `clx-client-overview.json`, `clx-client-campaigns.json`

Commit `187430a` added Merge nodes to fix the parallel-branch bug for
these two workflows (same fix as commit `b5660d1` for the admin side).
Without re-importing them, the client overview will return
`total_leads: 0` even though the database has data.

```bash
# On the VPS:
cd /root/crystallux-workflows
git pull
# Copy the workflow JSONs:
cp -r api/* /root/crystallux-workflows/api/   # if not the same path
# Re-run the bulk-import script:
N8N_API_KEY=$(cat /tmp/.k) python3 /tmp/clx.py
```

---

## 4. Cloudflare Pages cache purge

After commits land, hard-purge if the dashboard HTML stays stale:

- Cloudflare dashboard → `crystallux.org` zone → Caching → Purge cache
- Pick "Custom purge" → host `admin.crystallux.org` and `app.crystallux.org`
- Purge

OR full purge of the project. Then hard-refresh in browser
(Ctrl+Shift+R).

---

## 5. Re-run audit after the above

```bash
cd tests/audit
node dashboard-audit.js all
```

Then read:
- `docs/audit/admin-audit-report.md`
- `docs/audit/client-audit-report.md`
- `docs/audit/audit-summary.md`
- `docs/audit/post-fix-report.md` (after I get to do a second pass on
  whatever the audit surfaces)

---

## 6. Activate the Admin Copilot ✦ (commit `29be2c4`)

The FAB is now wired on every admin page. Backend already exists
(4 dormant copilot workflows + `clx-mcp-tool-gateway`). To turn it on:

- Confirm `MARY_MASTER_TOKEN` is set in n8n env.
- Activate `clx-copilot-query-v1`, `clx-copilot-troubleshoot-v1`,
  `clx-copilot-platform-v1`, `clx-copilot-whisper-v1`, and
  `clx-mcp-tool-gateway` in the n8n UI.
- Bind the Anthropic API + OpenAI credentials to the Claude/Whisper
  HTTP nodes per OPERATIONS_HANDBOOK §22.4.
- After Cloudflare deploys, open admin → click ✦ → paste the master
  token once into the first-open prompt. Token caches in localStorage.

---

## 7. Build the Client Assistant workflow (commit pending)

The client-side ✦ FAB now ships on every client page (`commit
this-pass`). Until the backend workflows land, the FAB shows a
"not yet activated" message. To activate:

- Build `workflows/api/client/clx-client-copilot-ask.json` and
  `clx-client-copilot-transcribe.json` per the spec in
  [`docs/architecture/CLIENT_COPILOT_SPEC.md`](../architecture/CLIENT_COPILOT_SPEC.md).
- Both use **session-token auth** (Bearer header), not
  `MARY_MASTER_TOKEN`. Tenant scoping is enforced in the workflow's
  `Check Client` node — `client_id` comes from the validated session row,
  never from the request body.
- Re-import + activate per usual. Cloudflare cache purge if needed.

---

## 8. Apply Layer 1 core-engine migrations (Commit A)

Apply in order. All idempotent — safe to re-run.

```bash
psql "$DATABASE_URL" -f db/migrations/lead-distribution-schema.sql
psql "$DATABASE_URL" -f db/migrations/agent-goals-schema.sql
psql "$DATABASE_URL" -f db/migrations/missing-table-fixes.sql
```

- `lead-distribution-schema.sql` adds the F7 tables + 3 RPCs.
- `agent-goals-schema.sql` adds the F3 tables + 2 RPCs.
- `missing-table-fixes.sql` consolidates `closing_scripts`,
  `agent_calendar_prefs`, `daily_task_plan`, `agent_daily_summary` —
  these already exist in production (from
  `docs/architecture/migrations/`), so this file is a no-op there.
  Required only if a fresh Supabase project does not have the §29-§34
  tables.

**Verify RPCs exist after applying:**

```sql
SELECT proname FROM pg_proc
WHERE proname IN (
  'assign_lead_to_user','unassign_lead','distribute_pending_leads',
  'upsert_user_goal_progress','recompute_goal_progress',
  'upsert_daily_plan','match_script_to_state','get_scripts_for_lead',
  'calculate_daily_summary'
);
```

If any §29-§34 RPCs are missing (the last four), apply the matching
legacy migration from `docs/architecture/migrations/` listed at the
bottom of `db/migrations/missing-table-fixes.sql`.

---

## 9. Re-import Layer 1 workflows into n8n (Commit A)

12 new workflows under `workflows/api/distribution/` and
`workflows/api/goals/`:

```bash
# On VPS:
docker cp workflows/api/distribution n8n:/tmp/distribution
docker cp workflows/api/goals        n8n:/tmp/goals
docker exec n8n n8n import:workflow --separate --input=/tmp/distribution
docker exec n8n n8n import:workflow --separate --input=/tmp/goals
```

All ship `active: false`. After importing, decide which scheduled
ones to activate (see step 10).

---

## 10. Activate Layer 1 scheduled workflows (when ready)

Flip `active: true` in n8n UI on:

- `clx-performance-aggregator-v1`  (00:30 daily — recomputes goal progress)
- `clx-team-capacity-monitor-v1`   (00:15 daily — seeds today's capacity rows)
- `clx-performance-snapshot-v1`    (Sun 01:00 + 1st-of-month 01:00)
- `clx-goal-progress-notification-v1`  (Mon 09:00 — emails)

The webhook-only workflows (`clx-lead-distribute-v1`,
`clx-lead-reassign-v1`, `clx-lead-self-claim-v1`,
`clx-team-member-preferences-update-v1`, `clx-user-goals-assign-v1`,
`clx-user-goals-list-v1`, `clx-team-goals-list-v1`,
`clx-goal-template-create-v1`) can be activated as soon as the
migrations land — they're idle until the frontend (Commit B) calls them.

---

## 11. Seed initial goal templates + distribution rule per client

Once the migrations are applied and a client is ready to use F3/F7,
seed at least one template and one rule. Suggested defaults for
Crystallux Insurance Network (test client):

```sql
-- One default round-robin rule for distribution.
INSERT INTO lead_distribution_rules (client_id, rule_name, rule_type, priority, active)
VALUES ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'default-round-robin', 'round_robin', 100, true)
ON CONFLICT (client_id, rule_name) DO NOTHING;

-- Three example goal templates.
INSERT INTO goal_templates (client_id, template_name, metric, period, target_value, role)
VALUES
  ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'weekly-meetings',    'meetings_booked', 'weekly',  8,  'advisor'),
  ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'weekly-calls',       'calls_made',      'weekly',  40, 'advisor'),
  ('6edc687d-07b0-4478-bb4b-820dc4eebf5d', 'monthly-leads',      'leads_assigned',  'monthly', 40, 'advisor')
ON CONFLICT (client_id, template_name) DO NOTHING;
```

Per-user goal instantiation happens through the `goals/assign` webhook
once advisors are onboarded.

---

## 12. Apply Layer 2 carrier-integration migration (Commit B)

```bash
psql "$DATABASE_URL" -f db/migrations/carrier-integration-schema.sql
```

Adds `insurance_carriers`, `carrier_products`, `carrier_integrations`,
`carrier_quotes` — all tagged `vertical_id='insurance'`. Idempotent.

---

## 13. Re-import Layer 2 workflows (Commit B)

9 new workflows under `workflows/api/insurance-mga/`:

```bash
docker cp workflows/api/insurance-mga n8n:/tmp/insurance-mga-c
docker exec n8n n8n import:workflow --separate --input=/tmp/insurance-mga-c
```

All ship `active: false`. Activate after step 14.

---

## 14. Seed digital-friendly carriers (one-time)

```bash
curl -X POST https://automation.crystallux.org/webhook/mga/insurance/carrier-seed \
  -H "Content-Type: application/json" \
  -d '{"internal_secret":"<INTERNAL_EMAIL_SECRET>"}'
```

Expected response: `{"ok":true,"carriers_seeded":8,"products_seeded":~20}`.
See `docs/insurance-mga/DIGITAL_FRIENDLY_CARRIERS_GUIDE.md` for the roster.

---

## 15. Activate v2 policy recommendation (optional)

After carriers are seeded, flip `active: true` on
`clx-mga-insurance-policy-recommendation-engine-v2`. v1 stays `active: false`
as fallback. v2 returns 422 if no products exist for the requested product_type.

---

## 16. Deploy insurance-mga-dashboard frontend (Cloudflare)

11 new pages + 3 shared file edits (api.js, components-mga.js, nav.html).
Cloudflare Pages auto-deploys on push to `scale-sprint-v1`. After deploy:

- Hard-refresh `mga.crystallux.org` (Ctrl+Shift+R) to bust cache.
- Verify the new sidebar entries render for `info@crystallux.org`
  (mga_principal role).
- Smoke test each new page returns data or a clear empty state — DO NOT
  expect data on `route-map`, `coaching`, `team-productivity` until the
  upstream §29-§34 universal workflows are activated.

---

## 17. Apply Session 2 Layer 1 schemas

```bash
psql "$DATABASE_URL" -f db/migrations/pre-meeting-briefing-schema.sql
psql "$DATABASE_URL" -f db/migrations/training-coach-schema.sql
psql "$DATABASE_URL" -f db/migrations/file-completeness-schema.sql
```

All idempotent. Independent — order doesn't matter.

---

## 18. Re-import Session 2 Layer 1 workflows

32 new workflows under 7 new folders:

```bash
for folder in content archetype-seeds supervisor rebook briefing training completeness; do
  docker cp workflows/api/$folder n8n:/tmp/$folder
  docker exec n8n n8n import:workflow --separate --input=/tmp/$folder
done
```

All ship `active: false`.

---

## 19. Seed multi-vertical archetypes (optional, per vertical)

For each vertical Mary plans to onboard, POST with `MARY_MASTER_TOKEN`:

```bash
curl -X POST https://automation.crystallux.org/webhook/api/seed-archetypes-mortgage \
  -H "Content-Type: application/json" \
  -d '{"master_token":"<MARY_MASTER_TOKEN>"}'
```

Substitute `mortgage` with `real-estate`, `logistics`, `beauty`, `dental`,
or `consulting`. Idempotent — re-running is safe.

---

## 20. Apply for external platform APIs (Phase 4 — Mary's BD task)

Run in parallel — none block the schema/workflow deployment:

- LinkedIn Developer Account (Marketing API)
- Meta for Developers (Instagram + Facebook Graph API)
- YouTube Data API (Google Cloud Console)
- TikTok for Business (Marketing API)
- X Developer ($200/month tier required for posting)

Until approvals land, the 6 publisher workflows are stubs that respond
202 and write a `content_publications` row with `status='scheduled'`.

---

## 21. Activate Session 2 scheduled workflows (when ready)

Flip `active: true` on (in n8n UI):

- `clx-content-topic-generator-v1` (06:00 daily)
- `clx-content-engagement-poller-v1` (every 6h)
- `clx-content-attribution-loop-v1` (02:00 daily)
- `clx-content-comment-monitor-v1` (every 2h)
- `clx-pre-meeting-briefing-generator-v1` (every 30m)
- `clx-no-show-multi-attempt-v1` (09:00 daily)
- `clx-file-completeness-bulk-refresh-v1` (03:00 daily — stub heartbeat)

Webhook-only workflows can be activated as soon as imported.

---

## 22. Apply Session 2 Layer 2 schemas (insurance)

```bash
psql "$DATABASE_URL" -f db/migrations/insurance-content-library-schema.sql
psql "$DATABASE_URL" -f db/migrations/insurance-onboarding-curriculum-schema.sql
```

Both idempotent. Both tag `vertical_id='insurance'` on every column.

---

## 23. Re-import Session 2 Layer 2 workflows

12 new workflows under `workflows/api/insurance-mga/`:

```bash
docker cp workflows/api/insurance-mga n8n:/tmp/insurance-mga-s2
docker exec n8n n8n import:workflow --separate --input=/tmp/insurance-mga-s2
```

(Re-imports Session 1's insurance-mga workflows too — that's fine,
n8n updates existing workflows by name.) All ship `active: false`.

---

## 24. Seed Layer 2 content + training + onboarding

Run each once with `INTERNAL_EMAIL_SECRET`:

```bash
SECRET=<INTERNAL_EMAIL_SECRET>

curl -X POST https://automation.crystallux.org/webhook/mga/insurance/content-library-seed \
  -H "Content-Type: application/json" -d "{\"internal_secret\":\"$SECRET\"}"
# expect: { ok: true, vertical_id: 'insurance', templates_seeded: 20 }

curl -X POST https://automation.crystallux.org/webhook/mga/insurance/training-topics-seed \
  -H "Content-Type: application/json" -d "{\"internal_secret\":\"$SECRET\"}"
# expect: { ok: true, topics_seeded: 12 }

curl -X POST https://automation.crystallux.org/webhook/mga/insurance/onboarding-curriculum-seed \
  -H "Content-Type: application/json" -d "{\"internal_secret\":\"$SECRET\"}"
# expect: { ok: true, days_seeded: 30 }
```

All three idempotent — safe to re-run.

---

## 25. Smoke test calculators + onboarding

After deploying insurance-mga-dashboard (Cloudflare auto-deploys on push):

- Hard-refresh `mga.crystallux.org` (Ctrl+Shift+R).
- Log in as advisor / sub_agent / mga_principal.
- Sidebar should show **Calculators** + **Onboarding** under Advisor.
- Open Calculators → Income Replacement → annual_income_cents=7500000, years=15 → expect a coverage estimate ≈ $84-92M cents depending on inflation/return.
- Open Onboarding → expect Day 1 ("Welcome + license verification") to show **Start** button. Clicking advances to in_progress.

---

## 26. Apply Session 3 schemas (1 Layer 1 + 3 Layer 2)

```bash
# Layer 1 universal
psql "$DATABASE_URL" -f db/migrations/production-reports-schema.sql

# Layer 2 insurance
psql "$DATABASE_URL" -f db/migrations/insurer-access-schema.sql
psql "$DATABASE_URL" -f db/migrations/insurance-compliance-scores-schema.sql
psql "$DATABASE_URL" -f db/migrations/insurance-whitelabel-schema.sql
```

All idempotent. Order doesn't matter.

---

## 27. Re-import Session 3 workflows

```bash
# Layer 1 (3 workflows)
docker cp workflows/api/reports n8n:/tmp/reports
docker exec n8n n8n import:workflow --separate --input=/tmp/reports

# Layer 2 insurance (21 new workflows)
docker cp workflows/api/insurance-mga n8n:/tmp/insurance-mga-s3
docker exec n8n n8n import:workflow --separate --input=/tmp/insurance-mga-s3
```

All ship `active: false`.

---

## 28. Seed insurer report templates

```bash
curl -X POST https://automation.crystallux.org/webhook/mga/insurance/report-template-seed \
  -H "Content-Type: application/json" \
  -d "{\"internal_secret\":\"$INTERNAL_EMAIL_SECRET\"}"
# expect: { ok: true, vertical_id: 'insurance', templates_seeded: 6 }
```

---

## 29. Activate Session 3 scheduled workflows

Flip `active: true` on:
- `clx-production-report-schedule-v1` (02:00 daily, Layer 1)
- `clx-mga-insurance-compliance-score-calculate-v1` (04:00 daily, Layer 2)
- `clx-mga-insurance-compliance-alerts-v1` (every 4h, Layer 2)

Webhook-only workflows can be activated as soon as imported.

---

## 30. Deploy new Cloudflare Pages projects

- **insurer-dashboard/** → new Cloudflare Pages project → suggested domain `portal.crystallux.org`.
- **insurer-marketing/** → new Cloudflare Pages project → suggested domain `insurers.crystallux.org` (public, no auth).
- **insurance-mga-dashboard/** auto-deploys on push — hard-refresh to see 3 new principal entries (Insurer Accounts, Demo Mode, White-Label).

### End-to-end insurer smoke test

1. Sign in as `info@crystallux.org` at `mga.crystallux.org`.
2. **Principal → Insurer Accounts** → create test account against an existing `insurance_carriers.id`.
3. Invite an insurer user (will write an `auth_users` row with `user_role=insurer_user` + an `insurer_users` link).
4. Sign in as that insurer user at `portal.crystallux.org`.
5. Open **Compliance Scorecard** → confirms either real scores or a clear empty state.
6. Open **Monthly Production** → either real data or empty state.
7. In Supabase: `SELECT * FROM insurer_access_log ORDER BY created_at DESC LIMIT 10;` — every login + view_report should appear.
