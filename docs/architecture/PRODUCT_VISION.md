# Crystallux — Product Vision

> **The thesis in one sentence:** every relationship-driven operator with a 1,000-person book should have the context window of a top-tier 30-person-book operator — at zero marginal effort, in any vertical.

## Crystallux is a universal sales engine

Crystallux is **vertical-agnostic by design**. The same codebase serves insurance brokers, real estate agents, mortgage brokers, financial advisors, dental practices, consultants, construction firms, law firms, agencies, and more. Vertical tuning is a configuration row in `niche_overlays`, not a codebase fork.

Insurance brokerage is currently the founder's home vertical and the operational beachhead — but it is **one of many** verticals the platform serves, not the platform itself. Every feature described below is built once, vertical-tuned through configuration, and sold across the catalog.

## What Crystallux is becoming

Crystallux started as a pipeline tool — find prospects, research them, write them, book them. It's now becoming a **seller-augmenting operating system** for any vertical where success depends on knowing the prospect and timing the outreach.

The arc:

1. **Pipeline** (shipped) — *who* to talk to. Discovery + research + multi-channel outreach.
2. **Closing Intelligence** (shipped, dormant) — *how* to talk. Vertical-specific scripts, objection handlers, follow-up sequences with usage learning.
3. **Listening Intelligence** (built, dormant) — *what was actually said*. Real-time transcript classification + post-call coaching + script adaptation in-flight.
4. **Behavioral Intelligence** (designed) — ***when*** to talk. Per-lead signal monitoring across 10 categories + compounded triggers + sensitivity-gated personalised outreach.
5. **Advisor Dashboard** (designed) — the role-specific surface that pulls all four together for licensed advisors / sub-agents (especially MGA-distributed insurance brokers).

Each of these is independently shippable + sellable. Together they're the moat.

## What we are NOT

- We are not "ChatGPT for sales reps." A generic LLM can write a cold email; it cannot tell you a prospect's daughter just graduated, his commercial GL renews in 60 days, and his Maple Leafs lost last night, and that the right call is *today*.
- We are not "another HubSpot." HubSpot is a CRM. Crystallux is a sales agent. We don't ask the advisor to log calls; we infer the next move.
- We are not "another Apollo." Apollo finds emails. Crystallux finds the right time to use them.
- We are not a vertical-specific tool. The platform is industry-agnostic; vertical tuning is a configuration row in `niche_overlays`, not a codebase fork.

## Differentiation features (what makes this defensible)

### 1. Behavioral Intelligence

The headline differentiator, **applied identically across every vertical**. Per-lead signal monitoring across **10 categories** (personal life events, business events, industry shifts, sports, news mentions, social activity, vertical-specific events, financial milestones, geographic moves, internal calendar gaps) feeds a trigger engine that compounds signals into archetypes per vertical and either auto-sends a personalised outreach or surfaces it for advisor approval.

The 10 categories are universal; **what differs per vertical is the seeded archetype library**:

- **Insurance broker:** birthday + 60-day-renewal → renewal walkthrough; new baby → term life (high sensitivity, mandatory review); business expansion → group benefits.
- **Real estate agent:** anniversary in current home + neighbourhood comp sold above asking → "thinking about listing?" outreach; child reaching school-age → suburban-move trigger; divorce news → relocation listing rep.
- **Mortgage broker:** Bank of Canada rate move + lead's existing mortgage approaching renewal → refi opportunity; promotion + spouse income → upsizing pre-approval.
- **Dental practice:** 6-month recall due + no booking on file → recall outreach; insurance-year-end + treatment plan pending → "use it or lose it" reminder.
- **Construction / contractor:** building permit filed in lead's neighbourhood + lead's home approaching 25-yr mark → reno outreach; storm event in region → roof / restoration pitch.
- **Consulting firm:** target company press-release + competitor named → "we work with X type of client" outreach; new exec hire at target → exec-onboarding pitch.

Concrete example (insurance): a lead's birthday today (lead-supplied DoB) + commercial GL renewal in 58 days + Toronto Maple Leafs won last night → one outreach opening with sports rapport, mentioning the renewal window, ending with a 15-minute calendar ask. Auto-composed via Claude Haiku, RIBO-safe per the niche overlay's compliance rules, sent through the existing multi-channel outreach pipeline.

Concrete example (real estate): a lead's home anniversary today + neighbour just sold $80K over asking + LinkedIn shows the lead's family has grown → one outreach: "Saw the sale on Maple Ave — comps in your block are pulling hard right now. If you've ever wondered what your place would list at today, want me to run an updated CMA? — [Agent]"

Same engine. Same Claude prompt scaffold. Different `niche_overlays` row. Different archetype seed set.

The full spec is [OPERATIONS_HANDBOOK §35](OPERATIONS_HANDBOOK.md). The pricing positions it as Tier D ($1,500-$3,500/mo) of the intelligence tier ladder, available in every vertical. It is **a** strong sub-agent recruitment lever for the [Crystallux MGA business line](BUSINESS_PLAN.md), but the same feature also powers a real-estate team's recruitment pitch and a dental clinic's hygienist retention pitch. The platform is the moat; insurance is one expression of it.

### 2. Listening Intelligence

Live-call transcript streaming + Claude-classified intent / sentiment / topics + post-call coaching analysis. Two-party Canadian consent model enforced at the RPC layer (a dashboard bug cannot bypass it). Detects objections, buy signals, closing signals, agent confusion in-flight; the real-time script suggester (§34) surfaces the right objection handler within ~2 seconds.

