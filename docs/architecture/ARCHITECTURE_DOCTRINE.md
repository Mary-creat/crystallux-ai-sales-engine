# The Three-Layer Architecture — Governing Principle

> **Version 1.0** — April 18, 2026
>
> **Status:** Doctrine. This document governs every architectural and product decision at Crystallux.
>
> **Audience:** Founder, engineers, product managers, partners, investors, future hires.
>
> **Companion document:** `BUSINESS_PLAN.md` (strategic spine). This document is the architectural spine.

---

## The Core Principle

**Crystallux is structured in three distinct layers, each with its own concerns. A change in one layer must not require changes in the others.**

```
┌─────────────────────────────────────────────────┐
│            LAYER 3 — NICHE OVERLAYS             │
│             (configuration, not code)           │
├─────────────────────────────────────────────────┤
│            LAYER 2 — MODULAR SERVICES           │
│              (products, SKUs, bundles)          │
├─────────────────────────────────────────────────┤
│            LAYER 1 — UNIVERSAL CORE             │
│              (the engine, shared by all)        │
└─────────────────────────────────────────────────┘
```

Every feature, every line of code, every configuration belongs in exactly one layer. Confusion about which layer a thing belongs in is the leading cause of architectural rot in SaaS platforms.

---

## Layer 1 — Universal Core (the engine)

**Purpose:** Provide the fundamental capabilities that ALL products and ALL niches need.

**Never specific to any product. Never specific to any niche. Never specific to any client.**

### What lives in the Core

- **Data model:** The 25+ table schema. Every table exists for every customer.
- **Discovery:** How leads are found (Google Maps scanner, Apollo scanner, etc.)
- **Enrichment:** Email scraping, data augmentation
- **Research:** AI-powered company and contact research
- **Scoring:** Fit and intent scoring
- **Signal detection:** Behavioral and market signal analysis
- **Routing:** Decision engine that matches leads to campaigns
- **Content generation:** AI-powered content creation
- **Delivery:** Multi-channel send (email, LinkedIn, WhatsApp, SMS, voice, video)
- **CRM:** Lead tracking, pipeline management
- **Analytics:** Performance measurement, reporting
- **Permissions:** User access control, RLS
- **Billing:** Subscription management, invoicing
- **Team management:** Hierarchy, activity tracking, productivity metrics
- **Coaching:** Goal tracking, accountability, check-ins
- **Market intelligence:** Signal aggregation, seasonal awareness

### The rule for Core

> If insurance brokers need it AND dentists need it AND SaaS founders need it, it lives in the Core.

If only one type of customer needs it, it does NOT belong in the Core.

### Consequences of getting this right

- Every new module inherits all core capabilities automatically
- Every new niche gets production-ready infrastructure from day one
- Bug fixes propagate to all customers simultaneously
- Performance improvements benefit all customers
- Engineering effort compounds instead of fragmenting

### Consequences of getting this wrong

- If niche-specific logic creeps into the Core, you can't add new niches without regression testing everything
- If product-specific features contaminate the Core, unrelated products break when one changes
- The platform becomes a monolith disguised as a platform

---

## Layer 2 — Modular Services (the products)

**Purpose:** Package Core capabilities into coherent, sellable products.

A **module** is a specific combination of Core capabilities, wrapped with pricing, positioning, UX, and sales motion.

### The five modules (current)

| Module | Activates (from Core) | Target Buyer |
|---|---|---|
| **Pipeline** | Discovery → Enrichment → Research → Scoring → Routing → Outreach → Delivery → Booking | Solo professionals needing more leads |
| **Content** | Research → Content Generation → Multi-channel delivery | Marketing teams, content-driven firms |
| **Coach** | Goal tracking → Calendar blocks → Check-ins → Resources | Solo operators needing structure |
| **Manager** | Team management → Productivity metrics → Alerts → Leaderboards | Leaders with 5+ reports |
| **Operator** | All of the above, bundled | Mid-market firms, MGAs, franchises |

### The rule for Modules

> A module is a cohesive offer a customer can buy alone and derive complete value from.

If a "module" only works when bundled with another module, it's not really a module — it's a feature.

### Module design principles

1. **Each module has its own pricing tiers** (Starter/Growth/Scale) with different Core capabilities activated at each tier.
2. **Each module has its own landing page** and sales conversation.
3. **Each module has its own onboarding flow** optimized for its specific buyer.
4. **Each module has its own success metric** (Pipeline: meetings booked. Coach: goals achieved. Manager: team productivity score.)
5. **Modules can be bundled** (e.g., Operator = Pipeline + Content + Coach + Manager) but individual modules must stand alone.

