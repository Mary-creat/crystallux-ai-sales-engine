# Claude Context — Crystallux platform brief

> **Purpose:** the longer-form companion to [`/CLAUDE.md`](../CLAUDE.md) at the repo root. CLAUDE.md is the auto-loaded session bootstrap pointer; this file is the depth document Claude (or any new contributor) reads when they need the *why* behind decisions, not just the *where*. Read this when CLAUDE.md alone isn't enough.

## What Crystallux is

**Crystallux is a universal AI sales engine.** Vertical-agnostic by design. Insurance brokerage is one of many verticals it serves — and the founder's home vertical — but the platform is not an insurance product. The same codebase powers real estate, mortgage, dental, consulting, construction, agencies, law firms, financial advisors, and more. Vertical tuning is a configuration row in `niche_overlays`, not a codebase fork.

The platform is delivered as a **two-business operation** built on a single codebase:

1. **Crystallux Platform (the universal engine)** — productized AI sales engine sold across every service-industry vertical. Five service lines: Pipeline / Content / Coach / Manager / Operator. Pricing $197-$25,000/mo. The larger of the two business opportunities; sells horizontally and is unconstrained by any single vertical's licensing or regulatory regime.
2. **Crystallux MGA (one vertical-specific application)** — separately licensed Managing General Agency in Ontario insurance. Uses the platform as a proprietary sub-agent recruitment moat. Earns override commissions on policies sub-agents write. See [BUSINESS_PLAN.md §5](architecture/BUSINESS_PLAN.md). The MGA is the platform's *first and most evangelical customer*, not the platform's identity.

Both businesses share schemas, dashboards, and workflows. Architectural separation is enforced through `niche_overlays` (per-vertical config rows), `clients` (per-tenant rows), and `team_members` (per-agent rows). When evaluating any feature request, **default to the universal interpretation** — only treat something as insurance-specific if it requires FSRA / RIBO / E&O / LLQP regulatory primitives that other verticals don't have.

## The intelligence layer (this is the moat)

The platform's defensibility comes from a stacked set of intelligence layers, each independently shippable + dormant-by-default, activated per-client. Read these in order:

1. **[Closing Intelligence (§28)](architecture/OPERATIONS_HANDBOOK.md)** — vertical-specific scripts, objection handlers, follow-ups. Conversion-rate learning loop.
2. **[Calendar Restructuring (§29)](architecture/OPERATIONS_HANDBOOK.md)** + **[Morning Priority (§30)](architecture/OPERATIONS_HANDBOOK.md)** + **[Geographic Optimization (§31)](architecture/OPERATIONS_HANDBOOK.md)** — operational layers that shape an advisor's day.
3. **[Productivity Tier (§32)](architecture/OPERATIONS_HANDBOOK.md)** — consent-gated activity tracking, supervisor dashboards, coaching framework. $1,000/mo Tier B.
4. **[Listening Intelligence (§33)](architecture/OPERATIONS_HANDBOOK.md)** — live-call transcript + Claude classification + post-call coaching. Two-party Canadian consent enforced at the RPC layer. $2,500/mo Tier C.
5. **[Real-time Closing Script Pop-Ups (§34)](architecture/OPERATIONS_HANDBOOK.md)** — in-call script suggester with sub-2-second latency.
6. **[Behavioral Intelligence (§35)](architecture/OPERATIONS_HANDBOOK.md)** — **the headline differentiator.** Per-lead monitoring of 10 signal categories (personal life events, business events, industry, sports, news, social, insurance-specific, financial, geographic, calendar). Compounds into trigger archetypes that auto-send or surface personalised outreach. Sensitivity-gated, PIPEDA-compliant, opt-out at every layer. $1,500-$3,500/mo Tier D. **The thesis: every advisor with a 1,000-person book gets the context window of a top-tier relationship advisor with a 30-person book — at zero marginal effort.** Designed; not yet built.
7. **[Market Intelligence (§27)](architecture/OPERATIONS_HANDBOOK.md)** — the vertical-level companion to Behavioral Intelligence. External signals (BoC rates, weather, regulatory feeds) scale outreach *volume* per vertical; behavioral signals scale outreach *relevance* per lead. Both feed Campaign Router v2.

