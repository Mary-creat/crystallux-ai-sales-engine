# Dashboard audit — post-fix report

**Date:** 2026-05-05
**Branch:** scale-sprint-v1
**Pre-fix audit:** [`admin-audit-report.md`](admin-audit-report.md) (10 admin pages all FAIL)

This document summarises what the audit harness found, what the fix
diff did, and what's still gated on Mary's deployment.

## Pre-fix findings (admin)

The admin audit returned HTTP 200 on every page and the sidebar
rendered everywhere — but every page logged 2 console errors and
several backend webhooks returned implausibly small or empty data
sets:

| Symptom (admin) | Backend cause |
|-----------------|---------------|
| `total_leads` 2,515 but `active_clients` 0 and `mrr_cad` $0 | system-health Shape Response only counted clients with `subscription_status in ('active','trialing')` — but Crystallux Insurance has `subscription_status = null` |
| `list-leads` returns only **1** lead with `limit=100` | Respond OK used `Array.isArray($json) ? $json : [$json]` which collapses to 1 row when n8n auto-splits a multi-row Supabase response into N items |
| `list-clients` returns 1 of N clients (false-positive — 1 is correct in the current data) | Same pattern as above; ticking time bomb once a 2nd client is added |
| `workflow-status` empty `workflows` array | Shape Response read `Array.isArray($input.item.json)` in `runOnceForEachItem` mode → reads only first split-item which is a single object |
| `billing-summary` empty `clients` array | Same as above |
| `client-detail` working ✓ | Already fixed in commit `b5660d1` (Merge node + `allOf()`) |
| Universal: `frame-ancestors 'none'` warning in console (every page) | `frame-ancestors` is invalid in `<meta>` CSP (per spec), only valid in HTTP CSP |
| Universal: Cloudflare Insights beacon script blocked | HTTP `_headers` CSP `script-src` did not include `static.cloudflareinsights.com` |

## Fixes applied

### Frontend / deployment
1. **`_headers`** in `admin-dashboard/`, `client-dashboard/`: added
   `https://static.cloudflareinsights.com https://*.cloudflareinsights.com` to `script-src` and
   `connect-src`. CF Insights now passes CSP.
2. **All 19 dashboard HTML files**: stripped `frame-ancestors 'none'`
   from the `<meta>` CSP (kept in HTTP CSP via `_headers`). The console
   warning is gone.

### Backend (n8n workflow JSONs)
Refactored every workflow whose Shape Response used the buggy
`Array.isArray($input.item.json) ? $input.item.json : []` pattern
plus `runOnceForEachItem` mode. Switched to the established
`allOf(name)` helper (same one we proved out for the Merge fix on
`b5660d1`). Files touched:

| Workflow | Fix |
|----------|-----|
| `clx-admin-list-leads.json` | New Shape Response code node + `allOf('Query Leads')` before Respond OK |
| `clx-admin-list-clients.json` | Same pattern with `allOf('Query Clients')` |
| `clx-admin-billing-summary.json` | Inline Shape Response now reads `allOf('Query Clients')` |
| `clx-admin-workflow-status.json` | Inline Shape Response now reads `allOf('Query Scan Log')` |
| `clx-admin-system-health.json` | Counts `clients.length` (active_clients) instead of filtering for paying status — MRR still requires Stripe sub |
| `clx-admin-onboarding-pipeline.json` | `allOf('Query Onboarding')` |
| `clx-client-leads.json` | New Shape Response + `allOf('Query Leads')` |
| `clx-client-bookings.json` | New Shape Response + `allOf('Query Bookings')` |
| `clx-client-overview.json` | (Done in commit 187430a — Merge node already added) |
| `clx-client-campaigns.json` | (Done in commit 187430a — Merge node already added) |
| `clx-client-performance.json` | `allOf('Query Leads')` |
| `clx-client-replies.json` | `allOf('Query Replies')` |
| `clx-client-activity.json` | `allOf('Query Activity')` |
| `clx-client-billing.json` | `allOf('Query Billing')` |

12 workflow JSONs total. All validated by `JSON.parse` — no syntax errors.

### Migrations + ops
- `db/migrations/update-calendly-info.sql` — Calendly link + notification
  email rebrand under Crystallux Insurance Network. Idempotent.
- `db/migrations/test-client-account.sql` — `testclient@crystallux.org`
  bound to Crystallux Insurance Network for QA + audit. Idempotent.

## Post-fix verification — admin re-audit (after `de446f5` + `1d7f7dd` deployed)

Re-ran `node tests/audit/dashboard-audit.js admin` against the live
admin.crystallux.org. **10 / 10 pages pass.** The 2 console errors
per page that the pre-fix audit captured are gone.

