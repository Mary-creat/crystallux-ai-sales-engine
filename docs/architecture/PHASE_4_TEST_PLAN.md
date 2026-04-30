# Phase 4 — Security &amp; Acceptance Test Plan

**Status:** Specification only. **Do not run tests until infrastructure is deployed** (auth migration applied, all 25 new webhooks active in n8n, both Cloudflare Pages projects live).
**Target sign-off:** "Mary can ship clients to `app.crystallux.org` without security or scalability concerns."
**Estimated execution time:** 8–12 hours of focused work spread over 3–5 days.

---

## 1. Scope

This plan validates **only** the new Tier-2/3/4/5 architecture (auth + admin + client dashboards + their webhooks). It does **not** re-test the 50 existing automation workflows — those have their own per-workflow contracts and are validated by their own execution logs and the existing `dashboard/CLIENT_ISOLATION_TEST.md` for the legacy MVP dashboard.

### 1.1 In scope

- All 25 new n8n webhooks (`workflows/api/auth/*`, `workflows/api/admin/*`, `workflows/api/client/*`)
- The two new dashboards (`admin.crystallux.org`, `app.crystallux.org`)
- The four new auth tables and their RPCs (`validate_session`, `touch_session`, `revoke_session`, `register_failed_login`, `register_successful_login`)
- The five new public auth pages on `crystallux.org` (login, magic-link-sent, magic-link-verify, forgot-password, reset-password)
- Cross-tenant isolation between two real client accounts
- Token lifecycle (issue → use → expire → revoke → reuse-fail)
- Rate limiting at the n8n + Cloudflare layers
- Audit log completeness for security-relevant actions

### 1.2 Out of scope

- Existing 50 workflow logic (already in production)
- Marketing site (`crystallux.org`)
- Legacy MVP dashboard at `crystallux-dashboard.pages.dev` (kept intact as fallback)
- The Stripe customer portal URL (still placeholder; tracked separately)
- Real email delivery for magic link / password reset (placeholder Code nodes; wire Postmark/SendGrid in a focused follow-up)

### 1.3 Pass / fail definition

A test **passes** only when its expected output matches exactly. Any deviation is a fail and must be triaged before shipping clients.

A finding is **P0** (blocker) if it allows: a client to read another client's data, a token to bypass revocation, a non-admin to call admin endpoints, or any path that exposes the Supabase service-role key to a browser.

A finding is **P1** if it degrades UX or trust but doesn't breach isolation: missing audit row, wrong error message, slow path, layout glitch.

A finding is **P2** if it is cosmetic or improvement-only.

**Gate:** **zero P0**, **zero unresolved P1** before Mary onboards a real paying client to the new dashboard.

---

## 2. Test environment

Set up before any test runs:

| Asset | Value | Notes |
|---|---|---|
| Mary admin login | `info@crystallux.org` | bcrypt hash already installed (per Phase 1 sign-off) |
| Test client A | `qa-client-a@crystallux.org` | bound to `clients.id = <UUID-A>`; bcrypt hash issued via `scripts/auth-bcrypt.js` |
| Test client B | `qa-client-b@crystallux.org` | bound to `clients.id = <UUID-B>`; **different** client row |
| Test team_member | `qa-tm-a@crystallux.org` | bound to client A's `clients.id`; same client_id as test client A |
| Two real `clients` rows | A: "QA Alpha Moving"; B: "QA Beta Cleaning" | seed 50+ leads on each, several `Booked` outcomes, one `appointment_log` row each |
| Burner browser profile | Chrome incognito + Firefox container | so localStorage between A and B doesn't bleed via the tester's habits |
| Network capture | DevTools → Network → "Preserve log" | required for §5 token-leak tests |
| Subdomains live | `admin.crystallux.org`, `app.crystallux.org` | DNS proxied through Cloudflare; HSTS preload deferred until soak test passes |

**Time-box:** the test environment setup itself is ~1 hour. Don't compress it; clean fixtures avoid false-positive isolation findings.

---

## 3. Test suites

### 3.1 Auth lifecycle (15 cases, ~45 min)

Each is a curl + assertion pair. Detailed commands live in `docs/deployment/N8N_IMPORT_GUIDE.md` §7.1; this section captures the test matrix.