The **moat lives in §35 (Behavioral Intelligence)**. Apollo + ChatGPT can write a personalised email; they cannot tell you a prospect's daughter just graduated, his commercial GL renews in 60 days, his Maple Leafs lost last night, and his LinkedIn says he hired three people this quarter — and that the right move is a short note + group benefits intro, *today*. Crystallux can. See [PRODUCT_VISION.md](architecture/PRODUCT_VISION.md) for the full thesis.

## What's shipped vs. what's coming

### Shipped + active (production)
- Lead discovery, research, scoring (v2 / v3 protected workflows)
- Multi-channel outreach: email, LinkedIn, WhatsApp, voice (DNCL-gated), video, SMS
- Reply ingestion + booking pipeline
- Apollo enrichment + lead import
- Stripe billing + subscription provisioning
- Admin + client dashboards (Cloudflare Pages, Phase 3 split)
- Auth, RLS, audit logging, monitoring thresholds
- Admin Copilot (FAB ✦ + chat + voice + DB query / troubleshoot / platform Q&A)
- Client Assistant (FAB ✦ + chat + voice, tenant-scoped)

### Built but dormant (activate per-client)
- Closing Intelligence script library (§28)
- Calendar Restructuring + No-Show Recovery (§29)
- Morning Priority Daily Plan (§30)
- Geographic / Route Optimization (§31)
- Productivity Tier (§32)
- Listening Intelligence (§33)
- Real-time Closing Script Pop-Ups (§34)
- Market Intelligence Engine (§27)

### Designed, not yet built (next-up)
- **Behavioral Intelligence (§35)** — the headline differentiator
- Advisor Dashboard role + supervisor rollup view
- `policies` table + renewal-window scanner (insurance-specific schema)
- Carrier comparison tool
- Group quote intake
- CE tracking for sub-agents
- Document management (FSRA recordkeeping)
- Lead recycling workflow
- Cross-sell strategy detection

Full inventory: [`docs/audit/insurance-features-extracted.md`](audit/insurance-features-extracted.md).

## What makes the architecture defensible

1. **Compliance by design.** CASL footers / DNCL gates / PIPEDA consent versioning / FSRA-aware copy / two-party call-recording consent — all baked in at the RPC layer, not bolted on. Competitors ship US-first products that fail Canadian regulatory review.
2. **Vertical-agnostic config-not-code.** Adding a new vertical is `INSERT INTO niche_overlays` + seed `closing_scripts` + Stripe price + landing page. ~1-3 days. The intelligence layer learns from cross-vertical patterns.
3. **Dormant-by-default activation.** Every new feature ships `active: false` and a per-client tier-flip RPC. No coordinated big-bang launches; per-client risk is bounded.
4. **Single codebase, two businesses.** Platform sells horizontally; MGA recruits sub-agents using the platform as a moat. The same `team_members` table powers both — no fork.
5. **Stack chosen for predictable cost.** Plain HTML + plain JS dashboards (no bundler, no framework) + n8n workflows + Supabase + Cloudflare Pages. Total infra: <$200/mo at 30 clients.

## Conventions you must not break

- **The 7 protected v2/v3 production workflows** — Lead Research v2, Campaign Router v2, Outreach Generation v2, Outreach Sender v2, Pipeline Update v2, Reply Ingestion v1, Booking v2. Don't touch without explicit instruction.
- **Workflow JSONs** — credential references use `name` only, never `id`. Every multi-branch Shape Response uses the `Merge Branches` (`mode: append`) pattern + the `allOf(name)` helper. See [`OPERATIONS_HANDBOOK §29`](architecture/OPERATIONS_HANDBOOK.md) and any recent admin client-detail commit.
- **Frontend** — plain HTML + plain JS. No build pipeline, no TypeScript, no bundler. Shared modules: `clxAuth` / `clxApi` / `clxComp`. CSP lives in `_headers`, not `<meta>`.
- **Migrations** — additive, idempotent (`IF NOT EXISTS` / `ON CONFLICT DO NOTHING`), with a rollback comment block at the bottom.
- **Documentation** — write decisions back to the handbook ([`OPERATIONS_HANDBOOK.md`](architecture/OPERATIONS_HANDBOOK.md)) immediately. Chat is a working surface, not a record. **If it matters, file it.**

## Where the canonical sources live

Read these in this order when joining a new task:

