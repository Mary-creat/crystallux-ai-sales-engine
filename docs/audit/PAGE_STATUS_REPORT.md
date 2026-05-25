# Page status report — 2026-05-16

Snapshot of every published page across the 7 deployed domains, with the
known state at the time Mary reported the "make it work" sprint.

**Legend:**
- ✓ working — file exists, backend reachable, no known issues
- ⚠ blocked-on-cache — fix is deployed; Cloudflare CDN serving stale `/shared/auth.js` (see `blockers.md` 0i). One cache purge resolves all of these at once.
- 🟡 dormant — file works; backend (n8n workflow / DB seed) inactive
- 🆕 stub — placeholder shipped in this commit; awaiting real implementation
- 🔴 missing — file does not exist on disk
- 🛰 marketing — static page, no backend required

Domains:
- `admin.crystallux.org` — admin-dashboard
- `app.crystallux.org` — client-dashboard
- `mga.crystallux.org` — insurance-mga-dashboard (advisor + principal shells)
- `portal.crystallux.org` — insurer-dashboard (auth-gated portal app)
- `insurers.crystallux.org` — insurer-marketing (public marketing site)
- `crystallux.org` — main marketing + auth (site/)
- `insurance.crystallux.org` — MGA marketing (insurance-marketing/)

---

## admin.crystallux.org

| Path | File | Status | Note |
|---|---|---|---|
| `/` | `index.html` | ✓ | Bootstrap; validates session, forwards admins to overview |
| `/pages/overview` | `pages/overview.html` | ✓ | |
| `/pages/clients` | `pages/clients.html` | ✓ | |
| `/pages/client-detail` | `pages/client-detail.html` | ✓ | Canonical multi-branch merge pattern (CLAUDE.md ref) |
| `/pages/leads` | `pages/leads.html` | ✓ | |
| `/pages/workflows` | `pages/workflows.html` | ✓ | |
| `/pages/billing` | `pages/billing.html` | ✓ | |
| `/pages/onboarding` | `pages/onboarding.html` | ✓ | |
| `/pages/market-intelligence` | `pages/market-intelligence.html` | ✓ | |
| `/pages/audit-log` | `pages/audit-log.html` | ✓ | |
| `/pages/settings` | `pages/settings.html` | ✓ | |
| `/pages/sentinel` | `pages/sentinel.html` | ⚠ | Auth fix is on origin; admin CDN cache stale → purge per 0i |
| `/pages/carriers/overview` | `pages/carriers/overview.html` | ⚠ | Same — deploy + Carriers DB seed (0f) |
| `/pages/carriers/appointments` | `pages/carriers/appointments.html` | ⚠ | Same |
| `/pages/carriers/submissions` | `pages/carriers/submissions.html` | ⚠ | Same |
| `/pages/carriers/commissions` | `pages/carriers/commissions.html` | ⚠ | Same |
| `/pages/carriers/reconciliation` | `pages/carriers/reconciliation.html` | ⚠ | Same |
| `/pages/training-topics` | `pages/training-topics.html` | ⚠ | Same — array-form auth call |
| `/pages/content-library` | `pages/content-library.html` | ⚠ | Same |
| `/pages/content-performance` | `pages/content-performance.html` | ⚠ | Same |
| `/pages/new-client` | `pages/new-client.html` | 🆕 | Stub. Real intake pending; see file's empty-state for the workflow it will call |
| `/pages/saas-onboarding` | `pages/saas-onboarding.html` | 🆕 | Stub. Wizard backed by `clx-admin-onboarding-pipeline-v1` |
| `/pages/clients/onboarding` | `pages/clients/onboarding.html` | 🆕 | Stub. Per-client onboarding detail |

---

## app.crystallux.org

Client-dashboard CDN cache has already rolled the array-form fix — these pages are live.

