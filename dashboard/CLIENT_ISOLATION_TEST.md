# Client Isolation Test Protocol

**Purpose:** verify that a client-role dashboard user (URL with `client_id` + `dashboard_token`) sees only their own data and cannot view other clients' rows, even under adversarial URL manipulation.

**Runs:** after applying `2026-04-24-dashboard-rls-hardening.sql` and deploying the updated `dashboard/index.html` with Phase 2 `clxScopeUrl()` wrapper.

**Executor:** Mary, manually, before inviting the first client to access their dashboard URL.

---

## Prerequisites

- Two test clients in Supabase:
  - **Client A:** `client_name='Isolation Test A'`, a known `client_id` (e.g., `aaaa...`), a known `dashboard_token`, ≥3 leads owned
  - **Client B:** `client_name='Isolation Test B'`, separate `client_id` (e.g., `bbbb...`), separate `dashboard_token`, ≥3 leads owned
- Mary's `MARY_MASTER_TOKEN` available for admin-mode verification
- Dashboard reachable via `https://crystallux.org/dashboard` (or local dev URL)

---

## Test cases

### Test 1 — Client A loads with own credentials (happy path)

**URL:**
```
https://crystallux.org/dashboard?client_id=<CLIENT_A_UUID>&token=<CLIENT_A_DASHBOARD_TOKEN>
```

**Expected:**
- Client context banner displays "Welcome, Isolation Test A"
- Admin banner is NOT visible
- `window.CLX_ROLE === 'client'` (check in browser DevTools console)
- `window.CLX_CLIENT_ID` matches Client A's UUID
- Every panel shows only Client A's data (Recent Leads, Recent Emails, Pipeline Stats)
- Billing panel shows Client A's subscription only
- Channels Active panel shows Client A's configured channels only
- `Client Performance` admin panel is hidden or empty (admin-only)

**Pass criteria:** Client A's leads visible; no Client B leads visible anywhere in the DOM.

---

### Test 2 — Client A tries to view Client B's data (URL swap attack)

**URL (malicious):**
```
https://crystallux.org/dashboard?client_id=<CLIENT_B_UUID>&token=<CLIENT_A_DASHBOARD_TOKEN>
```