1. [`/CLAUDE.md`](../CLAUDE.md) — bootstrap pointer (auto-loaded by Claude Code)
2. This file (depth context)
3. [`docs/architecture/OPERATIONS_HANDBOOK.md`](architecture/OPERATIONS_HANDBOOK.md) — feature-by-feature, 35 sections
4. [`docs/architecture/PRODUCT_VISION.md`](architecture/PRODUCT_VISION.md) — thesis + what's NOT being built
5. [`docs/architecture/BUSINESS_PLAN.md`](architecture/BUSINESS_PLAN.md) — service catalog + MGA structure + pricing
6. [`docs/audit/insurance-features-extracted.md`](audit/insurance-features-extracted.md) — feature inventory by build status
7. [`docs/audit/production-readiness.md`](audit/production-readiness.md) — current sprint state
8. [`docs/audit/blockers.md`](audit/blockers.md) — gated items waiting on Mary

## Differentiation features by name (for intent-routing)

When a feature request lands, route by name:

| Request mentions | Section / doc to read |
|------------------|----------------------|
| "right-time-to-call", "personalised by event", "life event trigger", "renewal-window outreach", "birthday reach-out" | [§35 Behavioral Intelligence](architecture/OPERATIONS_HANDBOOK.md) |
| "live call coaching", "transcript", "what was said on the call" | [§33 Listening Intelligence](architecture/OPERATIONS_HANDBOOK.md) |
| "in-call script", "objection handler pop-up" | [§34 Real-time Script Pop-Ups](architecture/OPERATIONS_HANDBOOK.md) |
| "scripts library", "objection handlers", "vertical templates" | [§28 Closing Intelligence](architecture/OPERATIONS_HANDBOOK.md) |
| "supervisor dashboard", "team productivity", "leaderboard" | [§32 Productivity Tier](architecture/OPERATIONS_HANDBOOK.md) + [§2.1 of insurance-features-extracted](audit/insurance-features-extracted.md) |
| "morning priorities", "Today's Plan", "advisor SLA" | [§30 Morning Priority Task Ordering](architecture/OPERATIONS_HANDBOOK.md) |
| "no-show recovery", "calendar reshuffle" | [§29 Calendar Restructuring](architecture/OPERATIONS_HANDBOOK.md) |
| "drive time", "route optimisation", "field appointments" | [§31 Geographic Appointment Optimization](architecture/OPERATIONS_HANDBOOK.md) |
| "vertical signals", "scale outreach by news/weather/rates" | [§27 Market Intelligence](architecture/OPERATIONS_HANDBOOK.md) |
| "advisor dashboard", "MGA sub-agent view" | [insurance-features-extracted §2.1](audit/insurance-features-extracted.md) — currently designed-not-built |
| "policies", "renewal date", "carrier compar", "group quote" | [insurance-features-extracted Bucket 2 (multiple §s)](audit/insurance-features-extracted.md) — designed-not-built schema gaps |
| "Copilot", "chat", "voice notes", "MCP" | [§22 Admin Copilot](architecture/OPERATIONS_HANDBOOK.md) + `admin-dashboard/shared/copilot.js` + `client-dashboard/shared/copilot.js` |

## How to write decisions back so they survive

Every non-trivial decision must land in the right canonical doc before the chat session ends:

| Type of decision | Goes in |
|------------------|---------|
| New feature spec | New `## XX. Feature Name (Phase B.YY)` section in OPERATIONS_HANDBOOK.md, structured as: Status / What it is / Schema / Workflows / Dashboard / Activation / Privacy / Decommission / Cost / Cross-references |
| Pricing or packaging change | BUSINESS_PLAN.md §4 or §9 |
| Differentiation thesis | PRODUCT_VISION.md |
| Schema migration | New `docs/architecture/migrations/YYYY-MM-DD-<name>.sql` |
| Operational runbook | New `docs/operations/<NAME>.md` |
| Feature inventory update | `docs/audit/insurance-features-extracted.md` (Bucket 1 / 2 / 3) |
| Blocker / gated work | `docs/audit/blockers.md` |
| Compliance / consent update | The relevant operations doc + bump the consent_version in the corresponding migration |

When in doubt — file it in OPERATIONS_HANDBOOK.md. Future Claude reads from there.