Why this matters: most sales coaching is anecdotal — a manager listens to 3 calls a quarter and gives generic feedback. Crystallux makes 100% of calls coachable, and the closing intelligence library (§28) learns from which scripts converted vs. didn't.

### 3. Closing Intelligence script library

Vertical-specific seeded library (7 verticals, ~100 templates per vertical: discovery frameworks, objection handlers, closing scripts, follow-up sequences, competitor intelligence). Conversion-rate tracking on every render. The script suggester ranks by recent performance per agent — the top-performing scripts surface fastest, low-performers fall out of rotation.

### 4. Compliance-by-design

Every layer is built with Canadian regulatory primitives baked in:

- **CASL** (Canadian Anti-Spam) — every outreach has the unsubscribe footer, sender ID, mailing address. No way to ship a CASL-non-compliant send from this platform.
- **DNCL** (Do Not Call List) — voice outreach short-circuits if `do_not_contact = true`.
- **PIPEDA** (federal privacy) — every consent flag has a versioned audit trail (`_at`, `_version`). Withdrawal flips the gate on the very next event; no retroactive deletion required to be compliant.
- **FSRA / RIBO** (Ontario insurance regulators) — niche overlay copy tuned for licensed-advisor language; objection handlers avoid guaranteed-outcome promises; advisors retain fiduciary authority.
- **Two-party consent for call recording** (CRTC) — Listening Intelligence enforces both client + agent consent at the RPC layer.

This is non-trivial for any competitor to replicate — they'd have to rebuild it all, and most ship US-first products that fail Canadian regulatory review.

### 5. Single platform, every vertical

Adding a new vertical (insurance broker → real estate → dental → consulting → construction → moving → cleaning → legal) is a configuration change, not a code change: seed `niche_overlays` + `closing_scripts` + `objection_handlers` per vertical, set Stripe pricing, ship a marketing landing page. ~1-3 days end-to-end. The platform learns from cross-vertical signal patterns; an insurance broker's productivity tracking surfaces patterns identical to a real estate agent's.

### 6. MGA business model (one of two business lines, not the whole story)

Crystallux MGA ([BUSINESS_PLAN.md §5](BUSINESS_PLAN.md)) is **one** of the two business lines and the platform's most evangelical customer — its own best case study in the insurance vertical. Sub-agents who join the MGA get the platform bundled (the only Canadian MGA that does). For sub-agents this is a "stop prospecting, focus on closing" promise that no other MGA can match. For Crystallux it's $200-$10K/month per sub-agent in override commissions on top of the SaaS revenue.

**The platform business line is the larger of the two opportunities** — it sells horizontally across every service-industry vertical, untethered to insurance licensing. The MGA is a vertical-specific business that uses the platform as its proprietary tool; the platform itself stays universal.

## What we are deliberately NOT building (yet)

- Generic CRM features (relationship trees, deal pipelines disconnected from outreach). The advisor's CRM is *whatever they already use* — we integrate, we don't replace.
- Open-ended chatbot features. The Copilot is intentionally scoped: admin-only DB query / troubleshoot / platform Q&A, plus a separate tenant-scoped client assistant. No broad agentic loops on customer data without explicit scoping.
- Anything that requires a human SDR or AE in the loop. The platform is the SDR. Humans are the closer.
- US-only features (HIPAA, US carrier integrations, US payroll). Canada-first; US is a Year 2-3 expansion.

## How a session of Claude should reason about features

If a feature request lands that:

- Routes through "advisor-side surface" → it's part of the **Advisor Dashboard** project (see [`docs/audit/insurance-features-extracted.md`](../audit/insurance-features-extracted.md) for the full inventory).
- Routes through "per-lead signal" or "right-time-to-call" → it's **Behavioral Intelligence** ([OPERATIONS_HANDBOOK §35](OPERATIONS_HANDBOOK.md)).
- Routes through "in-call coaching" or "what was actually said" → it's **Listening Intelligence** (§33) and/or **real-time scripts** (§34).
- Routes through "what should I send" → it's **Closing Intelligence** (§28).
- Routes through "vertical pricing / packaging" → [BUSINESS_PLAN.md](BUSINESS_PLAN.md) + [STRIPE_PRODUCTS_SPEC.md](../STRIPE_PRODUCTS_SPEC.md).
- Routes through "MGA-specific" → [BUSINESS_PLAN.md §5](BUSINESS_PLAN.md) + [docs/mga/](../mga/).
- Doesn't fit any of these — challenge the request before building. The platform stays focused.

## Cross-references

- [OPERATIONS_HANDBOOK.md](OPERATIONS_HANDBOOK.md) — the canonical feature reference. Read sections 27-35 for the intelligence layer.
- [BUSINESS_PLAN.md](BUSINESS_PLAN.md) — service catalog, pricing, MGA structure, vertical roadmap.
- [ARCHITECTURE_DOCTRINE.md](ARCHITECTURE_DOCTRINE.md) — non-negotiable architectural decisions.
- [docs/audit/insurance-features-extracted.md](../audit/insurance-features-extracted.md) — feature inventory by build status (🟢🟡🔴) for Advisor Dashboard scoping.
- [CLAUDE.md](../../CLAUDE.md) — Claude Code session bootstrap pointer.