| # | Case | Expected |
|---|---|---|
| AL-01 | Login with correct email + password | 200; `session_token` is 64-char base64url; `expires_at` ≈ now + 7d |
| AL-02 | Login with correct email, wrong password | 401; counter increments on `auth_users.failed_login_attempts` |
| AL-03 | 5× wrong password within 15 min | 5th call returns 423; `auth_users.locked_until ≈ now+15min` |
| AL-04 | Locked account, correct password | 423 until `locked_until` passes |
| AL-05 | Login with unknown email | 401 with same generic error message as wrong-password (no existence leak) |
| AL-06 | Validate session with valid token | 200; `user.role`, `user.email`, `user.client_id` populated correctly |
| AL-07 | Validate session with no `Authorization` header | 401 |
| AL-08 | Validate session with malformed header | 401 |
| AL-09 | Validate session sliding window | After validate, `auth_sessions.expires_at` is renewed +7d |
| AL-10 | Logout | 200; `auth_sessions.revoked_at` set |
| AL-11 | Validate session AFTER logout (same token) | 401 |
| AL-12 | Magic link request — valid email | 200; row in `auth_magic_links`; n8n execution log shows `click_url` |
| AL-13 | Magic link request — unknown email | 200 (same response shape — no existence leak) |
| AL-14 | Magic link verify — fresh token | 200; new session token; `auth_magic_links.used_at` set |
| AL-15 | Magic link verify — same token reused | 401 ("Link already used") |
| AL-16 | Magic link verify — token after 16 minutes | 401 ("Link expired") |
| AL-17 | Password reset request | 200; row in `auth_password_resets`; click_url surfaced in execution log |
| AL-18 | Password reset complete with new password | 200; bcrypt hash on `auth_users` changes; ALL existing sessions for that user have `revoked_at` set |
| AL-19 | Login with old password after reset | 401 |
| AL-20 | Login with new password after reset | 200; new session issued |

**Pass criteria:** all 20 cases produce the expected response. No P0 if behaviour is wrong on AL-05, AL-13, AL-15, AL-16, AL-19 (existence leaks / replay attacks / stale-credential acceptance).

---

### 3.2 Cross-tenant isolation — the 7-test protocol (~90 min)

The single most important suite. **Every test must pass.** A failure here means a paying client could see another client's data.

Set up: client A and client B both seeded with 50+ leads, separate companies, no shared rows. Mary admin token in `$ADMIN`, client A token in `$A`, client B token in `$B`.