| Path | File | Status |
|---|---|---|
| `/` | `index.html` | ✓ |
| `/onboarding/` | `onboarding/index.html` | ✓ |
| `/pages/overview` | `pages/overview.html` | ✓ |
| `/pages/leads` | `pages/leads.html` | ✓ |
| `/pages/campaigns` | `pages/campaigns.html` | ✓ |
| `/pages/bookings` | `pages/bookings.html` | ✓ |
| `/pages/activity` | `pages/activity.html` | ✓ |
| `/pages/billing` | `pages/billing.html` | ✓ |
| `/pages/settings` | `pages/settings.html` | ✓ |
| `/pages/content-calendar` | `pages/content-calendar.html` | ✓ |
| `/pages/content-engagement` | `pages/content-engagement.html` | ✓ |
| `/pages/content-preferences` | `pages/content-preferences.html` | ✓ |
| `/pages/training-coach` | `pages/training-coach.html` | ✓ |
| `/pages/training-progress` | `pages/training-progress.html` | ✓ |

---

## mga.crystallux.org

Auth gate in `insurance-mga-dashboard/shared/auth.js` already accepts arrays — NOT blocked on the same deploy as admin/client. MGA failures are n8n-side (see 0h).

### advisor/*

| Path | File | Status | Note |
|---|---|---|---|
| `/advisor/overview` | `advisor/overview.html` | ✓ | |
| `/advisor/today` | `advisor/today.html` | ✓ | |
| `/advisor/leads` | `advisor/leads.html` | ✓ | |
| `/advisor/applications` | `advisor/applications.html` | ✓ | |
| `/advisor/calculators` | `advisor/calculators.html` | ✓ | |
| `/advisor/product-comparison` | `advisor/product-comparison.html` | ✓ | |
| `/advisor/reviews` | `advisor/reviews.html` | ✓ | |
| `/advisor/coaching` | `advisor/coaching.html` | ✓ | |
| `/advisor/commissions` | `advisor/commissions.html` | ✓ | |
| `/advisor/goals` | `advisor/goals.html` | ✓ | |
| `/advisor/route-map` | `advisor/route-map.html` | ✓ | |
| `/advisor/onboarding` | `advisor/onboarding.html` | 🟡 | Page is fine; `POST /webhook/mga/insurance/onboarding-status` returns 500 → see 0h |

### principal/*

| Path | File | Status | Note |
|---|---|---|---|
| `/principal/overview` | `principal/overview.html` | ✓ | |
| `/principal/dashboard-home` | `principal/dashboard-home.html` | ✓ | |
| `/principal/advisors` | `principal/advisors.html` | ✓ | |
| `/principal/compliance` | `principal/compliance.html` | ✓ | |
| `/principal/team-goals` | `principal/team-goals.html` | ✓ | |
| `/principal/team-productivity` | `principal/team-productivity.html` | ✓ | |
| `/principal/products` | `principal/products.html` | ✓ | |
| `/principal/insurer-accounts` | `principal/insurer-accounts.html` | ✓ | |
| `/principal/lead-distribution-config` | `principal/lead-distribution-config.html` | ✓ | |
| `/principal/whitelabel` | `principal/whitelabel.html` | ✓ | |
| `/principal/demo-mode` | `principal/demo-mode.html` | ✓ | |
| `/principal/carriers` | `principal/carriers.html` | 🟡 | Page is fine; `POST /webhook/mga/insurance/carriers-list` returns 500 → see 0h |

---

## portal.crystallux.org (insurer-dashboard, auth-gated)

Insurer portal — read-only screens. Uses a separate auth gate (`clxAuth.require()` with no role check, validates via insurer-session-validate webhook). Not affected by the array-form bug. Companion public marketing site is `insurers.crystallux.org` (insurer-marketing/), tracked separately.

