# Crystallux — Pre-Launch Audit (2026-05-01)

**Auditor:** infrastructure review pre-first-client onboarding
**Repo:** `Mary-creat/crystallux-ai-sales-engine` @ `scale-sprint-v1`
**Branch HEAD:** `bb6f41f` (Phase 3.5 docs) — newer than the brief's `e9f4a07`; the difference is doc-only
**Working tree:** clean, no uncommitted changes
**All commits pushed to origin:** yes

---

## Section 1 — Current State Summary (verified vs assumed)

### 1.1 Repository

| Item | Status | Notes |
|---|---|---|
| Branch on `scale-sprint-v1` | ✅ verified | `git status` clean, all commits in `origin/scale-sprint-v1` |
| `admin-dashboard/` (20 files) | ✅ verified | 10 pages + 5 shared + index + login-redirect + headers + redirects + README |
| `client-dashboard/` (17 files) | ✅ verified | 7 pages + 6 shared + index + headers + redirects + README |
| `workflows/api/auth/` (7 files) | ✅ verified | login, logout, validate-session, magic-link, magic-link-verify, password-reset-request, password-reset-complete |
| `workflows/api/admin/` (9 files) | ✅ verified | list-clients, client-detail, list-leads, system-health, billing-summary, workflow-status, onboarding-pipeline, market-intelligence, audit-log |
| `workflows/api/client/` (9 files) | ✅ verified | overview, leads, campaigns, bookings, replies, activity, performance, billing, settings |
| `dashboard/` (legacy MVP) | ✅ verified | Untouched per constraint; serves crystallux-dashboard.pages.dev |
| `site/` (marketing) | ✅ verified | Plus 5 new auth pages (login, magic-link-sent, magic-link-verify, forgot-password, reset-password) |
| `scripts/auth-bcrypt.js` | ✅ verified | Local hash generator |
| All 4 new migrations in repo | ✅ verified | 2026-04-28-authentication, 2026-04-30-admin-dashboard-columns, 2026-04-30-client-settings-columns, plus this report's 2026-05-01-audit-fixes |

### 1.2 Supabase (per Mary's brief — assumed, not directly verified)

| Item | Status | Trust |
|---|---|---|
| 18 prior migrations applied | 🟡 assumed | Per brief; not independently verified by this audit |
| `2026-04-28-authentication.sql` applied | 🟡 assumed | Per brief; verify with §2 SQL |
| `2026-04-30-admin-dashboard-columns.sql` applied | 🟡 assumed | Per brief; verify with §2 SQL |
| `2026-04-30-client-settings-columns.sql` applied | ❌ NOT applied | Brief's "Known Uncertainties" flags this directly |
| Mary admin user with real bcrypt hash | 🟡 assumed | Per brief; verify with §2 SQL |
| 4 auth tables exist | 🟡 assumed | Verify with §2 SQL |
| 5 auth RPCs exist | 🟡 assumed | Verify with §2 SQL |

### 1.3 Cloudflare / DNS (per Mary's brief — assumed)

| Item | Status |
|---|---|
| `crystallux` Pages project (marketing) live | 🟡 assumed |
| `crystallux-dashboard` Pages project (legacy MVP) live | 🟡 assumed |
| `crystallux-admin` Pages project | ❌ not yet created |
| `crystallux-app` Pages project | ❌ not yet created |
| DNS for `admin.crystallux.org` | ❌ not yet pointed |
| DNS for `app.crystallux.org` | ❌ not yet pointed |
| Failed Worker `crystallux-ai-sales-engine` | ⚠️ flagged for deletion |

### 1.4 n8n (per Mary's brief — assumed)

| Item | Status |
|---|---|
| `automation.crystallux.org` reachable | 🟡 assumed |
| `NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs` set | ❌ unconfirmed (brief flagged "error in n8n to fetch workflow" without specifying which) |
| `MARY_MASTER_TOKEN` env var present | ❌ unconfirmed |
| 50 existing workflows imported | ❌ unconfirmed |
| 25 new workflows imported | ❌ unconfirmed |
| `Supabase Crystallux` credential created | ❌ unconfirmed |
| Anthropic, OpenAI, Gmail credentials created | ❌ unconfirmed |

---

## Section 2 — Schema Gaps

This section is the most important part of the audit. **Four gaps were found** between what the new webhooks expect and what the migrations provide. All four cause webhook failures (4xx/empty data) once activated. A consolidated fix migration has been drafted at `docs/architecture/migrations/2026-05-01-audit-fixes.sql`.

### 2.1 Severity legend

- **P0 — Blocker.** Webhook returns an error or empty payload; dashboard panel breaks visibly.
- **P1 — Degraded.** Webhook works but UX is degraded (missing data, wrong field).
- **P2 — Cosmetic.** Functional, but a future cleanup target.

### 2.2 Findings

#### F-01 (P0) — `campaigns` table does not exist