### How a module gets built

When adding a new module to Crystallux:

1. Confirm it uses only existing Core capabilities (or extend the Core if needed first)
2. Define what's activated at each pricing tier
3. Create module-specific landing page and onboarding
4. Define success metrics and dashboards
5. Price based on target buyer's willingness-to-pay
6. **Never write module-specific business logic that could have been Core**

---

## Layer 3 — Niche Overlays (the configurations)

**Purpose:** Make the platform speak the language of a specific industry without writing new code.

A **niche overlay** is a configuration bundle — data, not code — that adapts modules to a specific vertical.

### What a niche overlay contains

For each supported niche (insurance brokers, realtors, dentists, etc.), the overlay defines:

- **ICP template:** The ideal customer profile for this niche (typical company size, role titles, geography, etc.)
- **Routing preferences:** Which discovery platforms are preferred, in what priority order
- **Pain-point signals:** The niche-specific signals that indicate buying intent or need
- **Claude system prompt:** Industry-tuned instructions for AI agents
- **Outreach tone:** The language and cadence that resonates with this niche
- **Offer mapping:** Which modules and pricing tiers are recommended for clients in this niche
- **Dashboard labels:** Niche-appropriate terminology (e.g., "Policies" for insurance, "Listings" for real estate)
- **Compliance notes:** Regulatory considerations specific to this niche (CASL for Canada, HIPAA for medical, FINRA for financial)

### The rule for Niche Overlays

> A niche overlay is a database row and a set of prompt templates. It is NEVER a fork of the codebase.

If you find yourself writing `if (niche === 'insurance') { ... } else if (niche === 'real_estate') { ... }` in workflow code, you have broken this rule. That logic belongs in the niche overlay configuration, read at runtime.

### The `niche_overlays` table (to be added)

