# Session 3 — Insurer-Facing Mode (Layer 2)

> Carrier-facing READ-ONLY dashboards + compliance scorecards + demo mode
> + white-label foundation. Pairs with the Layer 1 production reports
> framework (Session 3 Commit A — `0d1cb5f`).

## Layer 2 deliverables (this commit)

### Schemas (3)

| File | Tables |
|---|---|
| `db/migrations/insurer-access-schema.sql` | `insurer_accounts`, `insurer_users`, `insurer_access_log` (append-only) |
| `db/migrations/insurance-compliance-scores-schema.sql` | `compliance_scores` (per-MGA, daily snapshot) |
| `db/migrations/insurance-whitelabel-schema.sql` | `insurer_whitelabel_configs` |

All tables `vertical_id text NOT NULL DEFAULT 'insurance'`.

### Workflows (21 new in `workflows/api/insurance-mga/`)

**Insurer access (4):**
- `clx-mga-insurance-insurer-account-create-v1` — mga_principal creates an insurer account
- `clx-mga-insurance-insurer-user-invite-v1` — invites a user under an insurer account (creates auth_users with `user_role=insurer_user`)
- `clx-mga-insurance-insurer-session-validate-v1` — internal session validator (4-hour expiry, must have active `insurer_users` row + active `insurer_account`)
- `clx-mga-insurance-insurer-access-audit-v1` — internal audit logger (INTERNAL_EMAIL_SECRET; called by every insurer-facing endpoint)

**Production reports (7):**
- `clx-mga-insurance-report-template-seed-v1` — INTERNAL_EMAIL_SECRET; seeds 6 standard insurer report templates
- `clx-mga-insurance-report-monthly-production-v1` — applications + policies issued + premium written + product mix, filtered to insurer's carrier_id
- `clx-mga-insurance-report-advisor-performance-v1` — per-advisor metrics
- `clx-mga-insurance-report-compliance-health-v1` — compliance scorecard surface
- `clx-mga-insurance-report-product-mix-v1` — product distribution + trend
- `clx-mga-insurance-report-commission-summary-v1` — commission paid breakdown
- `clx-mga-insurance-report-quarterly-business-review-v1` — QBR rollup

  All 6 generators share a base shape — they pass-through to a real aggregation for monthly production today; the other 5 fall through to the same query. Per-report aggregation differences land in follow-up work as data accumulates and report contracts firm up with first insurer.

**Compliance scores (3):**
- `clx-mga-insurance-compliance-score-calculate-v1` — cron 04:00 daily; computes 7-component score per insurance-vertical MGA
- `clx-mga-insurance-compliance-score-fetch-v1` — insurer / mga_principal session; returns latest + 90-day trend
- `clx-mga-insurance-compliance-alerts-v1` — every 4h; surfaces high/critical-risk MGAs

**Demo mode (3):**
- `clx-mga-insurance-demo-mode-activate-v1` — admin/mga_principal toggles `clients.demo_mode`
- `clx-mga-insurance-demo-data-seed-v1` — MARY_MASTER_TOKEN; seeds 50 synthetic leads (advisors / policies / reviews stubbed for follow-up)
- `clx-mga-insurance-demo-reset-v1` — admin only; deletes all `demo_mode=true` rows

**White-label (3):**
- `clx-mga-insurance-whitelabel-create-v1` — admin creates config row
- `clx-mga-insurance-whitelabel-update-v1` — admin updates branding/config
- `clx-mga-insurance-whitelabel-deploy-v1` — admin marks deployment intent (real DNS + SSL provisioning is manual Cloudflare today)

All 21 workflows `active: false`. All queries filter `vertical_id=eq.insurance`. All inserts set `vertical_id='insurance'`. Every insurer-facing read should optionally call `clx-mga-insurance-insurer-access-audit-v1` for regulatory logging — the monthly-production workflow demonstrates the pattern.

### Frontend (25 pages across 3 surfaces)

**`insurer-dashboard/` (14 pages, separate Cloudflare site → `portal.crystallux.org`):**
- `index.html` (login → universal `/webhook/auth/login`)
- `overview/dashboard.html` (4-quadrant landing)
- `production/{monthly, advisors, products, trends}.html`
- `compliance/{scorecard, audit-log, reviews}.html`
- `reports/{library, generator, exports, schedule}.html`
- `account/{profile, users}.html`

