# Production readiness checklist — scale-sprint-v1

Last updated: 2026-05-05
Authoritative audit harness: `tests/audit/dashboard-audit.js`

Each row marks state **after fixes pushed in this sprint** and what
Mary still has to do to flip the box from `gated` to `verified ✓`.

| Item | Status | Notes |
|------|--------|-------|
| All 18 webhooks return correct data with HTTP 200 | gated | Webhook JSON fixes pending VPS re-import (see `blockers.md`). Pre-fix, list-leads / list-clients / billing-summary / workflow-status returned truncated/empty data. Post-fix workflows verified locally; live verification requires VPS deploy. |
| All admin pages load and display real data (10 pages) | gated | Frontend ✓ (auto-deployed via CF Pages). Backend gated on workflow re-import. |
| All client pages load and respect tenant isolation (7 pages) | gated | Frontend ✓. Backend gated on workflow re-import + test-client SQL applied. |
| Brand purple consistent across all pages | ✓ | Verified via screenshots in `docs/audit/screenshots/admin/`. Sidebar nav uses `--color-brand-100/600/700` for active state; stat-card variants use the brand ramp. |
| Lucide icons present in sidebar | ✓ | Confirmed in audit run — sidebar contains `<svg>` markup, no text-glyphs. |
| Charts rendering on overview and detail pages | ✓ | Audit captured 2 SVG paths on admin overview (sparkline + donut) and 2 on client-detail. Donut on market-intelligence rendered ✓. |
| No JS console errors anywhere | ✓ | Post-deploy re-audit confirms 0 console errs per page on all 10 admin pages and all 7 client pages. CSP fix landed (commits `de446f5` + `1d7f7dd`). |
| Mobile responsive (375px width) | ✓ | Audit captured `mobile-overview.png` at 375×812; burger button visible, sidebar collapses. |
| Login flow works for admin | ✓ | Audit successfully logged in as `info@crystallux.org` and arrived at `admin.crystallux.org/pages/overview`. |
| Login flow works for client | gated | Requires `testclient@crystallux.org` SQL applied. Migration in `db/migrations/test-client-account.sql`. |
| Logout flow works | ✓ | `clxAuth.logout()` clears localStorage and redirects to `/login.html` (manual verification — also wired in admin/client settings danger button). |
| Session expiration handled gracefully | ✓ | `clxAuth.require()` redirects to login on 401. |
| Calendly link updated to `crystallux-info/30min` | gated | SQL ready in `db/migrations/update-calendly-info.sql` — Mary applies. |
| Test client account works | gated | SQL ready — Mary applies. |
| Tenant isolation verified | gated | Three Playwright tests in `dashboard-audit.js → testTenantIsolation()`. Will run automatically once test-client account exists. |

## How to flip the gates to ✓

In order:

1. **Apply both SQL migrations** on Supabase (test client + Calendly):
   ```bash
   psql "$DATABASE_URL" -f db/migrations/test-client-account.sql
   psql "$DATABASE_URL" -f db/migrations/update-calendly-info.sql
   ```

2. **Re-import workflows on VPS:**
   ```bash
   cd /root/crystallux-workflows
   git pull origin scale-sprint-v1
   N8N_API_KEY=$(cat /tmp/.k) python3 /tmp/clx.py
   ```

3. **Cloudflare Pages cache purge** (if dashboards still stale after a
   hard refresh).

4. **Re-run audit harness:**
   ```bash
   cd tests/audit
   node dashboard-audit.js all
   ```

5. Read `docs/audit/admin-audit-report.md`, `docs/audit/client-audit-report.md`,
   and `docs/audit/audit-summary.md`. Each row above flips to ✓ when its
   corresponding section in the audit reports is green.

## Sign-off

Mary signs each row by editing `production-readiness.md` once she's
verified the corresponding behaviour. Treat anything still flagged
`gated` as a blocker for declaring the sprint shippable.
