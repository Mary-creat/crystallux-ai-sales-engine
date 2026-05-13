# MGA Marketing Website — Roadmap

> **Status:** Phase 1 — Marketing Foundation BUILT 2026-05-13 (`insurance-marketing/` folder, 21 pages, lead-capture workflow shipped).

## Site identity

- **URL:** `insurance.crystallux.org` (subdomain on `crystallux.org`)
- **Brand:** Crystallux Insurance Network — Mary's MGA. **Separate brand** from the Crystallux SaaS site at `crystallux.org` and the Crystallux admin/client dashboards.
- **Audience:** B2C Canadian insurance buyers (and SMBs for the business-insurance line).
- **Goal:** Lead capture → advisor consultation → policy placement.

## Phase 1 — Marketing Foundation (BUILT 2026-05-13)

**Scope shipped:**
- 21 HTML pages (home + 7 product landings + needs-assessment + compare + how-it-works + why-us + about + contact + blog stub + 3 resource pages + privacy + terms + disclosure).
- Shared `assets/css/styles.css` (brand tokens + responsive primitives) and `assets/js/main.js` (mobile nav, FAQ accordion, cookie banner, lead-form submitter).
- 5 live vanilla-JS needs calculators on `resources/calculator-collection.html`.
- Lead-capture n8n workflow at `workflows/api/insurance-mga/clx-mga-insurance-lead-capture-v1.json` posting to public CORS endpoint `/webhook/mga/insurance/lead-capture`. Inserts into `leads` (vertical_id='insurance') + writes `regulatory_audit_log` row. CASL consent enforced client-side AND server-side.
- Cloudflare Pages-ready: `_headers` (strict CSP, HSTS, frame-ancestors none), `_redirects` (convenience URLs), `sitemap.xml`, `robots.txt`.

**Compliance items in place:**
- Privacy policy (PIPEDA + Quebec Law 25).
- Terms of service with insurance-specific disclaimers (no-binding-without-policy-issue).
- Comprehensive disclosure page (carrier relationships, commission ranges, conflicts, complaints, AML, E&O, AODA, CASL).
- Mandatory disclosure footer on every page.
- Cookie consent banner on every page.

**Compliance items gated on Mary:**
- LLQP license numbers (currently `#X` placeholders on `about.html` + `disclosure.html`).
- FSRA registration confirmation.
- E&O carrier name + policy number (only the $2M coverage minimum is stated currently).
- Carrier appointment status reconciliation — remove any seeded carrier name from `index.html` carrier strip and product pages where Crystallux doesn't have an active appointment.
- Calendly embed code (placeholder block on `contact.html`).
- Email aliases set up: `clients@`, `complaints@`, `privacy@`, `compliance@`.

## Phase 2 — AI Discovery Engine (Month 3–6)

**Goal:** Convert `needs-assessment.html` from a static lead form into a multi-step interactive AI experience.

**Scope:**
- Multi-step form (one question per screen, conversational UX).
- Real-time Claude-powered analysis after submission: identifies primary need (life / CI / DI / etc), estimates coverage range, surfaces likely product fits.
- Email-back with personalised explainer + 2–3 fitted options.
- Backend: extend `clx-mga-insurance-suitability-interview-v1` workflow (already exists) to power the public-facing flow.

**Tech:** Multi-step state machine in vanilla JS; result page renders Claude response. No new framework — same plain-HTML stack.

## Phase 3 — Static Comparison Engine (Month 6–12)

**Goal:** Detailed side-by-side product pages backed by real seed data from `carrier_products` + `insurance_carriers` tables.

**Scope:**
- Dynamic comparison pages built from the database (term life / whole life / CI / DI side-by-side per carrier).
- Coverage-difference explanations (annotated diff between policies).
- Use-case scenarios ("If you're a 35-year-old non-smoker with a $600K mortgage and 2 kids…").
- Customer story integration (after we have testimonials).
- Backend: extend `clx-mga-insurance-product-compare-v1` workflow (exists) to serve public consumption.

## Phase 4 — Live Quote Engine (Year 2)

**Goal:** Real-time quotes — actual carrier-API integration where carriers allow it.

**Scope:**
- Walnut API integration (priority 1 — they have a clean developer API).
- PolicyMe API integration (priority 2).
- Real-time underwriting pre-screening (carrier-side eligibility check before formal application).
- Direct application submission for simplified-issue products.

**Tech:** Per-carrier `clx-mga-insurance-quote-api-<carrier>-v1.json` workflows. Frontend embed of quote engine on product landing pages.

## Phase 5 — Full Platform (Year 2–3)

**Goal:** Authenticated client portal with policy management, claims status, document storage.

**Scope:**
- Authenticated client portal (reuses Crystallux SaaS `clxAuth` patterns).
- Policy management dashboard (status, payments, beneficiary updates).
- Claims initiation + status tracking.
- Document storage (policy PDFs, illustrations).
- Mobile-responsive (no separate app needed in v1).
- Multi-product bundle optimisation (auto + home + life rolled into one premium structure).

## Cross-references

- [`insurance-marketing/`](../../insurance-marketing/) — Phase 1 deployed site.
- [`workflows/api/insurance-mga/clx-mga-insurance-lead-capture-v1.json`](../../workflows/api/insurance-mga/clx-mga-insurance-lead-capture-v1.json) — Phase 1 lead handler.
- [`workflows/api/insurance-mga/clx-mga-insurance-suitability-interview-v1.json`](../../workflows/api/insurance-mga/clx-mga-insurance-suitability-interview-v1.json) — Phase 2 foundation (already exists).
- [`workflows/api/insurance-mga/clx-mga-insurance-product-compare-v1.json`](../../workflows/api/insurance-mga/clx-mga-insurance-product-compare-v1.json) — Phase 3 foundation.
- [`db/migrations/carrier-integration-schema.sql`](../../db/migrations/carrier-integration-schema.sql) — `insurance_carriers` + `carrier_products` schema used in Phase 3+.
- [`docs/strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md`](../strategy/CRYSTALLUX_MONETIZATION_STRATEGY.md) — broader commercial roadmap.

## Deployment runbook (Phase 1)

1. **Cloudflare Pages** — create project `crystallux-insurance-marketing`, production branch `scale-sprint-v1`, output `insurance-marketing/`.
2. **DNS** — `CNAME insurance → crystallux-insurance-marketing.pages.dev`.
3. **Workflow import** — `docker exec n8n n8n import:workflow --input=/data/workflows/api/insurance-mga/clx-mga-insurance-lead-capture-v1.json`, then activate.
4. **Compliance review** — fill in license numbers + E&O details in `about.html` + `disclosure.html`.
5. **Calendly embed** — replace placeholder block on `contact.html`.
6. **Smoke test** — submit needs-assessment, verify row in `leads` table with `vertical_id='insurance'`.
7. **SEO** — submit `sitemap.xml` to Google Search Console + Bing Webmaster Tools.
8. **Analytics** — enable Cloudflare Web Analytics on the Pages project.
