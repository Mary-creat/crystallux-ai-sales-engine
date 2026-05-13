# Audit blockers — actions needed from Mary before re-audit

These are items I (Claude) cannot complete autonomously because they
require either Supabase access, VPS access, or Cloudflare cache control.
Apply each, then re-run `tests/audit/dashboard-audit.js all` to verify.

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
