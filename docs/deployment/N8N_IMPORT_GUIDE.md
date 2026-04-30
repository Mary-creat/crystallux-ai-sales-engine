# Crystallux n8n Workflow Import Guide

**Audience:** Mary (or anyone bringing the n8n VPS up from scratch).
**Last reviewed:** 2026-04-30
**Total workflows to import:** **75** (50 existing + 25 new — 7 auth + 9 admin + 9 client)
**Target n8n instance:** `https://automation.crystallux.org`

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [n8n environment variables](#2-n8n-environment-variables)
3. [Credentials to create in n8n](#3-credentials-to-create-in-n8n)
4. [Migrations to apply BEFORE importing](#4-migrations-to-apply-before-importing)
5. [Import order & activation phases](#5-import-order--activation-phases)
6. [Importing workflows (UI + CLI methods)](#6-importing-workflows)
7. [Smoke tests after each phase](#7-smoke-tests-after-each-phase)
8. [Troubleshooting](#8-troubleshooting)
9. [Rollback procedure](#9-rollback-procedure)

---

## 1. Prerequisites

| Check | How |
|---|---|
| n8n instance reachable | `curl -I https://automation.crystallux.org/healthz` returns 200 |
| Postgres + Redis healthy | `docker compose ps` on the VPS shows both services Up |
| Supabase project alive | Supabase dashboard for `zqwatouqmqgkmaslydbr` shows green |
| Auth migration applied | `select count(*) from auth_users;` returns ≥1 (Mary's seed) |
| Repo cloned on VPS (optional, for CLI import) | `git clone … && cd crystallux-ai-sales-engine` |

If any of those fail, **stop here** — fix the dependency before importing workflows.

---

## 2. n8n environment variables

Set these on the n8n VPS **before starting the n8n process**. The auth and password-reset workflows depend on `bcryptjs` being allowed in Code nodes; without this, they will return `500: Server bcrypt unavailable`.

Add to the systemd unit (typical path `/etc/systemd/system/n8n.service`):

```ini
[Service]
Environment="NODE_FUNCTION_ALLOW_EXTERNAL=bcryptjs,crypto"
Environment="N8N_HOST=automation.crystallux.org"
Environment="N8N_PROTOCOL=https"
Environment="WEBHOOK_URL=https://automation.crystallux.org/"
Environment="N8N_LOG_LEVEL=info"
Environment="N8N_LOG_OUTPUT=file"
Environment="EXECUTIONS_DATA_PRUNE=true"
Environment="EXECUTIONS_DATA_MAX_AGE=720"        # hours = 30 days
Environment="GENERIC_TIMEZONE=America/Toronto"
Environment="N8N_DEFAULT_LOCALE=en-CA"
Environment="N8N_PERSONALIZATION_ENABLED=false"
Environment="N8N_DIAGNOSTICS_ENABLED=false"
Environment="N8N_VERSION_NOTIFICATIONS_ENABLED=false"
Environment="N8N_TEMPLATES_ENABLED=false"
```

Then reload + restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart n8n
journalctl -u n8n -n 50 --no-pager
```

Confirm `bcryptjs` is loadable from inside n8n by creating a one-off Code node and pasting:

```js
const b = require('bcryptjs'); return { json: { v: typeof b.hash } };
```

You should see `"v": "function"`. If you get `Cannot find module 'bcryptjs'`, the env var isn't taking effect — restart n8n.

---

## 3. Credentials to create in n8n

All workflows reference credentials **by name**, never by id (this is the saved repo convention — `id` fields are stripped on import to avoid n8n "credential not found" errors when ids drift).

Create these in **Settings → Credentials → New** before importing:

### 3.1 `Supabase Crystallux` (HTTP Header Auth)

Used by every workflow that talks to PostgREST (75 of them). The bearer is the **service-role** key — never an anon key.

```
Type:        HTTP Header Auth
Name:        Supabase Crystallux           ← exact, case-sensitive
Headers:
  Authorization:  Bearer <SUPABASE_SERVICE_ROLE_KEY>
  apikey:         <SUPABASE_SERVICE_ROLE_KEY>
```

Test it with a temporary HTTP Request node hitting `https://zqwatouqmqgkmaslydbr.supabase.co/rest/v1/clients?select=id&limit=1`. Should return JSON.

### 3.2 `Anthropic API` (HTTP Header Auth)

Used by the Copilot workflows + lead-research + script-matcher.

```
Type:    HTTP Header Auth
Name:    Anthropic API
Headers:
  x-api-key:           <ANTHROPIC_API_KEY>
  anthropic-version:   2023-06-01
  Content-Type:        application/json
```

### 3.3 Other credentials (referenced by the 50 existing workflows)

These names exist in workflow JSON; create each before activating its dependent workflows. **Names are case-sensitive.**

| Name | Type | Used by |
|---|---|---|
| `Apollo API`        | HTTP Header Auth (`X-Api-Key`) | clx-apollo-enrichment-v1, clx-lead-research-v2 |
| `Google Maps`       | HTTP Query Auth (`key`)         | clx-appointment-geocoder-v1, clx-route-optimizer-v1, clx-city-scan-discovery |
| `Gmail OAuth2`      | OAuth2 (Gmail scope)            | clx-outreach-sender-v2, clx-reply-ingestion-v1, clx-follow-up-v2 |
| `Calendly OAuth2`   | OAuth2 (Calendly)               | clx-booking-v2, clx-no-show-detector-v1 |
| `Stripe`            | HTTP Header Auth                | clx-stripe-provision-v1, clx-stripe-webhook-v1 |
| `OpenAI`            | HTTP Header Auth                | clx-copilot-whisper-v1 (transcription) |
| `Twilio`            | HTTP Basic Auth                 | clx-no-show-sms-recovery-v1, clx-whatsapp-outreach-v1 |
| `Vapi`              | HTTP Header Auth                | clx-vapi-transcript-streamer-v1, clx-voice-outreach-v1, clx-voice-result-webhook-v1 |
| `LinkedIn API`      | HTTP Header Auth                | clx-linkedin-outreach-v1 |
| `Postmark` *(or SendGrid / SMTP)* | HTTP Header Auth | placeholder in clx-auth-magic-link, clx-auth-password-reset-request — **wire this before launch** |

**You don't need every credential to start.** Auth + admin + client webhooks only need `Supabase Crystallux`. Other credentials are only required for the existing workflows that consume them. Activate workflows as their credentials become available — n8n surfaces a clear "credential not configured" error rather than running with no auth.

---

## 4. Migrations to apply BEFORE importing

The Supabase project must already have the schema each workflow expects. Apply migrations in chronological order. The auth + new dashboard work depends specifically on:

| Migration | Required by |
|---|---|
| All 18 baseline migrations through `2026-04-25-realtime-script-suggestions.sql` | the 50 existing workflows |
| `2026-04-28-authentication.sql` | every auth/admin/client webhook (uses `validate_session` RPC) |
| `2026-04-30-admin-dashboard-columns.sql` | clx-admin-onboarding-pipeline |
| `2026-04-30-client-settings-columns.sql` | clx-client-settings (write path) |

Confirm the auth migration with:

```sql
select email, user_role, email_verified
from   auth_users
where  user_role = 'admin';
```

Should return exactly 1 row (Mary). If it returns 0, the seed didn't apply — check the migration log.

Confirm `validate_session` is callable:

```sql
select * from validate_session('does-not-exist');   -- should return 0 rows, no error
```

---

## 5. Import order & activation phases

Activate in **this exact order**. Each phase depends on the previous one being green.

### Phase A — Auth (7 workflows)

```
workflows/api/auth/clx-auth-validate-session.json   ← activate FIRST; everything else calls it
workflows/api/auth/clx-auth-login.json
workflows/api/auth/clx-auth-logout.json
workflows/api/auth/clx-auth-magic-link.json
workflows/api/auth/clx-auth-magic-link-verify.json
workflows/api/auth/clx-auth-password-reset-request.json
workflows/api/auth/clx-auth-password-reset-complete.json
```

**Why this order:** every other API webhook calls validate-session via the `validate_session` RPC, but the n8n workflow itself is also callable as `/webhook/auth/validate-session` for the dashboard's bootstrap. If you activate the dashboard webhooks before validate-session, they still work (they hit the RPC directly), but you can't sanity-check token issuance from the login form.

After activating, **run the [smoke tests](#71-phase-a-smoke-tests-auth)**. Don't proceed to Phase B until login + logout cycle through cleanly.

### Phase B — Admin (9 workflows)

```
workflows/api/admin/clx-admin-list-clients.json
workflows/api/admin/clx-admin-client-detail.json
workflows/api/admin/clx-admin-list-leads.json
workflows/api/admin/clx-admin-system-health.json
workflows/api/admin/clx-admin-billing-summary.json
workflows/api/admin/clx-admin-workflow-status.json
workflows/api/admin/clx-admin-onboarding-pipeline.json
workflows/api/admin/clx-admin-market-intelligence.json
workflows/api/admin/clx-admin-audit-log.json
```

These are read-only against the existing schema. Safe to activate together once `2026-04-30-admin-dashboard-columns.sql` is applied.

### Phase C — Client (9 workflows)

```
workflows/api/client/clx-client-overview.json
workflows/api/client/clx-client-leads.json
workflows/api/client/clx-client-campaigns.json
workflows/api/client/clx-client-bookings.json
workflows/api/client/clx-client-replies.json
workflows/api/client/clx-client-activity.json
workflows/api/client/clx-client-performance.json
workflows/api/client/clx-client-billing.json
workflows/api/client/clx-client-settings.json
```

Settings is the only writer; verify after Phase C that a `notification_email` change persists.

### Phase D — Existing workflows (50 — non-blocking)

Activate the existing workflows in `workflows/` (root) **after** the auth/admin/client surface is green. None of them depend on the new auth tables; they are independent automation. Suggested grouping:

1. **Discovery + lead intake (10):** city-scan-discovery, b2c-discovery-v2.1, lead-research-v2, lead-import, signal-ingestion-v1, signal-intelligence-v1, business-signal-detection-v2, intelligence-upsell-detector-v1, apollo-enrichment-v1, email-scraper-v3
2. **Pipeline + scoring (5):** lead-scoring-v2, pipeline-update-v2, task-classifier-v1, activity-classifier-v1, activity-tracker-v1
3. **Outreach (8):** campaign-router-v2, outreach-generation-v2, outreach-sender-v2, follow-up-v2, linkedin-outreach-v1, whatsapp-outreach-v1, voice-outreach-v1, video-outreach-v1
4. **Booking + recovery (4):** booking-v2, no-show-detector-v1, no-show-sms-recovery-v1, appointment-geocoder-v1
5. **Daily ops (4):** daily-plan-generator-v1, daily-summary-generator-v1, route-optimizer-v1, reshuffle-suggester-v1
6. **Real-time call ops (5):** vapi-transcript-streamer-v1, transcript-classifier-realtime-v1, realtime-script-suggester-v1, post-call-analyzer-v1, voice-result-webhook-v1
7. **Script intelligence (2):** script-matcher-v1, script-learning-loop-v1
8. **Stripe (2):** stripe-provision-v1, stripe-webhook-v1
9. **Form intake + reply (2):** form-intake-v1, reply-ingestion-v1
10. **Copilot (4):** copilot-platform-v1, copilot-query-v1, copilot-troubleshoot-v1, copilot-whisper-v1
11. **Misc (4):** mcp-tool-gateway, error-monitor-v1, video-ready-v1, verify-dashboard-access-v1

Activate group by group, smoke-test as you go. You don't need all 50 active to launch the dashboards — auth + admin + client (25 workflows) is enough for Mary to log in and clients to see their data once seeded.

---

## 6. Importing workflows

### 6.1 Via the n8n UI (recommended for first import)

1. Open `https://automation.crystallux.org` and sign in.
2. **Workflows → Import from File**.
3. Select the `.json` file from this repo.
4. After import, n8n shows the workflow in **Inactive** state. Click **Save**.
5. Open the workflow → **Credentials** tab. If a credential reference is "missing", click the dropdown and pick the matching name (e.g. "Supabase Crystallux"). **Save** again.
6. Toggle **Active** at the top right. Confirm the green status pill.
7. Repeat for the next workflow in the activation order.

**Watch out for credential matching.** The repo convention strips credential `id` and only includes `name`. After import, n8n shows credentials by name and you must explicitly bind them. If you skip this step, the workflow runs but every HTTP node returns 401.

### 6.2 Via the n8n CLI (faster for bulk import)

If you have shell access to the VPS:

```bash
# From the n8n container or host that has n8n CLI
cd /path/to/crystallux-ai-sales-engine

# Import a single file
n8n import:workflow --input=workflows/api/auth/clx-auth-login.json

# Bulk import a folder
n8n import:workflow --separate --input=workflows/api/auth/

# After import, activate by name
n8n update:workflow --name="CLX - Auth Login v1" --active=true
```

CLI imports still leave credentials unbound. Either bind manually in the UI or run a one-off SQL update against n8n's database to re-link the credential rows (advanced — see n8n docs).

### 6.3 Verify import

After Phase A:

```bash
# Should list 7 active auth workflows
n8n list:workflow --active=true | grep "Auth"
```

Or in the UI: **Workflows → filter "Active" → search "auth"**.

---

## 7. Smoke tests after each phase

Test from your laptop (not the VPS) so you exercise the whole CDN → n8n → Supabase path. Replace `$EMAIL` and `$PASS` with Mary's credentials.

### 7.1 Phase A smoke tests (Auth)

```bash
# 1. Login → expect a session token
TOKEN=$(curl -s -X POST https://automation.crystallux.org/webhook/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" | jq -r .session_token)
echo "TOKEN: $TOKEN"
# Expect a 64-character base64url string. Empty = failure.

# 2. Validate session → expect ok:true with role:admin
curl -s -X POST https://automation.crystallux.org/webhook/auth/validate-session \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' | jq .

# 3. Wrong password → expect 401
curl -s -X POST https://automation.crystallux.org/webhook/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"definitely-wrong\"}" | jq .
# After 5 such requests in 15 minutes, the account locks (423).

# 4. Magic link → expect ok:true (always; no leak)
curl -s -X POST https://automation.crystallux.org/webhook/auth/magic-link \
  -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\"}" | jq .
# In the n8n execution log, find the click_url and copy it for testing the
# verify endpoint (until real email is wired).

# 5. Logout → expect ok:true
curl -s -X POST https://automation.crystallux.org/webhook/auth/logout \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' | jq .

# 6. Validate the now-revoked token → expect 401
curl -s -X POST https://automation.crystallux.org/webhook/auth/validate-session \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' | jq .
```

**Pass criteria for Phase A:** all six commands behave as the comments describe. If any return network errors, n8n is down. If steps 1+2 succeed but 5+6 fail with the original token still working after logout, the `revoke_session` RPC isn't being called — check the n8n execution log for the logout webhook.

### 7.2 Phase B smoke tests (Admin)

```bash
# Re-issue a fresh admin token first (Phase A test 5 revoked the previous one)
TOKEN=$(curl -s -X POST https://automation.crystallux.org/webhook/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" | jq -r .session_token)

# 1. system-health
curl -s -X POST https://automation.crystallux.org/webhook/admin/system-health \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' | jq .
# Expect: { ok:true, total_leads, active_clients, booked_this_week, errors_24h, mrr_cad }

# 2. list-clients
curl -s -X POST https://automation.crystallux.org/webhook/admin/list-clients \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"filters":{}}' | jq '.clients | length'

# 3. list-leads with filter
curl -s -X POST https://automation.crystallux.org/webhook/admin/list-leads \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"filters":{"status":"Booked","limit":10}}' | jq '.leads | length'

# 4. NEGATIVE: no token → expect 401
curl -s -X POST https://automation.crystallux.org/webhook/admin/list-clients \
  -H 'Content-Type: application/json' -d '{}' | jq .
```

**Pass criteria for Phase B:** all 9 admin endpoints return `ok:true` with valid token; all return 401 without a token. The dashboard at `admin.crystallux.org` will then load with no console errors.

### 7.3 Phase C smoke tests (Client)

You need a client login to run these. Create one (one-time):

```sql
-- Pick an existing client_id from the clients table
select id from clients where active=true limit 1;
-- Then, after generating a bcrypt hash via scripts/auth-bcrypt.js:
insert into auth_users (email, password_hash, user_role, client_id, email_verified, email_verified_at)
values ('test-client@crystallux.org', '<bcrypt-hash>', 'client', '<client-uuid>', true, now());
```

Then:

```bash
CLIENT_TOKEN=$(curl -s -X POST https://automation.crystallux.org/webhook/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test-client@crystallux.org","password":"<test-password>"}' | jq -r .session_token)

# 1. overview → expect client object + stats
curl -s -X POST https://automation.crystallux.org/webhook/client/overview \
  -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' -d '{}' | jq .

# 2. leads → returns ONLY this client's leads
curl -s -X POST https://automation.crystallux.org/webhook/client/leads \
  -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' \
  -d '{"filters":{"limit":50}}' | jq '.leads | length'

# 3. CROSS-TENANT: attempt to inject another client_id in the body
curl -s -X POST https://automation.crystallux.org/webhook/client/leads \
  -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' \
  -d '{"filters":{"limit":50},"client_id":"<some-other-client-uuid>"}' | jq '.leads | length'
# MUST return the same count as call #2 — the webhook ignores the body's
# client_id and uses the session's client_id. If counts differ, that is
# a P0 isolation bug — stop and investigate.

# 4. NEGATIVE: admin token → expect 403 (admin can't use client endpoints)
curl -s -X POST https://automation.crystallux.org/webhook/client/leads \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}' | jq .

# 5. settings write
curl -s -X POST https://automation.crystallux.org/webhook/client/settings \
  -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' \
  -d '{"notification_email":"test@example.com","daily_digest_opt_in":true}' | jq .
# Re-read to confirm:
curl -s -X POST https://automation.crystallux.org/webhook/client/settings \
  -H "Authorization: Bearer $CLIENT_TOKEN" -H 'Content-Type: application/json' -d '{}' | jq .client
```

**Pass criteria for Phase C:** every endpoint returns `ok:true`; cross-tenant injection (test 3) returns the same row count as the clean call (test 2); admin tokens are rejected with 403 (test 4).

### 7.4 Phase D smoke tests (existing workflows)

Each existing workflow has its own surface — most are scheduled triggers, a few are webhooks. The full validation belongs in `PHASE_4_TEST_PLAN.md`. For a fast Phase D smoke:

```bash
# Pick any one webhook-triggered workflow (form-intake is a clean test)
curl -s -X POST https://automation.crystallux.org/webhook/form-intake \
  -H 'Content-Type: application/json' \
  -d '{"client_slug":"blonai","full_name":"Test Person","email":"smoke-test+$(date +%s)@example.com"}'
# Expect a 2xx and a new row in leads matching the email.
```

For scheduled workflows, manually trigger one execution from the n8n UI (Workflow → ⋯ → Execute Workflow) and check the execution log for green ticks on every node.

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Cannot find module 'bcryptjs'` (login or password-reset) | `NODE_FUNCTION_ALLOW_EXTERNAL` not set | Set the env var in §2, restart n8n |
| Every Supabase HTTP node 401 | Credential bound by id, not name; or wrong service-role key | Open the workflow → Credentials tab → reselect "Supabase Crystallux" by name |
| Login returns 401 even with right password | `auth_users.password_hash` is the placeholder, or the bcrypt cost mismatch | Re-run `scripts/auth-bcrypt.js` and `UPDATE auth_users SET password_hash = '<hash>' WHERE email = '...'` |
| Login returns 423 (locked) | 5 failed attempts in last 15 min | Unlock with `UPDATE auth_users SET failed_login_attempts=0, locked_until=NULL WHERE email='...'` |
| validate-session returns 401 immediately after a successful login | Session row inserted but token mismatched (rare; URL-encoding bug) | Inspect `auth_sessions.session_token`; the n8n UI's "last execution" view shows the exact token sent vs stored |
| admin/* endpoint returns 403 with a valid admin token | `validate_session` returned a row but `user_role` is something other than `'admin'` | `select user_role from auth_users where email='info@crystallux.org';` |
| client/* endpoint returns 403 "No client mapped to session" | Auth row has `user_role='client'` but `client_id` is NULL | `UPDATE auth_users SET client_id='<uuid>' WHERE email='...'` |
| Cross-tenant test returns DIFFERENT row count from clean call | **STOP**. Webhook is using the body's `client_id` instead of the session's. Open the webhook in n8n → check the "Build Query" / "Check Client" Code node uses `row.client_id` not `body.client_id`. |
| CORS blocked from admin.crystallux.org or app.crystallux.org | n8n needs CORS headers added on webhook responses | Either add a Set node before each Respond node OR put Cloudflare Workers in front of n8n with a simple CORS header injection. (Tracked for Phase 4.) |
| Magic link "click_url" never lands in inbox | Email node is still the placeholder Code node | Wire Postmark/SendGrid/SMTP per §3 before launch |

---

## 9. Rollback procedure

If a workflow misbehaves in production:

```bash
# 1. Deactivate it immediately (UI: toggle inactive; CLI:)
n8n update:workflow --name="CLX - Whatever" --active=false

# 2. If the workflow corrupted data, revert at the Supabase layer:
#    - Find the offending writes via auth_sessions/scan_log timestamps
#    - Restore from Supabase point-in-time recovery (requires Pro tier)
#    - Or apply a corrective UPDATE/DELETE manually

# 3. Re-import the workflow from this repo to discard local n8n edits
n8n import:workflow --input=workflows/api/<area>/<file>.json
```

For the auth migration, a full rollback (drop tables) is documented at the bottom of `2026-04-28-authentication.sql`. Don't run it unless you've confirmed no other system depends on `auth_*` tables.

---

## Appendix A — file → endpoint map

```
Auth (Phase A)
  workflows/api/auth/clx-auth-login.json                     POST /webhook/auth/login
  workflows/api/auth/clx-auth-logout.json                    POST /webhook/auth/logout
  workflows/api/auth/clx-auth-validate-session.json          POST /webhook/auth/validate-session
  workflows/api/auth/clx-auth-magic-link.json                POST /webhook/auth/magic-link
  workflows/api/auth/clx-auth-magic-link-verify.json         POST /webhook/auth/magic-link-verify
  workflows/api/auth/clx-auth-password-reset-request.json    POST /webhook/auth/password-reset-request
  workflows/api/auth/clx-auth-password-reset-complete.json   POST /webhook/auth/password-reset-complete

Admin (Phase B)
  workflows/api/admin/clx-admin-list-clients.json            POST /webhook/admin/list-clients
  workflows/api/admin/clx-admin-client-detail.json           POST /webhook/admin/client-detail
  workflows/api/admin/clx-admin-list-leads.json              POST /webhook/admin/list-leads
  workflows/api/admin/clx-admin-system-health.json           POST /webhook/admin/system-health
  workflows/api/admin/clx-admin-billing-summary.json         POST /webhook/admin/billing-summary
  workflows/api/admin/clx-admin-workflow-status.json         POST /webhook/admin/workflow-status
  workflows/api/admin/clx-admin-onboarding-pipeline.json     POST /webhook/admin/onboarding-pipeline
  workflows/api/admin/clx-admin-market-intelligence.json     POST /webhook/admin/market-intelligence
  workflows/api/admin/clx-admin-audit-log.json               POST /webhook/admin/audit-log

Client (Phase C)
  workflows/api/client/clx-client-overview.json              POST /webhook/client/overview
  workflows/api/client/clx-client-leads.json                 POST /webhook/client/leads
  workflows/api/client/clx-client-campaigns.json             POST /webhook/client/campaigns
  workflows/api/client/clx-client-bookings.json              POST /webhook/client/bookings
  workflows/api/client/clx-client-replies.json               POST /webhook/client/replies
  workflows/api/client/clx-client-activity.json              POST /webhook/client/activity
  workflows/api/client/clx-client-performance.json           POST /webhook/client/performance
  workflows/api/client/clx-client-billing.json               POST /webhook/client/billing
  workflows/api/client/clx-client-settings.json              POST /webhook/client/settings
```