| # | Case | Expected |
|---|---|---|
| CT-01 | Client A calls `/client/leads` | Only A's leads |
| CT-02 | Client A injects `client_id` of B in body | Same count as CT-01 (server uses session's client_id) |
| CT-03 | Client A injects `client_id` of B in URL query string | Same count as CT-01 (server doesn't read query string for client_id) |
| CT-04 | Client A calls `/client/overview`, `/client/campaigns`, `/client/bookings`, `/client/replies`, `/client/activity`, `/client/performance`, `/client/billing` | Each returns A's data only; no row containing B's `client_id` |
| CT-05 | Client A calls `/admin/list-clients` | 403 ("Admin access required") |
| CT-06 | Client A calls `/admin/list-leads` | 403 |
| CT-07 | Client A token used at `app.crystallux.org/pages/leads.html`, then DevTools → localStorage manually replaced with client B's token, page refresh | Page now shows B's data (token swap is legitimate — this confirms the dashboard does NOT cache prior client's data anywhere) |
| CT-08 | Admin token used at `app.crystallux.org` | Redirects to `admin.crystallux.org` (auth.js gate) |
| CT-09 | Client A token used at `admin.crystallux.org` | Redirects back to `app.crystallux.org` |
| CT-10 | Client A logs out; resume page load on client A's tab | Redirects to login; localStorage cleared |
| CT-11 | team_member of client A calls `/client/settings` write | 403 ("Only the primary account can change settings") |
| CT-12 | team_member of client A calls `/client/leads` | 200 with A's leads (read-only access works) |
| CT-13 | Mary admin token calls `/client/leads` | 403 (client endpoints reject admin) |

**Pass criteria:** zero rows of client B appear in any client A response. Any leak is **P0** — stop everything, isolate the offending webhook, fix the `client_id` derivation, re-run the entire suite.

**Verification of fix:** cross-check `auth_sessions.user_id → auth_users.client_id` for the offending session matches the data returned. If they match but the leak still happened, the bug is in the SQL filter, not the auth layer.

---

### 3.3 Token security &amp; storage (~60 min)

| # | Case | Expected |
|---|---|---|
| TS-01 | Inspect localStorage on logged-in tab | `clx_session_token` present; nothing labelled "supabase", "service_role", "anon", "apikey"; values in `clx_user_*` keys are not bearer-shaped |
| TS-02 | Inspect document.cookie | No session token in cookies (Phase 4 still uses localStorage; httpOnly cookies tracked for hardening) |
| TS-03 | Inspect Network tab on every dashboard page load | No request to `*.supabase.co`; all requests go to `automation.crystallux.org/webhook/*` |
| TS-04 | View page source on every dashboard page | No occurrence of "service_role", a JWT, or `eyJ` (the JWT prefix) |
| TS-05 | View shared/*.js source served from CDN | Same as TS-04 |
| TS-06 | Manually call `validate_session` RPC on Supabase using the anon key | RPC is `SECURITY DEFINER` and `EXECUTE` is `service_role`-only; anon call returns "permission denied" |
| TS-07 | Steal a session token, replay from a different IP | 200 (acceptable — the dashboard does not pin sessions to IP today; tracked for future hardening). Verify the replay still appears as the original `user_agent` in `auth_sessions` and is logged in the audit log |
| TS-08 | Modify the `expires_at` field of an `auth_sessions` row to past | `validate_session` filters on `expires_at > now()`; subsequent calls return 401 |
| TS-09 | Modify the `revoked_at` field to `now()` | Same — 401 |
| TS-10 | Token-length scan: try 8-char, 16-char, 32-char fake tokens | All return 401; no information about why (no "token too short" leak) |
| TS-11 | URL-encoded token attempt | If the dashboard ever URL-encoded a token (it shouldn't), confirm the n8n decoder rejects double-encoding |

**Pass criteria:** no P0 finding. TS-07 is informational — pin-by-IP is not in scope. TS-04, TS-05 leaks are P0 (would mean a service-role key shipped to clients).

---

### 3.4 Rate limiting (~45 min)

Today, rate limiting is **only** the lockout counter on `auth_users` (5 fails / 15 min / email). Cloudflare WAF rate limiting is part of the Phase 4 deliverable; document the target rules and verify they fire.

#### 3.4.1 Application-layer (already implemented)

| # | Case | Expected |
|---|---|---|
| RL-01 | 5 wrong-password attempts in 1 minute | 5th returns 423; `locked_until ≈ now+15min` |
| RL-02 | Lock auto-clears after 15 min on next correct password | 200; counter resets to 0 |
| RL-03 | Lock applies per email (different email keeps counting from 0) | Confirmed isolated |
| RL-04 | Lock counter resets on successful login mid-streak | After 3 fails + 1 success, counter is 0 |

#### 3.4.2 Cloudflare WAF rules to add

These are **target rules** to install during Phase 4. After installing, verify each fires.

| Rule | Path | Threshold | Action |
|---|---|---|---|
| `auth-login-rate`           | `/webhook/auth/login`                   | 10 / IP / minute | challenge (managed) |
| `auth-magic-link-rate`      | `/webhook/auth/magic-link`              | 5 / IP / 5 minutes | challenge |
| `auth-password-reset-rate`  | `/webhook/auth/password-reset-request` | 5 / IP / 5 minutes | challenge |
| `api-burst-protection`      | `/webhook/admin/*` and `/webhook/client/*` | 120 / token / minute | log + alert (do not block; would cause UX disruption from real heavy users) |
| `webhook-global-rate`       | `/webhook/*` | 1000 / IP / minute | block 60s |

| # | Case | Expected |
|---|---|---|
| RL-10 | Hit `/webhook/auth/login` 11× in 60s from a single IP | 11th request hits Cloudflare challenge page (HTML, not JSON) |
| RL-11 | Hit `/webhook/auth/login` from 11 different IPs in 60s | All succeed (per-IP rate limit, not global) |
| RL-12 | Burst 1500 requests/minute to `/webhook/admin/list-leads` from a single IP | After 1000 in a minute, Cloudflare returns 429 + 60s block; n8n protected from overload |

**Pass criteria:** RL-01..04 already pass (logic is in the migration). RL-10..12 require the Cloudflare WAF rules to be installed; verify each fires after install.

---

### 3.5 Audit log completeness (~30 min)

Auth-related events are captured in `auth_sessions` (issue, last_activity, revoke), `auth_users` (failed_login_attempts, locked_until, last_login_at), and `auth_magic_links` / `auth_password_resets` (issue + use timestamps).

A dedicated `admin_action_log` table for state-changing admin actions is **deferred** to Phase 4 implementation work. The audit-log webhook (`/webhook/admin/audit-log`) reads from it but tolerates the table being missing (returns empty array). Phase 4 work on this:

1. Author migration `2026-04-30-admin-action-log.sql` (4 columns: actor_email, action, target_type, target_id, occurred_at; service-role RLS).
2. Insert audit rows from each state-changing webhook (currently: client/settings, password-reset-complete; future: client onboarding state changes, manual lead reassignment).

| # | Case | Expected |
|---|---|---|
| AU-01 | Successful login | `auth_sessions` row inserted; `auth_users.last_login_at` set |
| AU-02 | Failed login | `auth_users.failed_login_attempts` incremented |
| AU-03 | Logout | `auth_sessions.revoked_at` set |
| AU-04 | Magic link issued + used | Two rows in `auth_magic_links` (issue, then `used_at` set) |
| AU-05 | Password reset complete | `auth_users.password_hash` change visible in DB write log; all prior sessions revoked |
| AU-06 | Client settings updated | (Phase 4 add) Row in `admin_action_log` with `action='client.settings.update'` |
| AU-07 | Audit log webhook returns recent sessions | Last 80 active sessions visible to admin only |

**Pass criteria:** every security-relevant event is recoverable from the database within 30 days. If AU-06 isn't yet implemented, that's a Phase 4 todo, not a P0.

---

### 3.6 Layout, accessibility, regression (~60 min)

#### 3.6.1 Cross-browser visual

Tested at 100% zoom on all listed sizes:

| Viewport | Browser | Pages |
|---|---|---|
| 1280×720 | Chrome / Edge / Firefox | every admin + client page |
| 1366×768 | same | same |
| 1440×900 | same | same |
| 1536×864 | same | same |
| 1920×1080 | same | same |
| 768×1024 (tablet) | Safari iOS sim | client dashboard only |
| 390×844 (iPhone) | Safari iOS sim | client dashboard only |

| # | Case | Expected |
|---|---|---|
| LR-01 | Each viewport renders sidebar/bottom-nav per breakpoint rules | per `client-dashboard/README.md` matrix |
| LR-02 | No horizontal scroll on any page above 90% zoom | confirmed |
| LR-03 | Tap targets ≥44px on mobile | DevTools "Show ruler on hover" check |
| LR-04 | Sidebar is sticky on desktop, drawer on mobile, with backdrop | drawer dismisses on backdrop click |
| LR-05 | Wide tables (admin/leads with 7 cols) scroll horizontally inside their card; the page itself does not | `clx-table-scroll` overflow works |

#### 3.6.2 Accessibility smoke

| # | Case | Expected |
|---|---|---|
| LR-10 | Keyboard tab order through login form | email → password → forgot link → submit → magic-link button (logical) |
| LR-11 | Screen reader (VoiceOver / NVDA) on overview | page title, KPI labels, table headers all announced |
| LR-12 | Focus rings visible on every focusable element | yes (`:focus { box-shadow }` on inputs) |
| LR-13 | Colour contrast on badges + text | WCAG AA on every badge variant — verify with DevTools "Contrast issues" |
| LR-14 | Form errors announced via `aria-live="polite"` | login error message wakes screen reader |

#### 3.6.3 Regression

| # | Case | Expected |
|---|---|---|
| LR-20 | Marketing site `crystallux.org` still loads, all anchor pages work | no 404s |
| LR-21 | Legacy dashboard at `crystallux-dashboard.pages.dev?token=$MASTER` still works | preserved per spec |
| LR-22 | Form intake from `crystallux.org/contact.html` still hits the legacy `clx-form-intake-v1` workflow | new lead arrives in `leads` table |
| LR-23 | Existing 50 workflows continue to run on schedule | n8n execution log shows green ticks for last 24h |

**Pass criteria:** LR-20..23 all pass — Phase 4 cannot have damaged existing infrastructure. LR-01..14 must produce zero P1 findings to ship clients.

---

### 3.7 End-to-end happy path (~30 min)

The full user journey from cold to active. Run twice — once as Mary, once as a client. No internal tooling — just a fresh browser.

#### 3.7.1 Mary first sign-in

1. Visit `https://crystallux.org/login.html`
2. Enter email + password → click "Sign in"
3. Land on `https://admin.crystallux.org/pages/overview.html`
4. KPI cards populate within 5 seconds
5. Open Workflows → see the n8n run summary
6. Open Clients → see at least one client
7. Open Audit Log → see her own active session
8. Settings → "Sign out" → land on `crystallux.org/login.html`
9. Refresh the admin dashboard — redirects to login (session revoked correctly)

#### 3.7.2 Client first sign-in

1. Magic-link email arrives (after Postmark/SendGrid is wired) OR Mary issues a temp password and shares it via secure channel
2. Visit `https://crystallux.org/login.html`
3. Enter email + password → "Sign in"
4. Land on `https://app.crystallux.org/pages/overview.html`
5. Greeting shows the client's email name, KPI cards populate
6. Tap Leads → see only their leads
7. Tap Bookings → see upcoming bookings
8. Tap Settings → toggle "Daily digest" → "Save"
9. Refresh — toggle stays on (write persisted)
10. Sign out → land on login

**Pass criteria:** both flows complete without console errors, with each step taking <3 seconds. Any unexpected redirect or error message is at minimum P1.

---

### 3.8 Soak test (~24 hours, passive)

After all suites above pass, leave both dashboards running with active sessions for 24 hours. Verify:

- Sessions auto-extend via `touch_session` (don't expire mid-soak)
- No memory leaks in either dashboard (DevTools Performance → Heap stays flat)
- n8n execution log has no unexpected 5xx
- Cloudflare analytics shows traffic flowing without WAF blocks against legitimate users

If anything trips during soak, that's a P1 worth fixing before client onboarding.

---

## 4. Test artefacts

Each suite produces:

- **Run log:** plain-text record of curl outputs + observed responses, dated and stored in `docs/deployment/test-runs/YYYY-MM-DD-phase-4-runs/`
- **Findings list:** Markdown table of (test_id, severity, summary, owner, status). Live document at `docs/deployment/test-runs/YYYY-MM-DD-findings.md`
- **Sign-off:** when all P0 = 0 and all P1 closed/accepted, Mary signs `PHASE_4_SIGN_OFF.md` (template TBD; one paragraph + date).

---

## 5. Order of execution

Run in this order. Subsequent suites assume prior suites passed.

```
3.1  Auth lifecycle               (gate to everything else)
  ↓
3.2  Cross-tenant isolation       (the P0 suite)
  ↓
3.3  Token security & storage
  ↓
3.4.1  Application-layer rate limit
  ↓
3.5  Audit log completeness
  ↓
3.4.2  Cloudflare WAF rules       (after install)
  ↓
3.6  Layout / a11y / regression
  ↓
3.7  End-to-end happy path
  ↓
3.8  24-hour soak
  ↓
Sign-off
```

Stop on any P0 — fix and re-run the failing suite plus 3.2 (always re-verify isolation after any auth/webhook change).

---

## 6. Tooling

- `curl` + `jq` — every API test
- Chrome / Edge / Firefox / Safari iOS sim — visual + network capture
- Supabase SQL Editor — direct DB assertions
- n8n execution log — workflow-level visibility
- Cloudflare analytics — WAF + traffic
- Optional: a small Node script (`scripts/phase4-runner.js` — to be authored at start of Phase 4) that runs §3.1 + §3.2 in CI-style and prints pass/fail per case. Defer until manual run shows everything green.

---

## 7. Out-of-band Phase 4 deliverables

These are not test cases but Phase 4 work that lands alongside testing:

1. Wire Postmark/SendGrid/SMTP into the magic-link + password-reset workflows. Today they return the click_url in the n8n node output as a placeholder.
2. Install the Cloudflare WAF rules from §3.4.2. Required for RL-10..12 to pass.
3. Author migration `2026-04-30-admin-action-log.sql` so the admin/audit-log webhook returns real action history.
4. Insert audit rows from `clx-client-settings`, `clx-auth-password-reset-complete`, and any future state-changing client webhooks.
5. Replace the Stripe customer portal placeholder with a real session URL minted via the Stripe API (touch in `clx-client-billing` Shape Response node).
6. Add `connect-src 'self' https://app.crystallux.org` and similar to n8n CORS response headers (today CORS is implicit because Cloudflare proxies; verify under cross-origin DevTools on the deployed dashboards).
7. Decide whether to retire the master-token URL access on the legacy `crystallux-dashboard.pages.dev` after sign-off, or keep it as a documented break-glass admin path.

These items are tracked but not gating for Phase 4 sign-off as long as the test suites above pass and the items have explicit owners + dates.