```sql
CREATE TABLE IF NOT EXISTS niche_overlays (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name TEXT UNIQUE NOT NULL,
  display_name TEXT,
  icp_template JSONB,
  routing_preferences JSONB,
  pain_signals TEXT[],
  claude_system_prompt TEXT,
  outreach_tone TEXT,
  offer_mapping JSONB,
  dashboard_labels JSONB,
  compliance_notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Launching a new niche

Adding a new vertical to Crystallux follows this process:

1. Draft the overlay configuration (1-3 days of research and writing)
2. Insert row into `niche_overlays` table
3. Create niche-specific landing page from template (half day)
4. Create 10-20 ICP-tagged test leads for validation
5. Run end-to-end pipeline test on test leads
6. Launch to public

**No code deployment required. No workflow changes required.** This is the promise of a proper platform architecture.

---

## The Three-Layer Decision Framework

When any feature, request, or change arrives, ask these questions in order:

### Question 1 — Which layer does this belong to?

**Is it useful to every customer regardless of product or niche?**
→ It's Core. Build it once, benefit all customers.

**Is it useful for a specific product but applies across niches?**
→ It's a Module extension. Add to that module's feature set.

**Is it specific to one industry and affects how the platform speaks/routes/targets?**
→ It's a Niche Overlay. Update the configuration.

### Question 2 — Am I tempted to violate the layer?

Common temptations and correct responses:

| Temptation | Correct Response |
|---|---|
| "Let me just add this one niche-specific thing to the workflow code" | No. Add a field to niche_overlays. Workflow reads it at runtime. |
| "This product needs its own database table for one special feature" | Stop. Can the feature be expressed in existing tables? If not, is the table actually Core-worthy? |
| "Let me hardcode these prompts for insurance in the Research workflow" | No. Load prompts from niche_overlays at runtime. |
| "This client wants a custom feature" | Is it useful to all clients? → Core. Only one niche? → Niche Overlay. Only this one client? → Don't build it. |
| "Let me fork the workflow for a different vertical" | Absolutely never. That is architectural suicide. |

### Question 3 — Am I introducing layer confusion?

A healthy sign: The layer where something belongs is obvious.
A warning sign: Debate over which layer something belongs in.

Warning signs require architectural review BEFORE code is written.

---

## Practical Examples

### Example 1 — Adding WhatsApp as a new channel

**Wrong approach:** Build a WhatsApp module.

**Correct approach:** WhatsApp is a *capability*, not a product. It belongs in the Core (Delivery layer). Every module that uses Delivery gains WhatsApp support. Every niche can use WhatsApp.

**Implementation:**
- Add WhatsApp to `channel_credentials` supported types (Core)
- Add WhatsApp integration workflow (Core)
- Update Pipeline module to offer WhatsApp as channel option (Module)
- Update relevant niche overlays that benefit from WhatsApp (Niche)

---

### Example 2 — Client requests "I need reporting specific to my medical practice"

**Wrong approach:** Build a Medical Reporting product.

**Correct approach:** Standard reporting (Core) with medical-specific labels and metrics defined in the Niche Overlay for medical practices.

**Implementation:**
- Core reporting already exists — no change
- Medical overlay defines: "Patients acquired" instead of "Leads", "Show-up rate" instead of "Meeting rate", "No-show cost" as a KPI
- Dashboard pulls labels from niche overlay at runtime
- Same code, different presentation

---

### Example 3 — Adding a Coaching product

**Wrong approach:** Build Coach as a separate app with its own database.

**Correct approach:** Coach is a module that activates existing Core capabilities (goals, check-ins, resources) and packages them for a specific buyer.

**Implementation:**
- All infrastructure already in Core (coaching tables exist)
- Coach module defines: pricing tiers, what activates at each tier, landing page, onboarding
- Niche overlays define: which playbooks/resources are relevant per vertical
- Launch in 1-2 weeks, not 2-3 months

---

### Example 4 — Insurance-specific compliance (CASL)

**Wrong approach:** Write CASL logic into the delivery workflows.

**Correct approach:** Core handles compliance as a general capability. CASL-specific rules live in the insurance niche overlay.

**Implementation:**
- Core: configurable unsubscribe handling, opt-out enforcement, regional compliance hooks
- Insurance niche overlay: `compliance_notes = "CASL applies. Requires explicit opt-in for B2C. B2B relationship-based exceptions documented in /docs/compliance/casl.md"`
- Workflows read compliance requirements from overlay at send time

---

## Enforcement

### How this doctrine is enforced

1. **Every PR description must state which layer(s) it modifies.** PRs that modify inappropriately (e.g., hardcoded niche logic in Core) are rejected.

2. **Quarterly architecture review.** Founder + any technical collaborators review recent changes to ensure no layer violations have crept in.

3. **New hire onboarding requires reading this document.** No engineer at Crystallux writes code without understanding this model.

4. **Partner/white-label contracts reference this architecture.** When Crystallux is licensed to others, they must respect the three-layer structure or licensing terminates.

---

## Why This Matters Commercially

This architecture is not academic. It is the reason Crystallux can scale from $0 to $10M+ ARR with a small team.

**Without this architecture:**
- Each new vertical requires rebuilding
- Each new product requires a new codebase
- Engineering team must triple to keep up
- Bug fixes take 10x as long because they must be applied in multiple places
- Can't onboard new clients fast
- Can't expand geographically
- Can't sustain 85%+ gross margins

**With this architecture:**
- New vertical launches in 1-3 days
- New product launches in 1-2 weeks
- Bug fixes deploy to all customers at once
- One engineer can maintain platform serving 100+ clients
- New geographic regions are configuration
- White-label licensing is turnkey
- Exit valuation comparables are the best SaaS multiples available

---

## Summary — The One-Sentence Version

> **Same engine → different modules → different vertical packaging.**

- Engine: the shared Core.
- Modules: what customers buy.
- Vertical packaging: how it speaks to them.

All three are separable. All three are maintainable. All three compound in value over time.

**This is how Crystallux becomes a $10M+ ARR platform business with a team under 10 people. Do not deviate.**

---

## Related Documentation

- `BUSINESS_PLAN.md` — Strategic business plan and revenue model
- `OPERATIONS_HANDBOOK.md` — Day-to-day operations and troubleshooting
- `migrations/2026-04-18-full-platform-foundation.sql` — The Core data model

---

*This document is doctrine. Update only with explicit architectural review. Last updated: 2026-04-18; decision records appended 2026-08-30.*

---

# Architecture decision records

Appended 2026-08-30. The three-layer model above was written 2026-04-18 and is
**unchanged** — these records document decisions made while implementing it,
each with the evidence that settled it. Format: DECISION / WHY / ALTERNATIVES /
EVIDENCE / IMPACT.

## ADR-001 — `niche_overlays` is the sole source of vertical behaviour

**Decision.** Layer 3 stays exactly where the doctrine put it. No second vertical
intelligence system is created.

**Why.** Eight workflows already read it: campaign router, lead scoring, outreach
generation, Apollo enrichment, signal intelligence, video outreach, voice
outreach, copilot query.

**Alternatives.** A new `vertical_config` table (rejected — duplicates a working
table); moving industry rules into MAXI (rejected, see ADR-002).

**Evidence.** `grep -rl niche_overlays workflows/` → 8 files, all core engine.
`grep -rl maxi_industries workflows/` → 2 files, both MAXI's own listing
endpoints, both `active: false`.

**Impact.** The multi-vertical requirement was never an architecture gap. Seven of
eight verticals simply had `icp_template`, `dashboard_labels` and
`routing_preferences` set to NULL. It was a data gap wearing an architecture
gap's clothes.

## ADR-002 — MAXI stays a marketing persona and product surface

**Decision.** MAXI is not promoted to vertical router, sales agent, or
intelligence store. Its catalogue is *linked* to the engine, not merged into it.

**Why.** MAXI owns 22 marketing industries and 168 value-prop copy rows — real
assets, but sales collateral, not engine configuration.

**Alternatives.** Make MAXI the vertical layer (rejected — would fork industry
config into a second store); delete MAXI's tables (rejected — 168 rows of
marketing copy with live public URLs).

**Evidence.** `avatars.MAXI` is `active=false` with no HeyGen or voice id;
`maxi_industries` carries only slug/name/category/description/emoji/sort_order —
no ICP, titles, signals, tone, or compliance. MAXI appears nowhere in the Sales
Engine (earlier hits were the word "Maximum").

**Impact.** One nullable FK, `maxi_industries.niche_overlay_id`. A NULL states
plainly "marketed but not operable" — 17 of 22 industries today.

## ADR-003 — the vertical capability is not named after MAXI

**Decision.** `get_vertical_context(vertical, client_id)`.

**Why.** MAXI is a brand and a product-grant key. Naming a data contract after a
persona welds marketing to schema and guarantees a rename.

**Alternatives.** `get_maxi_context()` / `run_maxi_workflow()` — both rejected;
the second also leaks implementation into the tool surface (see ADR-005).

**Impact.** Sales, Copilot, the agent runtime and MAXI are callers of equal
standing.

## ADR-004 — global industry knowledge and tenant learning stay separate

**Decision.** `niche_overlays` holds general industry knowledge.
`client_icp_profiles` holds per-tenant specifics. `get_vertical_context()`
returns the tenant layer under its own `tenant` key rather than merging.

**Why.** A merge makes it impossible to tell which is which, and one tenant's
outcomes could rewrite defaults for every other client in that industry.

**Evidence.** `niche_overlays` has 8 rows and no `client_id`; it is global by
construction.

**Impact.** "Roofers respond to permit signals" is global. "ABC Roofing converts
permit signals better by phone" is tenant. Restaurant learning can never
overwrite construction behaviour.

## ADR-005 — MCP tools express business capabilities, never workflow names

**Decision.** `get_vertical_context`, `discover_entities`, `create_quote` — never
`run_maxi_workflow` or `call_clx_city_scan_json`. Tools call existing
`admin/*`, `client/*`, `mga/*` endpoints and never reach Supabase directly.

**Why.** A tool that names a workflow pins the contract to today's
implementation. A tool that bypasses the command layer creates a second
permission model, which is exactly how the two existing gateways diverged.

**Impact.** Providers and workflows can be replaced without rewriting agents.

## ADR-006 — Sentinel stays independent

**Decision.** Sentinel is both a standalone subscription product and the
observability/guardrail layer. It reuses shared auth, billing and messaging, but
its monitoring, incident, alerting and remediation domain is **not** merged into
Admin, Copilot, MCP, or the agent runtime.

**Why.** A monitor that lives inside the thing it monitors cannot report that
thing's failure. This is not theoretical here: Sentinel's workflow-health
collector has 0 rows because it depends on the same n8n API that was down, and
that is precisely why the Sales Engine's June outage went unnoticed for months.

**Alternatives.** Fold Sentinel into Admin (rejected — loses independent
sellability and independent failure domain); let the agent runtime self-monitor
(rejected — same reason, worse).

**Impact.** Sentinel will monitor agents, MCP calls, tool denials and cost, but
from outside. It remains separately sellable.

## ADR-007 — Smart Quote is a multi-industry estimator

**Decision.** A generic quote core (request → validate → calculate → price →
version → status → accept) with per-industry estimator adapters. Insurance
carrier, suitability and regulated-review logic stays in the MGA product and
*consumes* the core rather than living inside it.

**Why.** Smart Quote already has the most recent genuine human usage on the
platform outside Sentinel — 50 marketplace quotes, last 2026-07-24. It is the
warmest surface available and is currently modelled as insurance-only.

**Impact.** Construction estimates, cleaning quotes and moving inventories become
adapters, not new products. **Not yet implemented** — recorded here so the
boundary is agreed before code is written.
