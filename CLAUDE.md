# Crystallux — Claude bootstrap

> **You (Claude) are joining a sprint already in progress.** Read this file first, then read the docs it points to *before* answering, planning, or coding. The handbook is the source of truth — chat history is not.

## Working agreement (read first, every session)

1. **Handbook before chat.** When in doubt about a feature, decision, schema, or workflow behaviour, **read the handbook**. Do not infer from chat — chat gets compacted, the handbook does not.
2. **Write decisions back to the handbook.** Any non-trivial decision made in chat must be filed into the relevant handbook section before the session ends, otherwise it disappears at context limit.
3. **Build on what exists.** Don't ship parallel implementations. Reuse `clxAuth`, `clxApi`, `clxComp` (admin), `clxApi`, `clxComp` (client). Reuse the migration patterns in `docs/architecture/migrations/`. Reuse the workflow patterns in `workflows/api/`.
4. **Don't break what works.** The 7 protected v2/v3 production workflows must not be touched without explicit instruction (Lead Research v2, Campaign Router v2, Outreach Generation v2, Outreach Sender v2, Pipeline Update v2, Reply Ingestion v1, Booking v2).
5. **Respect the dormant-by-default policy.** New workflows ship `active: false`. Activation is per-client + per-tier, applied by Mary in production.

## Context compaction strategy

Claude has no memory between sessions. Within a session, context compresses. To minimise loss:

- **End every meaningful work block by updating the handbook** (`docs/architecture/OPERATIONS_HANDBOOK.md`), the audit reports, or a feature-specific doc.
- When a session feels heavy, run `/compact focus: <what to preserve>`.
- Treat chat as a working surface, not a record. **If it matters, file it.**
- Use `docs/audit/blockers.md` to bookmark partial work + what Mary still needs to do — that file is the cross-session bridge.

## Where things live

### Source of truth (read these before any non-trivial task)
- [`docs/architecture/OPERATIONS_HANDBOOK.md`](docs/architecture/OPERATIONS_HANDBOOK.md) — 2,500+ lines, 34 numbered sections covering every feature, schema, workflow, dashboard panel. **The single most important doc.**
- [`docs/architecture/BUSINESS_PLAN.md`](docs/architecture/BUSINESS_PLAN.md) — service catalog (5 services), MGA business line, vertical roadmap, pricing, financial model.
- [`docs/architecture/ARCHITECTURE_DOCTRINE.md`](docs/architecture/ARCHITECTURE_DOCTRINE.md) — non-negotiable architectural decisions.

### Current sprint state
- [`docs/audit/insurance-features-extracted.md`](docs/audit/insurance-features-extracted.md) — exhaustive feature inventory by build status (🟢🟡🔴) for the Advisor Dashboard scoping.
- [`docs/audit/production-readiness.md`](docs/audit/production-readiness.md) — per-criterion ✓ / gated table; what's verified vs. waiting on Mary.
- [`docs/audit/blockers.md`](docs/audit/blockers.md) — what Mary still has to do (SQL migrations + VPS workflow re-import + Cloudflare cache purge).
- [`docs/audit/post-fix-report.md`](docs/audit/post-fix-report.md) — what the audit found and what got fixed in commits `de446f5` + `1d7f7dd` + `696d372`.
- [`docs/audit/admin-audit-report.md`](docs/audit/admin-audit-report.md) and [`client-audit-report.md`](docs/audit/client-audit-report.md) — Playwright per-page audit output.

### Code
- `admin-dashboard/` — Cloudflare Pages site for `admin.crystallux.org`. Plain HTML + plain JS. Pages: overview, clients, client-detail, leads, workflows, billing, onboarding, market-intelligence, audit-log, settings.
- `client-dashboard/` — Cloudflare Pages site for `app.crystallux.org`. Pages: overview, leads, campaigns, bookings, activity, billing, settings.
- `site/` — marketing site at `crystallux.org` (login, industry pages, etc.).
- `dashboard/` — **legacy** single-page dashboard (4,578 lines). Source for features being ported into the split admin/client dashboards. Don't develop net-new here.
- `workflows/` — 52 n8n workflow JSONs (top-level = backend pipeline workflows; `workflows/api/admin/` and `workflows/api/client/` = the 18 dashboard webhooks).
- `docs/architecture/migrations/` — every SQL migration applied to Supabase, in chronological order.
- `tests/audit/dashboard-audit.js` — Playwright audit harness.