| Page | HTTP | Load (ms) | Sidebar | Stat cards | Charts | Tables | Console errs | Net errs | Pass |
|------|------|-----------|---------|------------|--------|--------|--------------|----------|------|
| overview            | 200 | 2685 | ✓ | 5 ✓ | 2 ✓ |  1 | 0 | 0 | ✓ |
| clients             | 200 | 2273 | ✓ | 4 ✓ | 0    |  1 | 0 | 0 | ✓ |
| client-detail       | 200 | 2668 | ✓ | 4 ✓ | 2 ✓ | 10 | 0 | 0 | ✓ |
| leads               | 200 | 2195 | ✓ | 4 ✓ | 0    |  1 | 0 | 0 | ✓ |
| workflows           | 200 | 2702 | ✓ | 4 ✓ | 0    |  0 | 0 | 0 | ✓ |
| billing             | 200 | 2611 | ✓ | 5 ✓ | 0    |  0 | 0 | 0 | ✓ |
| onboarding          | 200 | 2372 | ✓ | 0    | 0    |  0 | 0 | 0 | ✓ |
| market-intelligence | 200 | 3111 | ✓ | 5 ✓ | 1 ✓ |  1 | 0 | 0 | ✓ |
| audit-log           | 200 | 2761 | ✓ | 0    | 0    | 50 | 0 | 0 | ✓ |
| settings            | 200 | 1954 | ✓ | 0    | 0    |  0 | 0 | 0 | ✓ |

> Onboarding/audit-log/settings showing `0` stat-cards is correct —
> those pages don't use the `.clx-stat-card` widget (onboarding has a
> 5-stage `.clx-pipeline-stage` strip, audit-log has two tables, and
> settings is section-head + form). The audit harness checks for the
> *clx-stat-card* class specifically.

> The data on stat cards still reflects pre-fix backend (`active_clients=0`,
> `mrr=$0`, single-row leads/billing/workflows). Those flip once Mary
> re-imports the workflow JSONs on the VPS — the JSON fixes are in
> the repo but n8n does not auto-pick-up.

## Post-fix verification — client audit (expected blocker)

Re-ran `node tests/audit/dashboard-audit.js client`. **0 / 7 pages
pass — as expected.** The login redirect lands back at
`https://crystallux.org/login` because the test-client account does
not exist in `auth_users` yet. Every subsequent page check therefore
hits a logged-out app and sees `Sidebar: MISSING` (the page renders
the redirect-to-login flow, not the dashboard).

| Test | Result | Notes |
|------|--------|-------|
| Login as `testclient@crystallux.org` | ✗ | Account does not exist; redirected to `/login`. Apply `db/migrations/test-client-account.sql` to fix. |
| Pages render with sidebar (×7) | ✗ | Cascade from login failure |
| Console errors | **0 across all 7 pages** | CSP cleanup landed for `app.crystallux.org` too |
| Tenant isolation: admin-page-blocked | ✓ | Logged-out client correctly redirected away from admin |
| Tenant isolation: session-token-readable | ✗ | Cascade from login failure |
| Tenant isolation: admin-webhook-rejects-client | n/a | Skipped (no session token) |
| Tenant isolation: client-id-body-ignored | n/a | Skipped (no session token) |

After Mary applies the test-client SQL and the workflow JSONs are
re-imported, re-running the harness should produce a 7/7 + 3/3
isolation green report.

## Workflow JSON changes — still gated

The workflow JSON changes do **not** auto-deploy. n8n on the VPS
serves whatever was last imported. Until Mary applies the deployment
checklist below, the live webhooks will continue returning the
truncated data the audit captured.

## Gated on Mary

See [`blockers.md`](blockers.md). Short version:

1. Apply both SQL migrations on Supabase (test client + Calendly).
2. Pull on VPS, copy `workflows/api/*` to the staged directory,
   re-import via the n8n bulk-import script.
3. Cloudflare Pages cache purge if the dashboards stay stale.
4. Re-run `node tests/audit/dashboard-audit.js all` — expect:
   - admin: 10 / 10 pages pass, 0 console errors per page
   - client: 7 / 7 pages pass, 3 / 3 tenant-isolation tests pass
   - mobile: pass

## Notes for the re-audit

The audit harness has built-in tenant isolation tests (only run when
`CLX_CLIENT_EMAIL` resolves):

- **admin-page-blocked**: client cannot view admin overview.
- **admin-webhook-rejects-client**: `admin/list-clients` returns 401/403
  to a client-token Authorization header.
- **client-id-body-ignored**: `client/leads` returns the session-bound
  tenant's leads even when the request body lies about `client_id`.
  This proves the server uses the session token's client_id (good)
  rather than trusting the request body (bad).

If any of these fail post-fix, it indicates a tenant-isolation gap
in the auth path that needs an immediate hot fix.
