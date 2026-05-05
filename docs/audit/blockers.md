# Audit blockers — actions needed from Mary before re-audit

These are items I (Claude) cannot complete autonomously because they
require either Supabase access, VPS access, or Cloudflare cache control.
Apply each, then re-run `tests/audit/dashboard-audit.js all` to verify.

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