### Operations runbooks
- [`docs/operations/`](docs/operations/) — every recurring operational doc (onboarding scripts, contracts, consent forms, incident response, weekly check-in, etc.).
- [`docs/operations/AGENT_PREFERENCE_ONBOARDING.md`](docs/operations/AGENT_PREFERENCE_ONBOARDING.md) — 5-question Q&A every advisor / agent goes through.

## Current branch + recent commits

- **Branch:** `scale-sprint-v1`
- **Most recent commits (newest first):**
  - `696d372` — Re-audit verification: CSP fix landed, 10/10 admin pages pass
  - `1d7f7dd` — CSP cleanup for marketing site
  - `de446f5` — Audit harness + workflow allOf() fix + CSP cleanup + migrations
  - `187430a` — Polish layer commit 3: 7 client pages + Merge fix on 2 client wfs
  - `15231e0` — Polish layer commit 2: 10 admin pages + revert diagnostic
  - `fbfaee0` — Polish layer commit 1: shared CSS tokens + components.js helpers + SVG nav

## Test data

- **Test client tenant:** Crystallux Insurance Network, `id = 6edc687d-07b0-4478-bb4b-820dc4eebf5d`, ~79 leads.
- **Other test tenant:** Blonai Moving Company, ~61 leads.
- **Admin login:** `info@crystallux.org` / `Crystallux2026#`.
- **Test client login:** `testclient@crystallux.org` / `TestPass2026#` (creation gated on `db/migrations/test-client-account.sql` being applied).

## Key conventions

- **Branch:** all work on `scale-sprint-v1`. Mary merges to `main` herself.
- **Workflow JSONs use `allOf(name)` helper** to handle n8n's array-split behaviour. See any `Shape Response` Code node in `workflows/api/admin/` or `workflows/api/client/` for the canonical pattern.
- **Multi-branch workflows use a `Merge Branches` (`mode: append`) node** before the Shape Response. See `clx-admin-client-detail.json` (the canonical fix) — applied in commits `b5660d1` (admin) and `187430a` (client).
- **Workflow credential references use name only, never id** — strip `id` from `credentials.<type>` blocks; n8n resolves by name during import.
- **Frontend CSP:** the canonical CSP lives in `admin-dashboard/_headers`, `client-dashboard/_headers`, `site/_headers`. The `<meta>` CSP in HTML is a fallback only (and must NOT contain `frame-ancestors` — that directive is invalid in `<meta>` per spec).
- **Shared frontend modules:** `clxAuth` (`/shared/auth.js`), `clxApi` (`/shared/api.js`), `clxComp` (`/shared/components.js`). Helper inventory: `escapeHtml`, `formatDate`, `formatDateTime`, `relativeTime`, `formatMoney`, `badgeFor`, `renderStatGrid`, `renderTable` (admin) / `renderList` (client), `renderEmpty`, `injectNav`, `wireSidebar`, `renderTopbarUser`, `icon`, `skeleton`, `skeletonStat`, `sparkline`, `donut`, `donutLegend`, `barChart`, `progressBar`, `avatar`, `scoreBar`, `sectionHead`.

## What you should NOT do without explicit instruction

- Touch any of the 7 protected v2/v3 production workflows.
- Activate dormant workflows (`active: true`) — that's a Mary action.
- Apply migrations to Supabase — Mary applies migrations.
- Push force / rewrite history on `scale-sprint-v1` or `main`.
- Add a build pipeline / framework / TypeScript / bundler. The repo is intentionally plain HTML + plain JS.
- Run `git add -A` / `git add .` — stage specific files only.
- Create new top-level docs without first checking `docs/` for an existing home.

## When you finish a non-trivial task

1. File the decision into the handbook.
2. Update the relevant `docs/audit/*.md` if the task affects the audit posture.
3. Commit with a message that explains *why*, not *what* (the diff explains the what).
4. Push — Mary needs to see it on `scale-sprint-v1`.
5. Tell Mary what's gated on her (migrations to apply, workflows to re-import, etc.) — every gated item belongs in `docs/audit/blockers.md`.