- **Symptom:** `clx-client-campaigns.json` queries `/rest/v1/campaigns?…` returns 404 "relation does not exist".
- **Where:** `workflows/api/client/clx-client-campaigns.json` line ~58 ("Query Campaigns" node).
- **Why this happened:** the existing `add_campaign_columns.sql` migration adds columns *to the leads table*, not a standalone campaigns table. `2026-04-18-full-platform-foundation.sql` defines `carousel_campaigns`, which is a different concept.
- **Fix:** create the `campaigns` table. Done in `2026-05-01-audit-fixes.sql` §1 with shape `(id, client_id, name, channel, status, sent, replies, started_at, ended_at, notes, created_at, updated_at)` + service-role RLS + indexes.

#### F-02 (P0) — `appointment_log` missing `company`, `attendee_name`, `event_type`

- **Symptom:** `clx-client-bookings.json` returns 400 "column 'company' does not exist".
- **Where:** `workflows/api/client/clx-client-bookings.json` "Build Query" node selects `id,company,attendee_name,event_type,scheduled_start,scheduled_end,outcome,no_show_flag,created_at`.
- **Schema reality (`2026-04-24-calendar-restructuring.sql`):** the table has `id, client_id, lead_id, appointment_type, scheduled_start, scheduled_end, duration_minutes, meeting_url, source_channel, outcome, outcome_at, notes, created_at, updated_at` plus no-show fields. None of `company / attendee_name / event_type` exist.
- **Fix:** add the three columns as nullable text; backfill `event_type ← appointment_type`. Done in `2026-05-01-audit-fixes.sql` §2.
- **Follow-up (P1):** the calendar workflows that insert into `appointment_log` (`clx-booking-v2`, etc.) should populate `company` and `attendee_name` from the joined lead row going forward. Until they do, those columns will be NULL on new rows and the bookings panel will show `(no name)` placeholders.

#### F-03 (P0) — `admin_action_log` schema mismatch

- **Symptom:** `clx-admin-audit-log.json` returns 400 "column 'actor_email' does not exist".
- **Where:** `workflows/api/admin/clx-admin-audit-log.json` "Admin Actions" node selects `actor_email, action, target_type, target_id, occurred_at`.
- **Schema reality (`2026-04-24-admin-copilot.sql`):** the table has `id, admin_user, action_type, input_text, panel_context, generated_content, result_summary, success, error_message, created_at`. The Copilot writes to *that* schema, not the audit-log webhook's expected one.
- **Fix:** add the five missing columns and backfill from the existing rows so the audit panel returns useful history immediately. Done in `2026-05-01-audit-fixes.sql` §3. The two schemas now coexist in one table — Copilot keeps writing the original columns; audit-emitting webhooks (settings update, password reset) write the new columns.
- **Alternative considered but rejected:** rewriting the audit-log webhook to query the original Copilot columns. Rejected because Phase 4 needs a uniform audit shape across multiple emitters; one column set across all of them is simpler than one shape per emitter.

#### F-04 (P0) — `scan_log` table not defined in any migration