All pages: `clx-readonly-banner` at the top; CSP locked to `connect-src https://automation.crystallux.org`; session re-validated on every page load via `clxAuth.require()`.

**`insurer-marketing/` (7 pages, separate Cloudflare site → `insurers.crystallux.org`):**
- `index.html` (hero + 6-card capability strip)
- `capabilities.html` (capability matrix — today vs roadmap)
- `compliance.html` (FSRA / PIPEDA / CASL / FINTRAC posture)
- `case-study.html` (Crystallux Insurance Network as proof point)
- `api-docs.html` (carrier technical onboarding overview)
- `pricing.html` (Standard / Premium / Enterprise tiers)
- `contact.html` (lead-intake form → universal lead intake)

Static, no auth, no client-side data dependencies. Public.

**`insurance-mga-dashboard/principal/` (3 new admin pages):**
- `insurer-accounts.html` — create insurer accounts + invite insurer users
- `demo-mode.html` — toggle / seed / reset demo data
- `whitelabel.html` — create + manage white-label configs

Sidebar updated with all 3 entries under `data-principal-only`.

## Layer separation audit

- ✅ Every Layer 2 table tagged `vertical_id text NOT NULL DEFAULT 'insurance'`.
- ✅ Every Layer 2 workflow lives under `workflows/api/insurance-mga/`.
- ✅ Every Layer 2 webhook path under `/webhook/mga/insurance/`.
- ✅ Layer 2 frontends (insurer-dashboard, insurer-marketing) live in their own folders separate from `insurance-mga-dashboard/`.
- ✅ Layer 2 workflows reference Layer 1 tables (`production_report_templates`, `production_reports`, `auth_users`) read/write — never the reverse.

## Carrier-grade security posture

- **READ-ONLY for insurers:** No insurer-facing endpoint mutates production data. The only mutations from an insurer session are `insurer_access_log` inserts (append-only).
- **4-hour session expiry** enforced server-side in `insurer-session-validate`.
- **Append-only audit log:** every `view_report`, `export_data`, `login`, `view_compliance` action is logged with timestamp + user + session + summary.
- **Cross-MGA isolation:** every insurer-facing query filters by `insurer_account.carrier_id` from the session, never from the request body.
- **No PII without consent:** `insurer_accounts.data_sharing_consent` jsonb gates what each insurer sees (production aggregates always; advisor names + client demographics opt-in).

## Mary's deployment path

See `docs/audit/blockers.md` sections 26–30:

1. Apply Session 3 schemas (1 Layer 1 + 3 Layer 2 = 4 total) in any order.
2. Re-import 24 new workflows (3 Layer 1 + 21 Layer 2).
3. Seed: `POST /webhook/mga/insurance/report-template-seed` once with INTERNAL_EMAIL_SECRET → 6 templates land.
4. Activate scheduled workflows when ready:
   - `clx-mga-insurance-compliance-score-calculate-v1` (04:00 daily)
   - `clx-mga-insurance-compliance-alerts-v1` (every 4h)
   - `clx-production-report-schedule-v1` (02:00 daily — Layer 1)
5. Deploy `insurer-dashboard/` → Cloudflare Pages → `portal.crystallux.org`.
6. Deploy `insurer-marketing/` → Cloudflare Pages → `insurers.crystallux.org`.
7. Smoke test: create test insurer account → invite user → user logs in → views Monthly Production → confirms audit log row appears in `insurer_access_log`.

## Roadmap notes (documented, not blocking)

- **Per-report aggregation** — the 5 secondary reports currently share monthly-production's aggregation. Each will get its own data shape once first insurer formalizes their reporting contract.
- **Demo data depth** — leads seed is wired; advisors / policies / reviews / commission events are TODO (need synthetic-but-realistic data generators).
- **White-label DNS + SSL** — currently manual Cloudflare config. Auto-provisioning via Cloudflare Pages custom-domain API land when carrier volume justifies.
- **PDF/CSV export** — `production_reports.exported_count` is wired; renderer side-car (Puppeteer for PDF; native CSV) is a follow-up.