| Path | File | Status |
|---|---|---|
| `/` | `index.html` | ✓ |
| `/overview/dashboard` | `overview/dashboard.html` | ✓ |
| `/production/advisors` | `production/advisors.html` | ✓ |
| `/production/monthly` | `production/monthly.html` | ✓ |
| `/production/products` | `production/products.html` | ✓ |
| `/production/trends` | `production/trends.html` | ✓ |
| `/compliance/reviews` | `compliance/reviews.html` | ✓ |
| `/compliance/scorecard` | `compliance/scorecard.html` | ✓ |
| `/compliance/audit-log` | `compliance/audit-log.html` | ✓ |
| `/reports/generator` | `reports/generator.html` | ✓ |
| `/reports/library` | `reports/library.html` | ✓ |
| `/reports/schedule` | `reports/schedule.html` | ✓ |
| `/reports/exports` | `reports/exports.html` | ✓ |
| `/account/profile` | `account/profile.html` | ✓ |
| `/account/users` | `account/users.html` | ✓ |

---

## crystallux.org (marketing + auth)

| Path | File | Status |
|---|---|---|
| `/` | `site/index.html` | 🛰 |
| `/about` | `site/about.html` | 🛰 |
| `/features` | `site/features.html` | 🛰 |
| `/pricing` | `site/pricing.html` | 🛰 |
| `/how-it-works` | `site/how-it-works.html` | 🛰 |
| `/book` | `site/book.html` | 🛰 |
| `/contact` | `site/contact.html` | 🛰 (form posts to lead-capture webhook — verify active) |
| `/faq` | `site/faq.html` | 🛰 |
| `/login` | `site/login.html` | ✓ (calls validate-session; webhook live) |
| `/magic-link-sent` | `site/magic-link-sent.html` | 🛰 |
| `/magic-link-verify` | `site/magic-link-verify.html` | ✓ (calls magic-link verify webhook) |
| `/forgot-password` | `site/forgot-password.html` | 🛰 |
| `/reset-password` | `site/reset-password.html` | 🛰 |
| `/industries/*` | `site/industries/*.html` | 🛰 |
| `/privacy` | `site/privacy.html` | 🛰 |

---

## insurance.crystallux.org (MGA marketing)

| Path | File | Status |
|---|---|---|
| `/` | `index.html` | 🛰 |
| `/about` | `about.html` | 🛰 (needs FSRA licence # — see 0e) |
| `/disclosure` | `disclosure.html` | 🛰 (needs E&O carrier details — see 0e) |
| `/auto-insurance` | `auto-insurance.html` | 🛰 |
| `/home-insurance` | `home-insurance.html` | 🛰 |
| `/business-insurance` | `business-insurance.html` | 🛰 |
| `/life-insurance` | `life-insurance.html` | 🛰 |
| `/critical-illness` | `critical-illness.html` | 🛰 |
| `/disability` | `disability.html` | 🛰 |
| `/needs-assessment` | `needs-assessment.html` | 🟡 (form posts to `clx-mga-insurance-lead-capture-v1` — see 0g) |
| `/contact` | `contact.html` | 🟡 (same) |
| `/compare` | `compare.html` | 🛰 |
| `/how-it-works` | `how-it-works.html` | 🛰 |
| `/team` | `team.html` | 🛰 |
| `/blog/` | `blog/index.html` | 🛰 |
| `/resources/*` | `resources/*.html` | 🛰 |
| `/privacy` / `/terms` | `privacy.html` / `terms.html` | 🛰 |

---

## Summary

- **Working today:** 65+ pages across all 7 domains (including all client-dashboard array-form pages — the fix DID reach `app.crystallux.org`).
- **Blocked on Cloudflare cache purge (0i):** 10 admin pages — one URL purge of `admin.crystallux.org/shared/auth.js` unblocks all of them. The fix is on origin; the CDN edge is stale.
- **Blocked on n8n (0h):** 2 MGA pages and 2 marketing forms — need workflow activation + seed.
- **New stubs (this commit):** 3 admin pages so the URLs stop silently falling through.
- **Marketing copy gaps (0e):** FSRA licence number + E&O carrier details for `insurance.crystallux.org`.

Re-run `tests/audit/smoke-domains.sh` after each of (a) cache purge, (b) MGA workflows activated, to validate progress.