**Expected:**
- Client context banner displays "Invalid token" (line 671 of index.html catches token/client mismatch)
- Dashboard sections load but display no data (RLS blocks the anon-key reads; `clxScopeUrl` forces `client_id=eq.CLIENT_B_UUID` which doesn't match the token, so RLS returns zero rows if the new anon-read policy is tightened)
- No Client A data visible (the URL said "I am Client B")
- No Client B data visible (token doesn't match)

**Pass criteria:** No leads, emails, or billing data from either client appear in the DOM.

---

### Test 3 — Client A tries to drop client_id to reach admin-like view

**URL (malicious):**
```
https://crystallux.org/dashboard?token=<CLIENT_A_DASHBOARD_TOKEN>
```

**Expected:**
- Role detection classifies this as `admin` (token alone → admin per Phase 1 logic)
- Client A's dashboard_token is NOT the `MARY_MASTER_TOKEN`, so the server-side verify-access workflow (once active) would reject
- While verify-access is dormant (Phase 1 ships active:false), the current behaviour is: role flips to `admin`, queries omit `client_id` filter, and results depend entirely on the Supabase service_role key in the browser
- If the browser has Mary's service_role key in Settings (expected for Mary herself), the URL would show full admin data — but only Mary has that key; Client A does not

**Pass criteria:** Client A does not have the Supabase service-role anon key and therefore their anon-key requests return zero rows from hardened tables after this migration.

**Important hardening note:** until `clx-verify-dashboard-access-v1` is activated and the dashboard calls it before rendering, a malicious client who somehow obtains the Supabase service-role key could bypass all client-side checks. The service-role key is the single most sensitive credential and must never be distributed to clients.

---

### Test 4 — Client A submits raw PostgREST query bypassing the wrapper

**Scenario:** Client A opens browser DevTools and runs:
```javascript
fetch(SUPABASE_URL + '/rest/v1/leads?client_id=eq.<CLIENT_B_UUID>&select=*', { headers: supabaseHeaders() })
  .then(r => r.json()).then(console.log);
```

**Expected (after RLS hardening):**
- If the browser is using the service-role key: query returns Client B's leads (service_role bypasses RLS — this is why the service_role key must never leave Mary's hands)
- If the browser is using the anon key: query returns zero rows (anon role has REVOKE SELECT on `leads` after this migration)

**Pass criteria:** anon-key users cannot query hardened tables at all. Service-role users (only Mary) can query everything.

---

### Test 5 — Admin mode (Mary)

**URL:**
```
https://crystallux.org/dashboard?token=<MARY_MASTER_TOKEN>
```

**Expected:**
- `window.CLX_ROLE === 'admin'`
- Admin banner visible
- All client data visible across all clients
- Billing panel shows MRR summary
- Channels Active panel shows all clients
- `clxScopeUrl` passes URLs through without appending `client_id` filter

**Pass criteria:** full platform visibility for Mary.

---

### Test 6 — Guest mode (no credentials)

**URL:**
```
https://crystallux.org/dashboard
```

**Expected:**
- `window.CLX_ROLE === 'guest'`
- Current behaviour: dashboard shell loads, queries attempt to run with whatever Supabase key is in sessionStorage (possibly Mary's, possibly empty)
- After future Phase 3 navigation ships with guest-mode access-denied page: dashboard shows a "Please sign in" message and hides all panels

**Pass criteria (today):** no client data leaks if no Supabase key is in sessionStorage. **Pass criteria (future):** access-denied screen displayed, no panels render.

---

### Test 7 — Ops mode (future, dormant)

**URL:**
```
https://crystallux.org/dashboard?token=<CLX_OPS_TOKEN>&ops=1
```

**Expected:**
- `window.CLX_ROLE === 'ops'` (once ops role is wired in Phase 3 navigation)
- Today: no ops-specific UI; panels load identically to admin
- Future: ops sidebar shows support-scoped views, cannot access platform-settings or billing admin

**Pass criteria (today):** role classified as `ops`; no errors. **Pass criteria (future):** ops-scoped views only.

---

## Execution log template

Record results each time the test is run (e.g., after a RLS policy change, after an index.html update affecting queries).

```
Date: YYYY-MM-DD
Executed by: Mary
Dashboard URL: https://crystallux.org/dashboard
Migration in effect: 2026-04-24-dashboard-rls-hardening.sql

Test 1 (Client A happy path):    PASS / FAIL
Test 2 (URL swap attack):         PASS / FAIL
Test 3 (Drop client_id):          PASS / FAIL
Test 4 (Raw anon fetch):          PASS / FAIL
Test 5 (Admin mode):              PASS / FAIL
Test 6 (Guest mode):              PASS / FAIL
Test 7 (Ops mode):                PASS / FAIL (expected: role classified, not fully wired yet)

Notes / observations:
- [any deviation from expected behaviour]
- [any data leak — red-flag, investigate immediately]
- [any browser console errors]

Remediation required:
- [if any failures, describe the fix]
```

---

## Triggers to re-run this test

Re-execute the full test suite any time:

1. A new migration affects the `leads`, `outreach_log`, `clients`, `campaigns`, `appointment_log`, or any other hardened table
2. A new panel is added to the dashboard
3. The `clxScopeUrl` / `clxFetch` helpers are modified
4. A new role is added or an existing role's scope changes
5. Supabase anon role permissions are modified
6. Before onboarding a new client for the first time
7. Quarterly as a standing security review

---

## Known-limitation disclosures

To flag for future hardening:

- **Anon-key token comparison.** The current flow at line 664 of `index.html` reads `clients.dashboard_token` via anon access to verify the URL-supplied token. This means a determined adversary can enumerate `dashboard_token` values via `clients?dashboard_token=like.*` queries. Mitigation: (a) dashboard_tokens are 32-byte random strings, (b) the anon role's `clients_anon_read_for_token_verify` policy limits access to rows `WHERE dashboard_token IS NOT NULL`. Longer-term mitigation: server-side verification via `clx-verify-dashboard-access-v1` workflow makes the anon-read unnecessary.

- **Service-role key sharing.** Mary pastes the Supabase service-role key into the dashboard's Settings pane. If any client-scoped user somehow obtains that key (shoulder-surfing, stolen laptop, phishing), the entire RLS model is bypassed. Mitigation: service-role key lives only in Mary's browser; client users use dashboard_token only, which grants anon-level DB access post-this-migration (meaning zero rows from hardened tables).

- **Client context banner exposure.** Line 664 returns `id, client_name, client_slug, vertical, dashboard_token` in anon-readable response. The dashboard_token field in the response is not rendered to the UI but is available via DevTools inspection. Minimise exposure by restricting the select clause to `id, client_name, client_slug, vertical` in the verify step once the server-side workflow is live.

---

## Decision log

**Why anon-SELECT on `clients` is retained:** the current token-verify flow requires it. Removing the anon policy would force an immediate switch to server-side verification, which is Phase 1's scaffolded-but-dormant workflow. That switch is the correct long-term fix; this migration tees it up.

**Why RLS-only isn't sufficient alone:** the dashboard queries are joined in one browser session using Mary's service-role key. For client-role users (who don't have the service-role key), RLS *is* sufficient — but the `clxScopeUrl` wrapper is defence-in-depth so even a Mary-role mistake (e.g., accidentally loading the client URL while having the service-role key cached) doesn't expose other clients' data.

**Why ops role uses the admin token for now:** no operational need for a separate ops token until the first VA is hired. The `CLX_OPS_TOKEN` env variable exists as a hook for that future hire; until then, `?ops=1` with the admin token scopes the dashboard to ops-view without granting admin-panel access.