- **Symptom:** if the table doesn't exist on the live Supabase, both `clx-admin-system-health` (Errors 24h node) and `clx-admin-workflow-status` (Query Scan Log node) return 404.
- **Where:** `workflows/api/admin/clx-admin-system-health.json` + `workflows/api/admin/clx-admin-workflow-status.json` + the legacy `dashboard/index.html` panels.
- **Status:** **likely already exists** on the live database (the legacy MVP dashboard's "Scans Today" panel works in production), but no migration in this repo proves it. Auditor cannot verify without DB access.
- **Fix:** `2026-05-01-audit-fixes.sql` §4 has `CREATE TABLE IF NOT EXISTS scan_log` with the columns the workflows query (`workflow_name, status, scan_count, new_leads_found, duplicates_skipped, error_count, duration_ms, payload, scanned_at`). If the table already exists, this is a no-op. If not, it's created with the same shape Mary's existing dashboards already write to.
- **Verify-first SQL:** see §2.4 ("Mary verification queries"). If the verify shows the table exists, you can comment out §4 of the fix migration before applying.

#### F-05 (P0) — `daily_digest_opt_in` and `booking_alerts_opt_in` columns not applied

- **Symptom:** `clx-client-settings.json` write path returns 400 "column does not exist". Read path works (PostgREST tolerates SELECT of non-existent columns by returning NULLs only when using `select=*`; explicit column selects fail with 400).
- **Where:** `clients` table; required by settings webhook.
- **Status:** the migration **exists** in repo as `docs/architecture/migrations/2026-04-30-client-settings-columns.sql` but has NOT been applied to Supabase per the brief's Known Uncertainties.
- **Fix:** apply the existing migration. No new SQL needed.

### 2.3 Verified-correct columns / tables (no action needed)

| Reference | Source | Status |
|---|---|---|
| `auth_users`, `auth_sessions`, `auth_magic_links`, `auth_password_resets` | `2026-04-28-authentication.sql` | ✅ exists if migration applied |
| RPCs `validate_session`, `touch_session`, `revoke_session`, `register_failed_login`, `register_successful_login` | same | ✅ exists if migration applied |
| `clients.subscription_status / subscription_plan / next_billing_date / last_payment_amount / last_payment_at / trial_ends_at / stripe_customer_id` | `2026-04-23-stripe-billing.sql` | ✅ |
| `clients.intelligence_tier_enabled` | `2026-04-24-market-intelligence.sql` | ✅ |
| `clients.channels_enabled` | `2026-04-23-multi-channel.sql` | ✅ |
| `clients.video_enabled` | `2026-04-23-video-schema.sql` | ✅ |
| `clients.vertical` | `2026-04-24-verticals-batch-full.sql` | ✅ |
| `clients.notification_email / fee_per_booking / monthly_retainer / calendly_link / client_name / industry / city / active` | `add_clients_table.sql` | ✅ |
| `clients.onboarding_stage / onboarding_started_at / onboarding_next_action` | `2026-04-30-admin-dashboard-columns.sql` | ✅ if applied |
| `market_signals_processed`, `market_signals_raw` | `2026-04-24-market-intelligence.sql` | ✅ |
| `appointment_log` (base columns) | `2026-04-24-calendar-restructuring.sql` | ✅ (extended in F-02) |

### 2.4 Mary verification queries — run in Supabase SQL Editor

Run all of these. Each is read-only and returns a verdict row.

```sql
-- ══════════════════════════════════════════════════════════════════
-- Crystallux pre-launch audit verification queries
-- Read-only. Safe to run any time. Run as a single batch.
-- ══════════════════════════════════════════════════════════════════

-- 2.4.1  Auth tables exist with the expected columns
WITH expected AS (
  SELECT * FROM (VALUES
    ('auth_users','email'), ('auth_users','password_hash'), ('auth_users','user_role'),
    ('auth_users','client_id'), ('auth_users','failed_login_attempts'), ('auth_users','locked_until'),
    ('auth_sessions','session_token'), ('auth_sessions','expires_at'), ('auth_sessions','revoked_at'),
    ('auth_magic_links','token'), ('auth_magic_links','expires_at'), ('auth_magic_links','used_at'),
    ('auth_password_resets','token'), ('auth_password_resets','expires_at'), ('auth_password_resets','used_at')
  ) AS t(table_name, column_name)
)
SELECT '2.4.1 auth schema' AS check_name,
       e.table_name, e.column_name,
       CASE WHEN c.column_name IS NULL THEN '❌ MISSING' ELSE '✅' END AS status
FROM   expected e
LEFT   JOIN information_schema.columns c
       ON c.table_schema = 'public'
      AND c.table_name   = e.table_name
      AND c.column_name  = e.column_name
ORDER BY e.table_name, e.column_name;

-- 2.4.2  Auth RPCs exist with the right argument count
SELECT '2.4.2 auth rpcs' AS check_name,
       p.proname AS rpc_name,
       p.pronargs AS n_args,
       CASE
         WHEN p.proname = 'validate_session'        AND p.pronargs = 1 THEN '✅'
         WHEN p.proname = 'touch_session'           AND p.pronargs IN (1,2) THEN '✅'
         WHEN p.proname = 'revoke_session'          AND p.pronargs = 1 THEN '✅'
         WHEN p.proname = 'register_failed_login'   AND p.pronargs = 1 THEN '✅'
         WHEN p.proname = 'register_successful_login' AND p.pronargs = 1 THEN '✅'
         ELSE '❌ wrong arg count'
       END AS status
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('validate_session','touch_session','revoke_session','register_failed_login','register_successful_login')
ORDER BY p.proname;

-- 2.4.3  Mary admin row + bcrypt hash sanity
SELECT '2.4.3 mary admin' AS check_name,
       email,
       user_role,
       client_id IS NULL                AS client_id_is_null,
       length(password_hash) = 60       AS bcrypt_length_ok,
       password_hash LIKE '$2%'         AS bcrypt_prefix_ok,
       email_verified                   AS verified,
       failed_login_attempts            AS fails,
       locked_until > now()             AS currently_locked
FROM   auth_users
WHERE  email = 'info@crystallux.org';
-- Expect: 1 row, user_role='admin', client_id_is_null=true,
-- bcrypt_length_ok=true, bcrypt_prefix_ok=true, currently_locked is NULL/false

-- 2.4.4  clients onboarding columns (admin-dashboard-columns migration)
SELECT '2.4.4 onboarding cols' AS check_name, column_name,
       CASE WHEN column_name IS NOT NULL THEN '✅' ELSE '❌' END AS status
FROM   information_schema.columns
WHERE  table_schema='public' AND table_name='clients'
  AND  column_name IN ('onboarding_stage','onboarding_started_at','onboarding_next_action');
-- Expect: 3 rows.

-- 2.4.5  clients notification opt-in columns (client-settings migration)
SELECT '2.4.5 client settings cols' AS check_name, column_name,
       CASE WHEN column_name IS NOT NULL THEN '✅ applied' ELSE '❌ missing' END AS status
FROM   information_schema.columns
WHERE  table_schema='public' AND table_name='clients'
  AND  column_name IN ('daily_digest_opt_in','booking_alerts_opt_in');
-- Expect: 2 rows. If 0 rows, you have NOT yet applied
-- 2026-04-30-client-settings-columns.sql.

-- 2.4.6  Schema-gap tables — campaigns / scan_log
SELECT '2.4.6 missing tables' AS check_name, t.table_name,
       CASE WHEN c.relname IS NOT NULL THEN '✅ exists' ELSE '❌ MISSING' END AS status
FROM   (VALUES ('campaigns'), ('scan_log'), ('admin_action_log'), ('appointment_log')) AS t(table_name)
LEFT   JOIN pg_class c ON c.relname = t.table_name AND c.relkind = 'r'
LEFT   JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public';
-- Expect after audit-fixes migration: all 4 ✅. Right now,
-- campaigns is likely ❌; scan_log MAY be ✅ already.

-- 2.4.7  Schema-gap columns — appointment_log + admin_action_log new columns
SELECT '2.4.7 audit-fix columns' AS check_name, table_name, column_name,
       CASE WHEN column_name IS NOT NULL THEN '✅' ELSE '❌' END AS status
FROM   information_schema.columns
WHERE  table_schema='public'
  AND  ( (table_name='appointment_log'  AND column_name IN ('company','attendee_name','event_type'))
      OR (table_name='admin_action_log' AND column_name IN ('actor_email','action','target_type','target_id','occurred_at')) )
ORDER  BY table_name, column_name;
-- Expect after audit-fixes migration: 8 rows ✅.

-- 2.4.8  RLS posture on auth tables (must be enabled, service_role-only)
SELECT '2.4.8 auth rls' AS check_name, c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       (SELECT COUNT(*) FROM pg_policies WHERE schemaname='public' AND tablename = c.relname) AS policy_count,
       CASE WHEN c.relrowsecurity THEN '✅' ELSE '❌ RLS DISABLED' END AS status
FROM   pg_class c
JOIN   pg_namespace n ON n.oid = c.relnamespace
WHERE  n.nspname='public'
  AND  c.relname IN ('auth_users','auth_sessions','auth_magic_links','auth_password_resets');
-- Expect: 4 rows, rls_enabled=true on every one.

-- 2.4.9  Anon role has NO policies on auth tables (defence-in-depth)
SELECT '2.4.9 anon access' AS check_name, tablename,
       polroles_text,
       CASE WHEN polroles_text LIKE '%anon%' THEN '❌ ANON CAN READ' ELSE '✅' END AS status
FROM   (
  SELECT p.tablename,
         array_to_string(ARRAY(
           SELECT rolname FROM pg_roles r WHERE r.oid = ANY(p.polroles)
         ), ',') AS polroles_text
  FROM   pg_policies p
  JOIN   pg_class c ON c.relname = p.tablename
  WHERE  p.schemaname='public'
    AND  p.tablename IN ('auth_users','auth_sessions','auth_magic_links','auth_password_resets')
) x;
-- Expect: every row's polroles_text shows 'service_role' (NOT 'anon').
```

**Expected vs actual results template** (Mary fills this in):

```
2.4.1 auth schema           [ pass / fail ]   (15 rows expected, all ✅)
2.4.2 auth rpcs             [ pass / fail ]   (5 rows, all ✅)
2.4.3 mary admin            [ pass / fail ]   (1 row, all booleans true)
2.4.4 onboarding cols       [ pass / fail ]   (3 rows ✅)
2.4.5 client settings cols  [ pass / fail ]   (2 rows ✅, OR 0 → apply 2026-04-30-client-settings-columns.sql)
2.4.6 missing tables        [ pass / fail ]   (4 rows; campaigns likely ❌ pre-fix)
2.4.7 audit-fix columns     [ pass / fail ]   (8 rows; all ❌ pre-fix)
2.4.8 auth rls              [ pass / fail ]   (4 rows, rls_enabled=true)
2.4.9 anon access           [ pass / fail ]   (every row shows service_role only)
```

---

## Section 3 — Integration Issues (file paths + line numbers)

These are the exact webhook nodes whose queries must work after the §2 schema fixes are applied.

### 3.1 Auth webhook → DB references

| Webhook | DB target | Verified |
|---|---|---|
| `clx-auth-login.json` "Lookup User" | `auth_users` (email) | ✅ |
| `clx-auth-login.json` "Verify Password" | bcrypt via `bcryptjs` | ✅ if `NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs` set |
| `clx-auth-login.json` "Insert Session" | `auth_sessions` insert | ✅ |
| `clx-auth-login.json` "Mark Login Success" | `register_successful_login` RPC | ✅ |
| `clx-auth-login.json` "Mark Login Failed" | `register_failed_login` RPC | ✅ |
| `clx-auth-validate-session.json` | `validate_session` + `touch_session` RPCs | ✅ |
| `clx-auth-logout.json` | `revoke_session` RPC | ✅ |
| `clx-auth-magic-link.json` | `auth_magic_links` insert | ✅ |
| `clx-auth-magic-link-verify.json` | `auth_magic_links` lookup, `auth_users` lookup, `auth_sessions` insert, `register_successful_login` | ✅ |
| `clx-auth-password-reset-request.json` | `auth_users` lookup, `auth_password_resets` insert | ✅ |
| `clx-auth-password-reset-complete.json` | `auth_password_resets` lookup, `auth_users` PATCH (password_hash), `auth_password_resets` PATCH (used_at), `auth_sessions` PATCH (revoke all) | ✅ |

**Verdict:** all 7 auth webhooks are clean once `2026-04-28-authentication.sql` is applied AND `NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs` is set on n8n.

### 3.2 Admin webhook → DB references

| Webhook | DB target | Status |
|---|---|---|
| `clx-admin-list-clients.json` "Query Clients" | SELECT id, client_name, industry, city, active, subscription_status, subscription_plan, monthly_retainer, fee_per_booking, calendly_link, onboarding_stage FROM clients | ✅ all columns exist after admin-columns migration |
| `clx-admin-client-detail.json` (3 queries) | SELECT * FROM clients; SELECT … FROM leads; aggregate | ✅ |
| `clx-admin-list-leads.json` | SELECT … FROM leads with filters | ✅ assumed (leads table is baseline) |
| `clx-admin-system-health.json` | leads, clients, scan_log | ⚠️ depends on F-04 (scan_log) |
| `clx-admin-billing-summary.json` | clients with stripe columns | ✅ |
| `clx-admin-workflow-status.json` "Query Scan Log" | scan_log | ⚠️ F-04 |
| `clx-admin-onboarding-pipeline.json` | clients with onboarding_* | ✅ |
| `clx-admin-market-intelligence.json` | market_signals_processed/raw, clients.intelligence_tier_enabled | ✅ |
| `clx-admin-audit-log.json` "Admin Actions" node | admin_action_log selecting actor_email, action, target_type, target_id, occurred_at | ❌ **F-03** |

### 3.3 Client webhook → DB references (cross-tenant boundary)

Every client webhook extracts `client_id` from the session row in `validate_session`'s output. None of them reads `client_id` from the request body. This is the cross-tenant isolation anchor; verified by reading every Code node:

| Webhook | Session-derived `client_id`? | Schema |
|---|---|---|
| `clx-client-overview.json` "Check Client" | ✅ `row.client_id` from validate_session output | clients + leads ✅ |
| `clx-client-leads.json` "Build Query" | ✅ | leads ✅ |
| `clx-client-campaigns.json` "Check Client" | ✅ | ❌ **F-01** (campaigns table missing) |
| `clx-client-bookings.json` "Build Query" | ✅ | ⚠️ **F-02** (appointment_log missing 3 columns) |
| `clx-client-replies.json` "Build Query" | ✅ | leads ✅ |
| `clx-client-activity.json` "Build Query" | ✅ | leads ✅ |
| `clx-client-performance.json` "Check Client" | ✅ | leads ✅ |
| `clx-client-billing.json` "Check Client" | ✅ | clients ✅ |
| `clx-client-settings.json` "Check Client" | ✅ | ⚠️ **F-05** (opt-in columns missing) |

**Cross-tenant verdict:** **clean**. Every client webhook reads `client_id` only from the session row. The `clxApi.clientPost` browser helper additionally strips `client_id` from outgoing payloads as defence-in-depth.

### 3.4 Frontend → API path verification

Every dashboard page sends requests in this exact shape, verified by reading:

```js
// admin-dashboard/shared/api.js  (and equivalent for client)
fetch(BASE + '/admin/<resource>', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json',
             'Authorization': 'Bearer ' + localStorage.clx_session_token },
  body: JSON.stringify({ filters: {...} })
})
```

This matches the webhook contract. No mismatch found.

---

## Section 4 — Deployment Checklist

Group A = Mary's actions in browser (Cloudflare, DNS, n8n UI). Group B = SQL Mary runs in Supabase. Group C = Mary's actions on n8n VPS shell. Group D = Code actions (already done; included for completeness).

> **Apply order matters.** Each item depends on prior items. Don't skip ahead.

### Group D — Already done by Code (no Mary action)

| # | Item | Status |
|---|---|---|
| D-01 | All 25 new webhook JSONs in repo | ✅ |
| D-02 | All 4 new migrations in repo | ✅ |
| D-03 | Two new dashboard folders in repo | ✅ |
| D-04 | Auth pages on marketing site | ✅ |
| D-05 | Phase 1/2/3 commits pushed to `scale-sprint-v1` | ✅ |
| D-06 | Audit-fixes migration `2026-05-01-audit-fixes.sql` drafted | ✅ (this audit) |

### Group B — Supabase SQL (~15 min)

Run in Supabase SQL Editor in this order:

| # | Action | File | Time |
|---|---|---|---|
| B-01 | Run §2.4 verification queries | _inline above_ | 3 min |
| B-02 | Apply `2026-04-30-client-settings-columns.sql` (if §2.4.5 returned 0 rows) | `docs/architecture/migrations/2026-04-30-client-settings-columns.sql` | 1 min |
| B-03 | Apply `2026-05-01-audit-fixes.sql` | `docs/architecture/migrations/2026-05-01-audit-fixes.sql` | 2 min |
| B-04 | Re-run §2.4 to confirm all checks pass | _inline above_ | 3 min |
| B-05 | Optional: create a test client account for §3.7.1 of test plan | (one-off insert; see N8N_IMPORT_GUIDE §7.3) | 5 min |

### Group C — n8n VPS shell (~60 min)

| # | Action | Command | Time |
|---|---|---|---|
| C-01 | Verify n8n reachable | `curl -I https://automation.crystallux.org/healthz` | 1 min |
| C-02 | Edit systemd unit, set `NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs,crypto` | `sudo systemctl edit n8n` (see `docs/deployment/N8N_IMPORT_GUIDE.md` §2 for the full block) | 5 min |
| C-03 | Restart n8n, watch logs | `sudo systemctl daemon-reload && sudo systemctl restart n8n && journalctl -u n8n -n 50 --no-pager` | 2 min |
| C-04 | Verify bcryptjs loadable (one-off Code node test) | per N8N_IMPORT_GUIDE.md §2 final block | 3 min |
| C-05 | Set `MARY_MASTER_TOKEN` env var (for legacy break-glass admin) | add `Environment="MARY_MASTER_TOKEN=<token>"` to systemd unit OR docker-compose env | 2 min |

### Group A — Cloudflare + DNS + n8n UI (~3-4 hours)

| # | Action | Where | Time |
|---|---|---|---|
| A-01 | Delete failed Worker `crystallux-ai-sales-engine` | Cloudflare → Workers & Pages → ⋯ → Delete | 2 min |
| A-02 | Create Pages project `crystallux-admin` | Cloudflare → Workers & Pages → Create → Pages → Connect to GitHub. Repo: `Mary-creat/crystallux-ai-sales-engine`. Branch: `scale-sprint-v1`. Build command: empty. Output directory: `admin-dashboard`. | 8 min |
| A-03 | Wait for first deploy of `crystallux-admin` to succeed | Cloudflare deploy log (green) | 3 min |
| A-04 | Add custom domain `admin.crystallux.org` to crystallux-admin | Project → Custom domains → Set up. CF will create the CNAME automatically. | 5 min |
| A-05 | Verify `https://admin.crystallux.org/` returns the bootstrap spinner | Browser, incognito | 1 min |
| A-06 | Repeat A-02..A-05 for `crystallux-app` (output dir: `client-dashboard`, domain: `app.crystallux.org`) | same | 15 min |
| A-07 | Open n8n UI → Settings → Credentials → New: `Supabase Crystallux` (HTTP Header Auth) | n8n UI (see N8N_IMPORT_GUIDE §3.1 for exact headers) | 5 min |
| A-08 | Test the credential with a temporary HTTP node hitting `/rest/v1/clients?select=id&limit=1` | n8n UI | 2 min |
| A-09 | Create remaining named credentials per N8N_IMPORT_GUIDE §3.3 (Anthropic, OpenAI, Gmail, Stripe, etc.) — only those needed for workflows you'll activate | n8n UI | 30 min |
| A-10 | Import 7 auth workflows (Phase A — `workflows/api/auth/*.json`) | n8n UI: Workflows → Import from file. **Activate `clx-auth-validate-session` first.** | 15 min |
| A-11 | After A-10, run §7.1 of N8N_IMPORT_GUIDE smoke tests (login, validate, magic link, logout, replay-after-logout) | terminal with curl | 10 min |
| A-12 | Import 9 admin workflows (Phase B — `workflows/api/admin/*.json`); activate after A-11 passes | n8n UI | 15 min |
| A-13 | Run §7.2 admin smoke tests | terminal | 10 min |
| A-14 | Import 9 client workflows (Phase C — `workflows/api/client/*.json`); activate after A-13 passes | n8n UI | 15 min |
| A-15 | Run §7.3 client smoke tests INCLUDING the cross-tenant injection test (CT-02) | terminal | 15 min |
| A-16 | Import 50 existing workflows in 11 logical groups (Phase D, see N8N_IMPORT_GUIDE §5) | n8n UI | 60-90 min |
| A-17 | End-to-end happy-path tests per PHASE_4_TEST_PLAN §3.7 (Mary login + test-client login) | browser | 20 min |

### Total estimated time

- Group D: 0 min (already done)
- Group B: 15 min
- Group C: 60 min (or 15 min if no system tuning needed)
- Group A: 3-4 hours
- **Total: 4-5 hours of focused work** before first client onboarding can start

---

## Section 5 — Error Recovery Procedures

### 5.1 Pages project fails to deploy

**Symptom:** Cloudflare deploy log shows red. Most common cause: the build command isn't empty (default Cloudflare templates auto-fill `npm run build` even for static sites).

**Recovery:**

1. Cloudflare → project → Settings → Builds & deployments → Build configurations → set Build command to **empty**, Output directory to `admin-dashboard` (or `client-dashboard`).
2. Trigger a redeploy: Deployments → ⋯ on the latest → Retry deployment.
3. If still failing, check that the repo branch is `scale-sprint-v1` (NOT `main`).
4. If domain is stuck on "Initializing" >10 min, delete the custom domain and re-add it.

**Rollback:** Cloudflare → project → Deployments → find the last green deploy → ⋯ → Rollback to this deployment. Sites become serving immediately.

### 5.2 n8n bcryptjs config fails

**Symptom:** Login webhook returns `500: Server bcrypt unavailable. Set NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs.`

**Recovery:**

```bash
sudo systemctl cat n8n              # confirm Environment line present
sudo systemctl edit --full n8n      # add/repair if missing
sudo systemctl daemon-reload
sudo systemctl restart n8n
journalctl -u n8n -n 50 --no-pager  # look for "n8n ready"
```

If on Docker Compose instead of systemd, edit `docker-compose.yml`:

```yaml
services:
  n8n:
    environment:
      - NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs,crypto
```

Then `docker compose up -d`. Verify with the one-off Code node test from N8N_IMPORT_GUIDE.md §2.

If n8n still rejects bcryptjs after the env var: the Docker image may not include it. Add to the image build OR mount a custom node_modules with `npm i bcryptjs` baked in. (Self-hosted n8n on the official image typically already has it once `NODE_FUNCTION_ALLOW_EXTERNAL` is set.)

### 5.3 Workflow import fails

**Symptom:** "Cannot import workflow: missing credential" or silent green workflow but every HTTP node returns 401.

**Recovery:**

1. The workflow imported but credentials are unbound. Open the workflow → each red HTTP node → Credentials dropdown → reselect by name (e.g. `Supabase Crystallux`) → Save → Save workflow.
2. If using CLI import (`n8n import:workflow`), credentials always need re-binding manually in the UI after import. Plan for it.
3. If imports succeed but the workflow has phantom nodes (e.g. "Send Email (placeholder)" appears as red): the n8n version on the VPS is older than expected. Either upgrade n8n or remove the placeholder node and replace it with a noop Code node.

**Rollback for a single workflow:** delete it from n8n UI, re-import from this repo. No data loss; the workflow definition is the source of truth.

### 5.4 Cross-tenant isolation test fails

**This is a P0. Stop everything and investigate before any client onboards.**

**Symptom:** in PHASE_4_TEST_PLAN §3.2 / CT-02 or CT-04, client A's request returns rows belonging to client B.

**Immediate actions:**

1. **Deactivate** the offending webhook in n8n (toggle to inactive). Clients see "endpoint not found" — that's safer than seeing other clients' data.
2. Open the webhook in the n8n UI. Find the Code node named "Check Client" or "Build Query".
3. Verify the `client_id` source: the line should be `row.client_id` where `row` is the result of `validate_session`. NOT `body.client_id`. NOT `inputs.client_id` from the request payload.
4. The next HTTP node should construct its URL with the `client_id` returned by Check Client, e.g. `'client_id=eq.' + encodeURIComponent($json.client_id)`.
5. If both look correct but the test still fails, run this SQL while the failing test is reproducing:

   ```sql
   SELECT s.session_token, s.user_id, u.email, u.client_id
   FROM   auth_sessions s
   JOIN   auth_users u ON u.id = s.user_id
   WHERE  s.session_token = '<token-used-in-the-failing-test>';
   ```

   If the row's `client_id` doesn't match what the user was supposed to be (e.g. the auth_users row was inserted with the wrong client_id), the bug is in the seed/onboarding script, not the webhook.

6. After the fix, re-import the workflow, re-activate, and **re-run the entire §3.2 7-test protocol from scratch**. Do not declare the bug fixed by re-running only the failing case.

### 5.5 Schema-fix migration fails mid-apply

**Symptom:** `2026-05-01-audit-fixes.sql` errors out partway through.

**Recovery:** the migration is wrapped in `BEGIN; … COMMIT;` so a failure rolls back automatically. To diagnose:

1. The error message will name the section. Common causes:
   - **§1 campaigns CREATE TABLE fails:** a `campaigns` table was already created out-of-band with a different schema. Check `\d campaigns` in psql; either rename the existing table (`ALTER TABLE campaigns RENAME TO legacy_campaigns;`) or comment out §1 of the fix migration.
   - **§2 appointment_log ADD COLUMN fails:** the column already exists with a conflicting type. Check `\d appointment_log`; if a `company` column already exists, comment out the relevant ADD line.
   - **§3 admin_action_log fails:** same — comment out the conflicting ADD lines.
   - **§4 scan_log CREATE TABLE fails:** the table exists with a different schema. **Don't force it.** Comment out §4. The existing scan_log on the live DB is presumably what the legacy MVP dashboard already uses; respect its shape.
2. Apply the fix migration in pieces if needed: copy the working sections into a new file and apply them.
3. After a partial apply, re-run §2.4 verification to confirm what's now in place.

### 5.6 Mary's "error in n8n to fetch workflow" symptom

**Diagnosis (it's vague — these are the likely causes ranked by probability):**

1. **Browser cache / cookie state.** Hard refresh (Ctrl+F5) the n8n UI; clear cookies for `automation.crystallux.org` if the UI is wedged.
2. **Workflow JSON has phantom credential id.** Open the file in a text editor, search for `"credentials"`, confirm each block has `"name"` only, no `"id"`. (Saved repo convention.) If an `id` field is present, strip it and re-import.
3. **n8n version mismatch on a node type.** Open the workflow JSON, look for `"typeVersion"` numbers; the most likely culprit is `n8n-nodes-base.if` at version 2.2 or `n8n-nodes-base.code` at version 2. Upgrade n8n to >=1.50 OR downgrade the typeVersion in the JSON to something the running n8n supports.
4. **Webhook path collision.** Two workflows have the same `path` (e.g. both export `auth/login`). n8n refuses the second import. Deactivate the conflicting one before re-importing.

If none of those: ask Mary to copy the *exact* error message + the workflow filename into a fresh chat and we'll triage from there.

---

## Section 6 — Estimated Time to Launch

### 6.1 Best case (no surprises)

| Phase | Duration |
|---|---|
| Group B SQL (audit fixes + verify) | 15 min |
| Group C n8n env (bcryptjs + restart) | 15 min |
| Group A Cloudflare projects + DNS + credentials | 60 min |
| Group A workflow imports + smoke tests (auth + admin + client) | 90 min |
| Phase 4 test suites (auth + isolation + token + happy path) | 4 hours |
| **Total best case** | **~7 hours** spread over 1-2 days |

This assumes:
- No errors in the audit-fix migration (every check in §2.4 returns ✅ on first run).
- bcryptjs loads cleanly on first n8n restart.
- All Cloudflare deploys go green on first try.
- Cross-tenant tests pass on first run (the architecture is correct; the only way they fail is a typo in a Code node, which would have shown up in Phase 3 unit checks already).
- Real email (Postmark/SendGrid) wire-up is **deferred** to a follow-up — magic links work via the click_url surfaced in n8n execution logs for first internal testing.

### 6.2 Worst case (each step has a problem)

| Phase | Duration |
|---|---|
| Group B (one column conflict in audit-fix migration → comment-out + retry) | 1 hour |
| Group C (bcryptjs requires Docker image rebuild) | 2 hours |
| Group A (one Pages project deploy fails due to build-config drift; one credential mis-named in n8n; one workflow has typeVersion conflict) | 4 hours |
| Phase 4 (one cross-tenant test fails → debug + fix + rerun entire suite) | 8 hours |
| Real email wire-up before first paid client | 2 hours |
| Stripe portal URL replacement | 1 hour |
| Cloudflare WAF rules install + verify | 2 hours |
| **Total worst case** | **~20 hours** spread over 4-5 days |

### 6.3 Critical path

The single longest blocking path is:

```
audit-fixes migration applied  →  n8n bcryptjs configured  →
n8n auth workflows active  →  n8n admin+client workflows active  →
Pages projects + DNS live  →  Phase 4 cross-tenant test passes
```

Of these, the cross-tenant test is the only one that is non-recoverable in the same day if it fails (because debugging happens against a real test environment). Everything else is mechanical and recoverable in <1 hour.

### 6.4 What blocks first paid client onboarding

The minimum acceptable bar:

1. ✅ Group B done (schema fixes + verification SQL all green)
2. ✅ Group C done (n8n bcryptjs working)
3. ✅ Group A done through A-15 (auth + admin + client workflows live; smoke tests pass; cross-tenant injection test passes)
4. ✅ Mary can sign in at admin.crystallux.org and see Overview render with real data
5. ✅ At least one test client account can sign in at app.crystallux.org and see only their data
6. ⚠️ Real email delivery for magic-link / password-reset wired up — **OR** Mary issues a temp password and rotates it via the password-reset flow on first client login
7. ⚠️ Cloudflare WAF rate-limit rules installed (per PHASE_4_TEST_PLAN §3.4.2)
8. ⚠️ `admin_action_log` writes from `clx-client-settings` and `clx-auth-password-reset-complete` (Phase 4 follow-up code work)

Items 1-5 are gated on this audit; 6-8 are Phase 4 follow-ups that can land within a week of go-live. The first paid client can onboard once 1-5 are done, with 6 done in a temp-password mode.

---

## Appendix — One-screen summary

```
P0 schema gaps to fix before activating webhooks (apply 2026-05-01-audit-fixes.sql):
  F-01  campaigns table missing                    → blocks clx-client-campaigns
  F-02  appointment_log missing 3 columns          → blocks clx-client-bookings
  F-03  admin_action_log column rename             → blocks clx-admin-audit-log
  F-04  scan_log existence guard                   → may block clx-admin-system-health/workflow-status
  F-05  daily_digest/booking_alerts_opt_in cols    → blocks clx-client-settings write path

Mary's checklist to launch:
  B  Run §2.4 verify SQL → apply client-settings + audit-fixes migrations → re-verify
  C  Set NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs on n8n VPS, restart
  A  Cloudflare: delete failed Worker; create crystallux-admin + crystallux-app Pages
     projects; add admin.crystallux.org + app.crystallux.org custom domains
  A  n8n: create Supabase Crystallux credential; import + activate 7 auth, then 9 admin,
     then 9 client workflows; smoke test each phase before moving to next
  A  Run Phase 4 cross-tenant test (PHASE_4_TEST_PLAN §3.2 — the P0 suite)

Time to launch: 7 hours best case, 20 hours worst case. Critical path = cross-tenant
test passing. Once Phase 4 §3.2 is green, first paid client can onboard.
```
