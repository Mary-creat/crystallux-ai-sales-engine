# Crystallux — Business Plan & Architecture Blueprint

> **Version 1.0** — April 18, 2026
>
> **Owner:** Adeshola Akintunde
> **Repository:** https://github.com/Mary-creat/crystallux-ai-sales-engine
> **Status:** Pre-revenue, platform foundation complete, first verticals ready to launch
>
> **Document purpose:** Single source of truth for what Crystallux is, what it sells, how it is structured, and how each vertical slot fits into the overall architecture. This is the strategic spine of the business. All future decisions reference this document.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [What Crystallux Is (and Isn't)](#2-what-crystallux-is-and-isnt)
3. [The Platform Vision](#3-the-platform-vision)
4. [The Full Service Catalog](#4-the-full-service-catalog)
5. [Crystallux MGA — A Separate, Vertical-Specific Business Line](#5-crystallux-mga--a-separate-vertical-specific-business-line)
6. [Target Verticals — Universal Platform Across Industries](#6-target-verticals--universal-platform-across-industries)
7. [Infrastructure & Architecture](#7-infrastructure--architecture)
8. [When to Separate Projects — Mono-Repo vs Multi-Repo Decision Framework](#8-when-to-separate-projects--mono-repo-vs-multi-repo-decision-framework)
9. [Pricing Framework](#9-pricing-framework)
10. [The 12-Month Execution Roadmap](#10-the-12-month-execution-roadmap)
11. [Financial Projections](#11-financial-projections)
12. [Risks & Mitigations](#12-risks--mitigations)
13. [Exit / Scale Options](#13-exit--scale-options)
14. [Operating Principles](#14-operating-principles)

---

## 1. Executive Summary

Crystallux is an **AI-powered growth operating system for professional service firms**, built as a multi-product platform on a single underlying data model. It serves any industry where the core business problem is: "find qualified prospects, build relationships, book meetings, close deals, manage a team."

The business has **two distinct but reinforcing arms**:

**A. Crystallux Platform** — a vertical-agnostic SaaS product serving many industries through tuned configurations. Five productized services share one codebase.

**B. Crystallux MGA** — a licensed Managing General Agency in Ontario's insurance market. Uses the Crystallux Platform as its proprietary competitive moat to recruit sub-agents that no other MGA can match.

**Near-term revenue target:** $50-70K MRR within 90 days across both arms.

**24-month ARR target:** $3-7M with team under 10 people.

**Unique competitive position:** The combination of a working AI platform + licensed MGA + licensed advisor credibility is not replicable by any current competitor in the Canadian market.

---

## 2. What Crystallux Is (and Isn't)

### What Crystallux IS

- A **platform** that runs multiple productized services from one backend
- A **vertical-agnostic** system, configurable to serve any professional service industry
- A **revenue-generating** machine with multiple SKUs at multiple price points
- An **AI-first** operation using Claude, Apollo, Google Maps, and other APIs as commodity inputs
- A **distributable** platform that can be licensed, white-labeled, or deployed to new clouds

### What Crystallux IS NOT

- Not a single point-solution tool
- Not a commodity outbound agency
- Not dependent on any single vertical for survival
- Not architecturally locked to one cloud provider
- Not a lifestyle business — the architecture supports 8-9 figure scale

### The Founder Lens

The founder (Adeshola) is a licensed Ontario insurance broker AND holds an MGA license. This creates an unusual hybrid:

- Tech platform founder (building Crystallux)
- Insurance industry insider (running Crystallux MGA)
- Both positions inform and strengthen each other
- Neither business is the other's parent — they operate as sister companies

---

## 3. The Platform Vision

### Core Principle

**One codebase. One database. Multiple productized services. Multiple vertical editions.**

This is the pattern used by HubSpot (marketing → sales → service → CMS), Salesforce (multiple clouds), ServiceTitan (one HVAC platform expanded to 12+ trades), and Toast (restaurant platform expanding to retail). The platform approach is what separates lifestyle-scale SaaS from venture-scale SaaS.

### The Platform Layer Stack

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENT INTERFACE LAYER                │
│  Dashboard • Client Portal • Reports • Billing • Auth    │
└────────────────────────┬────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    PRODUCT LAYER                         │
│  Pipeline • Content • Coach • Manager • Operator         │
└────────────────────────┬────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    DELIVERY LAYER                        │
│  Email • LinkedIn • WhatsApp • SMS • Voice • Video       │
│  Booking (Calendly) • Reply handling                     │
└────────────────────────┬────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    CONTENT LAYER                         │
│  Personalization engine • Carousel generator             │
│  Video scripts (HeyGen) • Voice scripts (ElevenLabs)     │
│  Research & signal detection                             │
└────────────────────────┬────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│                  ORCHESTRATION LAYER                     │
│  Discovery Orchestrator • Market Intelligence Engine     │
│  Routing rules • Signal detection • Credit management    │
└────────────────────────┬────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    DISCOVERY LAYER                       │
│  Google Maps • Apollo.io • LinkedIn • Yelp • Reddit      │
│  Crunchbase • Industry directories • Social scrapers     │
└────────────────────────┬────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│                    DATA LAYER                            │
│  Supabase/Postgres • 25+ tables • RLS • RPCs             │
│  Same database serves all products, all verticals        │
└─────────────────────────────────────────────────────────┘
```

---

## 4. The Full Service Catalog

Crystallux sells **five distinct productized services**. Each is a complete, standalone offering. Each can be sold individually or bundled. All share the same underlying platform.

### Service 1 — Crystallux Pipeline

**What it is:** Done-for-you AI sales engine. Discovery → research → personalized outreach → booking. Delivers 15-50 qualified meetings per month depending on tier.

**Who it is for:** Individual professionals and firms whose primary pain is "I need more qualified prospects to show up in my calendar."

**Target customers:** Insurance brokers, real estate agents, mortgage brokers, financial advisors, law firms (PI, immigration, family), CPAs, B2B SaaS founders, marketing agencies, consultants.

**Pricing tiers:**
- **Starter — $1,497/mo** — 10-15 booked meetings, single vertical, single geography, 60-day commit
- **Growth — $2,997/mo** — 20-30 booked meetings, up to 3 cities, dedicated Slack, 90-day commit *(default tier)*
- **Scale — $5,997/mo** — 50+ booked meetings, multi-vertical or national, weekly strategy calls, 6-month commit

**Guarantee:** Minimum 10 booked meetings in month one or next month is free.

---

### Service 2 — Crystallux Content

**What it is:** AI-powered content generation at scale. Emails, follow-up sequences, LinkedIn posts, carousel content, video scripts, social media assets — all personalized to the client's brand and audience.

**Who it is for:** Marketing teams, solo operators, agencies, thought leaders, anyone whose growth depends on consistent content output but lacks time to produce it.

**Target customers:** Agencies reselling content as a service, consultants building personal brand, coaches, founders doing inbound marketing, real estate agents running social campaigns.

**Pricing tiers:**
- **Creator — $497/mo** — 20 pieces of content per month (emails, social posts), single brand
- **Professional — $1,497/mo** — 100 pieces, multi-platform (LinkedIn + Instagram + X), carousel generation, video scripts
- **Agency — $2,997/mo** — Unlimited, up to 5 brands, white-label capability

---

### Service 3 — Crystallux Coach

**What it is:** AI-powered coaching and accountability system. Goal setting, calendar coaching, weekly check-ins, time management guidance, industry-specific playbooks. For solo operators who need structure and coaching but can't afford a human coach.

**Who it is for:** Solo professionals, newly licensed advisors, freelancers, solo consultants, anyone working independently who needs accountability and structure.

**Target customers:** Solo brokers, advisors in first 2 years, freelance professionals, coaches' clients (bulk purchase by coaches).

**Pricing tiers:**
- **Self-Directed — $197/mo** — AI coach, goal tracking, weekly accountability, resource library
- **Guided — $497/mo** — AI coach + monthly live group coaching call, calendar optimization
- **Executive — $997/mo** — Everything above + quarterly 1-on-1 with human coach (Adeshola or contracted coach)

---

### Service 4 — Crystallux Manager

**What it is:** AI team management intelligence for leaders. Daily briefings on team productivity, leaderboards, alerts on at-risk team members, accountability tracking, performance reviews — all automated.

**Who it is for:** Any leader with 5+ revenue-generating team members. Makes "managing by signal" possible instead of "managing by intuition."

**Target customers:** Insurance MGAs, brokerage principals, real estate team leads, sales managers, franchise operators, multi-office professional practices.

**Pricing tiers:**
- **Team — $497/mo per team of up to 10** — Productivity tracking, basic leaderboards, weekly reports
- **Manager — $1,497/mo per team of up to 25** — Full AI Manager briefings, alerts, goal cascade, coaching integration
- **Director — $2,997/mo per organization up to 100** — Multi-team, rollup reporting, custom KPIs, white-label

---

### Service 5 — Crystallux Operator (Enterprise Bundle)

**What it is:** The full suite. Pipeline + Content + Coach + Manager combined into one enterprise offering. Typically sold to organizations that need end-to-end growth operations.

**Who it is for:** MGAs, large brokerages, franchise networks, multi-location service businesses, professional associations offering services to members.

**Pricing tiers:**
- **Business — $5,997/mo** — Up to 15 team members, 2 verticals, all products
- **Enterprise — $9,997/mo** — Up to 50 team members, any verticals, priority support
- **Partner — $14,997-25,000/mo** — Unlimited, white-label, dedicated success manager, API access, custom integrations

---

### Cross-Product Table

| Service | Primary Use Case | Target Industry Breadth | Monthly Price Range |
|---|---|---|---|
| Pipeline | "Fill my calendar" | All | $1,497 – $5,997 |
| Content | "Produce my content" | All | $497 – $2,997 |
| Coach | "Structure my day" | Solo professionals | $197 – $997 |
| Manager | "See my team" | Team leaders (5+) | $497 – $2,997 per team |
| Operator | "Run everything" | Mid-market firms | $5,997 – $25,000 |

### Add-on intelligence tiers

Layer on top of any service tier; sold per-client per month.

| Tier | Feature | Price (CAD/mo) | Spec |
|------|---------|----------------|------|
| B | Productivity tracking + supervisor dashboard | $1,000 | [OPERATIONS_HANDBOOK §32](OPERATIONS_HANDBOOK.md) |
| C | Listening Intelligence (live transcript + post-call coaching) | $2,500 | [OPERATIONS_HANDBOOK §33](OPERATIONS_HANDBOOK.md) |
| **D** | **Behavioral Intelligence (per-lead signal monitoring + triggered outreach)** | **$1,500 – $3,500** | [OPERATIONS_HANDBOOK §35](OPERATIONS_HANDBOOK.md) |

Tier D is the differentiator: where Pipeline finds *who* to talk to and Listening Intelligence improves *what* gets said on the call, Behavioral Intelligence decides *when* to reach out. It works for **every vertical Crystallux serves** (insurance, real estate, mortgage, dental, consulting, construction, legal, financial advisors, agencies, more). It monitors 10 categories of person-level signals (life events, business changes, industry news, sports, news mentions, social activity, vertical-specific events such as policy renewals or property listings or treatment plans, financial milestones, geographic moves, internal calendar gaps) and either auto-sends or surfaces a triggered outreach for advisor approval. Vertical-tuning happens through `niche_overlays`, not code: a real-estate agent gets "listing-window" triggers; an insurance broker gets "renewal-window" triggers; a dentist gets "recall-due" triggers — same engine. The MGA business line ([§5](#5-crystallux-mga--a-separate-vertical-specific-business-line)) ships Behavioral Intelligence bundled into every sub-agent contract — it's *one* expression of the same universal feature.

---

## 5. Crystallux MGA — A Separate, Vertical-Specific Business Line

### Why This Section Exists Separately

The Crystallux Platform (Section 4) serves **all industries**. Crystallux MGA is specifically an **insurance distribution business** operating in Ontario. It is:

- A separate legal entity with its own licensing and compliance
- Operating in one vertical only (insurance)
- Using the Crystallux Platform as a proprietary tool, not as a product sold externally
- Generating revenue through carrier overrides, not SaaS subscriptions

**Think of it as:** Two sister companies. The platform is "sword for sale." The MGA is "an army built with the sword we own."

### What Crystallux MGA Is

A licensed Managing General Agency serving as an insurance distribution arm. Contracts with multiple carriers. Recruits and supports sub-agents who sell insurance under the MGA umbrella. Earns override commissions on every policy sub-agents write.

### The MGA-Specific Value Proposition to Sub-Agents

Unlike traditional MGAs, Crystallux MGA offers sub-agents something no other Canadian MGA can match:

> "Join Crystallux MGA and the Crystallux Platform is included in your contract. We deliver 15-25 qualified insurance prospects to your calendar every month. You stop prospecting. You focus on closing."

This is a recruitment moat. Traditional MGAs compete on commission splits and back-office services. Crystallux MGA competes on **guaranteed pipeline** — a category of one.

### MGA Revenue Model

Three revenue streams from the MGA operation:

1. **Override commissions** — $100-300 per policy written by sub-agents, depending on product type and carrier contract
2. **Sub-agent production floor bonuses** — carriers pay the MGA additional volume bonuses based on total production
3. **Personal book of business** — founder continues writing own policies at full advisor commission

Sub-agents pay nothing for Crystallux Platform access — it's bundled into their MGA contract. This is not a cost to the MGA; it's a lead generation machine the MGA already owns.

### Financial Model — MGA Alone

Year 1 target:
- 10 sub-agents
- Average 5 policies/month per sub-agent
- $200 average override per policy
- **Monthly override revenue: $10,000**
- Plus founder's personal book: $5,000/month typical
- **MGA Year 1 MRR: ~$15,000 ($180K ARR)**

Year 2 target:
- 40 sub-agents, averaging 8 policies/month (production increases as agents mature on the platform)
- **Monthly override revenue: $64,000**
- **MGA Year 2 MRR: ~$69,000 ($828K ARR)**

Year 3 target:
- 100 sub-agents, averaging 10 policies/month
- **Monthly override revenue: $200,000**
- **MGA Year 3 MRR: ~$205,000 ($2.46M ARR from MGA alone)**

### Sub-Agent Recruitment Targets

1. **Struggling licensed advisors** — highest conversion (desperate for leads)
2. **Mid-tier advisors at other MGAs** — medium conversion, highest lifetime value
3. **Newly licensed advisors** — volume play (need everything: leads, coaching, structure)
4. **Retiring advisors** — book acquisition opportunities (buy their book, transition clients)

### MGA Requirements & Compliance

The founder already holds the MGA license. The separate business entity must maintain:

- FSRA (Financial Services Regulatory Authority of Ontario) licensing
- E&O insurance (typically $2M+ aggregate)
- Minimum 2-3 active carrier contracts (life, disability, critical illness, at minimum)
- Written compliance program (KYC, AML, complaint handling, privacy)
- Sub-agent contracts with proper client ownership clauses (critical — see below)
- CE tracking for all sub-agents
- Record keeping compliant with FSRA requirements

### Critical Contract Clause — Client Ownership

Sub-agent contracts must specify: **Leads generated through Crystallux Platform remain property of Crystallux MGA, not the sub-agent.** If a sub-agent leaves, they cannot take platform-generated prospects with them.

This is non-negotiable. Without this, sub-agents would use you for 12 months then walk with your assets. A licensed insurance regulatory lawyer must draft these contracts.

### How MGA and Platform Interact

```
┌─────────────────────────────────────────┐
│         CRYSTALLUX PLATFORM             │
│   (Sold externally to any industry)     │
└────────────────┬────────────────────────┘
                 │ "Licensed internally to"
                 ▼
┌─────────────────────────────────────────┐
│         CRYSTALLUX MGA                  │
│   (Uses platform for own sub-agents)    │
│                                         │
│   Sub-agents get platform access        │
│   bundled in MGA contract               │
└─────────────────────────────────────────┘
```

The MGA is essentially the platform's most evangelical customer — its own best case study.

---

## 6. Target Verticals — Universal Platform Across Industries

The Crystallux Platform is vertical-agnostic. Each new vertical requires:

- Routing rule configuration
- ICP template
- Industry-tuned Claude prompts
- Vertical-specific landing page
- Pricing adjustment for industry norms

**No code changes.** Adding a new vertical is typically 1-3 days of work (mostly content and configuration).

### Tier 1 — Immediate High-Fit Verticals

| Vertical | Monthly Price Range | Why This Works |
|---|---|---|
| Insurance brokers (life, P&C, group) | $1,497 – $5,997 | Founder's home vertical, licensing insider, high LTV |
| Real estate agents & teams | $1,497 – $5,997 | Lead-obsessed, $10K+ commissions, massive TAM |
| Mortgage brokers | $1,497 – $5,997 | Natural adjacency to insurance, regulated, relationship-driven |
| Financial advisors & wealth managers | $2,997 – $9,997 | High-ticket clients, premium tier, compliance matters |
| Law firms (PI, immigration, family) | $1,497 – $5,997 | Attorneys pay for qualified leads reliably |

### Tier 2 — Medium-Fit High-Volume Verticals

| Vertical | Monthly Price Range | Notes |
|---|---|---|
| Accounting firms / CPAs | $1,497 – $2,997 | Seasonal (tax season), market intelligence key |
| B2B SaaS (pre-Series A) | $2,997 – $5,997 | Apollo integration essential |
| Marketing agencies | $1,497 – $2,997 | Often become reseller partners |
| Consulting firms | $1,497 – $2,997 | Carousel Content upsell fits perfectly |
| Medical practices (private) | $997 – $2,997 | Dentists, plastic surgeons, chiropractors, clinics |

### Tier 3 — Lower-Margin Higher-Volume Verticals

| Vertical | Monthly Price Range | Notes |
|---|---|---|
| Home services (HVAC, plumbing, roofing) | $497 – $1,997 | Price-sensitive, high volume, smaller tickets |
| Fitness & wellness | $497 – $1,997 | Instagram-heavy, Content product upsell |
| Restaurants & hospitality | $297 – $997 | Yelp-driven, volume compensates |
| Recruiters & staffing firms | $1,497 – $5,997 | Natural fit — they sell meetings |

### Tier 4 — Require Custom Work (Future)

- Enterprise B2B (long sales cycles, multi-stakeholder)
- Healthcare providers (HIPAA compliance needed first)
- US Financial services (regulatory scrutiny on cold outreach)
- Education / universities
- Non-profits / political campaigns

### Vertical Launch Sequence

**Year 1, Phase 1 (Months 1-3):** Insurance brokers only (Ontario). Beachhead.

**Year 1, Phase 2 (Months 4-6):** Add real estate agents and mortgage brokers (Canada). Natural adjacencies.

**Year 1, Phase 3 (Months 7-9):** Add financial advisors + law firms.

**Year 2:** Add accounting firms, B2B SaaS, marketing agencies. US market expansion.

**Year 3:** Add Tier 3 verticals at scale. UK/Australia expansion.

**Discipline:** No new vertical until the current vertical has 10 paying clients with proof points.

---

## 7. Infrastructure & Architecture

### Current Tech Stack

| Component | Technology | Hosting | Purpose |
|---|---|---|---|
| Database | Supabase (Postgres) | Supabase Cloud | All business data (leads, clients, content, team) |
| Workflow automation | n8n (self-hosted) | Hostinger VPS | All business logic orchestration |
| AI/LLM | Claude (Anthropic API) | Anthropic | Research, content gen, scoring, signal detection |
| Data discovery | Google Maps API, Apollo.io, others | External APIs | Lead sourcing |
| Email delivery | Gmail OAuth2, Google Workspace | Google | Outbound email |
| Voice (future) | Twilio + ElevenLabs | Twilio, ElevenLabs | Voice calls, voice AI |
| Video (future) | HeyGen API | HeyGen | Personalized video generation |
| Source control | GitHub | GitHub | Code, workflow JSONs, docs |
| Dev assistance | Claude Code | VPS terminal | Development + deployment |
| Payments (future) | Stripe | Stripe | Subscription billing |
| File storage (future) | Cloudflare R2 / AWS S3 | Cloudflare / AWS | Assets, videos, large files |

### Why This Stack

- **Supabase:** Postgres power, built-in REST API, RLS security, migration-friendly. Cloud-agnostic if needed to migrate.
- **n8n:** Workflows as JSON. Self-hostable, portable, versionable in git. No vendor lock-in.
- **Claude:** Best-in-class reasoning for research and content. API stable and portable.
- **Standard APIs everywhere:** Google Maps, Apollo, etc. are all standard REST. Swap providers if needed.

Every component is **cloud-portable** by design. No single piece locks the platform to one cloud provider.

### Data Model Foundation (25+ tables)

All data lives in one Supabase database, organized into logical layers:

**Lead & Platform Layer:**
- `leads`, `clients`, `client_subscriptions`, `client_icp_profiles`
- `scan_log`, `scan_errors`, `scan_query_tracker`, `pipeline_stats`

**Orchestration Layer:**
- `routing_rules`, `market_signals`, `platform_credits`, `discovery_jobs`
- `apollo_usage`, `mcp_tool_calls`

**Content Layer:**
- `content_assets`, `carousel_campaigns`, `video_assets`

**Delivery Layer:**
- `channel_credentials`, `delivery_log`

**Coaching Layer:**
- `coaching_sessions`, `client_goals`, `calendar_blocks`
- `accountability_checkins`, `client_onboarding`, `coaching_resources`

**Team Management Layer (powers both Manager product and MGA):**
- `team_members`, `productivity_metrics`, `team_goals`
- `leadership_alerts`, `team_activity_log`, `leaderboards`

**CRM Layer:**
- `deals`, `pipeline_stats`

Same schema serves every product. Same schema serves every vertical. Same schema serves Crystallux MGA's sub-agents and every external client.

---

## 8. When to Separate Projects — Mono-Repo vs Multi-Repo Decision Framework

This section addresses: **When do you create a separate project/repo, and when do you extend the existing one?**

### Default Rule — Keep Everything in One Repo Until Forced Apart

The current repository (`Mary-creat/crystallux-ai-sales-engine`) houses all platform code, workflows, documentation, and migrations. This is the right setup for now because:

- Single source of truth
- Atomic commits across layers
- Easy to refactor across boundaries
- One CI/CD pipeline
- Easier to onboard future collaborators

### Triggers That Justify Separating a Project Into Its Own Repo

Create a new, separate repository when one or more of these is true:

#### A. **Legal or Regulatory Separation Required**

The MGA is a **separate legal entity** with its own compliance requirements. Therefore:

**Create `crystallux-mga-ops`** as a separate repository when MGA operations grow beyond informal coordination.

Contents of `crystallux-mga-ops` repo:
- Sub-agent contract templates (legal documents)
- Compliance policies and procedures
- Carrier onboarding documentation
- MGA-specific dashboards
- FSRA filings and records
- Internal operational runbooks

**Why separate:** Regulatory auditors should be able to inspect MGA records without seeing unrelated platform code. Client ownership clauses are sensitive legal IP.

**Recommended action:** Create this repo in Month 3-4 when MGA operations formalize.

#### B. **Different Deployment Lifecycle**

If a component needs to deploy on a different schedule or to a different environment, it earns its own repo.

**Examples of components that deploy separately:**

- **Dashboard frontend** (already partially separated via `dashboard/` subdirectory). If it grows to a full React app with its own build pipeline, make it `crystallux-dashboard`.
- **Client portal** — when built, this is customer-facing and needs strict separation from internal tools. Create `crystallux-portal`.
- **Landing pages per vertical** — when you have 5+ vertical landing pages, they likely deserve their own static-site repo: `crystallux-marketing-sites`.

#### C. **Different Technology Stack**

When a component uses a fundamentally different technology that doesn't mix well with the rest:

- **Mobile apps** (if ever built) — separate iOS/Android repos
- **Native desktop apps** — separate repo
- **Python-based data science / analytics** — if you ever build a dedicated analytics engine in Python, separate repo

Current stack is consistent enough that this trigger does not apply yet.

#### D. **Different Ownership / Team**

Once you hire engineers, give different teams ownership of different repos to avoid merge conflicts and confusion.

**Example:** If you hire an operations lead for the MGA and a product engineer for the platform, each should own separate repos.

#### E. **White-Label or Licensing**

When Crystallux is licensed to external customers (white-label), the licensed customer should NOT have access to your entire codebase. Separate the "platform core" from "client deployments":

- **`crystallux-platform-core`** — internal only, all proprietary IP
- **`crystallux-deployment-template`** — public-ish, what licensed partners receive

This is a Year 2 concern, not now.

---

## 9. Pricing Framework

### Pricing Principles

1. **Three tiers per product, always.** Starter/Growth/Scale. The middle tier converts the majority.
2. **Never price below market anchors.** Cheap signals low value.
3. **Pricing is tied to outcome, not features.** "20 booked meetings" not "50,000 API calls."
4. **Annual plans get 2 months free.** Improves cash flow and commitment.
5. **Setup fee signals premium positioning.** $500-2,000 per new client, waived for founding clients.

### Price Escalation Policy

As the brand builds case studies and demand, prices increase. Lock in founding-client pricing for 12 months so early adopters are rewarded. New clients pay higher rates as proof accumulates.

### Pricing Modification for MGA Sub-Agents

Sub-agents of Crystallux MGA receive platform access bundled in their MGA contract at zero marginal cost to them. This is a competitive recruiting tool. The cost to the platform for including a sub-agent is negligible (same infrastructure, same APIs — marginal cost under $50/month per sub-agent).

**This is the moat.** A competing MGA would have to build or buy a platform to match. Neither is fast or cheap.

---

## 10. The 12-Month Execution Roadmap

### Quarter 1 (Months 1-3) — Beachhead

**Primary goal:** Prove Crystallux Pipeline works on insurance brokers. Earn first MRR.

**Month 1:**
- Fix all remaining Pipeline bugs (Discovery workflow, Research workflow)
- Ship first 10 cold outreaches
- Book first 2-3 discovery calls
- Close first founding client ($1,997/mo)

**Month 2:**
- Scale outreach to 50-100 cold contacts/week
- Close 3-5 total founding clients
- Reach $10K MRR from Pipeline
- Begin soft sub-agent recruitment conversations

**Month 3:**
- Scale Pipeline to 8-12 paying clients
- Reach $20-30K MRR from Pipeline
- Formalize first MGA sub-agent contracts (2-3 sub-agents recruited)
- First policies written under Crystallux MGA

**Q1 target: $25-35K MRR combined (Pipeline + MGA overrides)**

### Quarter 2 (Months 4-6) — Product Expansion + Second Vertical

**Primary goal:** Add Manager product, launch real estate + mortgage broker verticals.

- Launch Crystallux Manager (sold to brokerage principals and MGAs — including your own)
- Launch real estate vertical (Ontario)
- Launch mortgage broker vertical (Ontario)
- Scale MGA sub-agents to 8-12
- Reach $50-65K MRR combined

### Quarter 3 (Months 7-9) — Multi-Vertical + US Expansion

**Primary goal:** Scale to multiple verticals + first US clients.

- Launch financial advisor and law firm verticals
- Launch Crystallux Coach product (complement to Pipeline)
- First 5 US clients (Pipeline only — regulatory simplicity)
- Scale MGA sub-agents to 20-25
- Reach $90-120K MRR combined

### Quarter 4 (Months 10-12) — Scale Infrastructure + First Enterprise

**Primary goal:** Build operational scale. Close first Operator (enterprise) deal.

- Launch Crystallux Content as standalone product
- First white-label/Operator contract with an MGA or franchise ($10-15K/mo)
- Scale MGA to 30-40 sub-agents
- Hire first ops person (MGA operations manager)
- Reach $150-200K MRR combined

**End of Year 1: $150-200K MRR = $1.8-2.4M ARR run rate**

---

## 11. Financial Projections

### Revenue Assumptions

| Source | Month 3 | Month 6 | Month 9 | Month 12 |
|---|---|---|---|---|
| Pipeline clients (external) | 10 × $2,500 = $25K | 25 × $2,800 = $70K | 50 × $3,000 = $150K | 80 × $3,200 = $256K |
| Manager clients | — | 5 × $1,500 = $7.5K | 12 × $1,800 = $21.6K | 20 × $2,000 = $40K |
| Coach clients | — | — | 30 × $500 = $15K | 80 × $500 = $40K |
| Content clients | — | — | — | 20 × $1,500 = $30K |
| Operator (bundle) | — | — | — | 2 × $10K = $20K |
| **Platform MRR** | **$25K** | **$77.5K** | **$186.6K** | **$386K** |
| | | | | |
| MGA overrides | $3K | $10K | $25K | $50K |
| Founder personal book | $5K | $5K | $5K | $5K |
| **MGA MRR** | **$8K** | **$15K** | **$30K** | **$55K** |
| | | | | |
| **COMBINED MRR** | **$33K** | **$92.5K** | **$216.6K** | **$441K** |
| **ARR Run-Rate** | **$400K** | **$1.1M** | **$2.6M** | **$5.3M** |

These are aggressive but achievable targets given:
- Ontario broker market alone has 10,000+ licensed advisors
- Zero direct competitors offering this combination
- Founder's industry credibility
- Platform's cost structure (90%+ gross margin)

### Cost Structure

**Monthly operating costs at $100K MRR scale:**
- Claude API: $500-1,500
- Apollo subscription: $300
- Google Maps API: $500-1,000
- Hostinger VPS (n8n): $50
- Supabase: $25 (free tier likely fine)
- Stripe fees (3% of revenue): ~$3,000
- Domain/email (Workspace): $100
- E&O + compliance (MGA): $500
- Contract compliance officer (MGA): $2,000-3,000
- **Total fixed + variable: ~$8,000-9,000/month**

**Gross margin: ~91%**

**At $100K MRR, net profit before founder draw and taxes: ~$91K/month.**

This is an extremely capital-efficient business.

---

## 12. Risks & Mitigations

### Risk 1 — Founder Bandwidth

Running both Crystallux Platform and Crystallux MGA will exceed what one person can handle beyond Month 6-9.

**Mitigation:** Hire MGA operations manager at $40-50K MRR. Hire platform success manager at $80-100K MRR.

### Risk 2 — Regulatory Changes (Insurance)

FSRA rules change. CASL enforcement intensifies. Sub-agent contract enforceability challenged.

**Mitigation:** Maintain ongoing relationship with regulatory lawyer. Annual compliance audit. Build compliance buffer into pricing.

### Risk 3 — Claude API Dependency

Anthropic pricing could increase, rate limits tighten, or API becomes unreliable.

**Mitigation:** Abstract LLM calls behind a service layer. Ability to swap to OpenAI/others if needed. Architectural diversification within 12 months.

### Risk 4 — Email Deliverability

Cold outreach regulations tightening globally. Google/Microsoft reputation enforcement increasing.

**Mitigation:** Proper domain warmup. SPF/DKIM/DMARC correctly configured. Rotating sending identities. CASL unsubscribe automation. Avoid volume spikes.

### Risk 5 — Sub-Agent Attrition

A sub-agent who joins Crystallux MGA, learns from your playbook, and leaves to start their own MGA.

**Mitigation:** Proper contract (client ownership clauses). Non-compete for 12-18 months post-departure. Make staying more attractive than leaving (continuous platform improvements, higher splits for tenure).

### Risk 6 — Scale Before Product-Market Fit

Trying to launch multiple verticals before proving one.

**Mitigation:** Strict discipline — no new vertical until current vertical has 10 paying clients with documented case studies.

---

## 13. Exit / Scale Options

By Year 3, Crystallux could pursue multiple paths:

### Option A — Independent Cash Flow Business
- Run as private operating company
- $5-20M ARR at 85%+ margins
- Founder retains 100% ownership

### Option B — Strategic Acquisition
Potential acquirers:
- Insurance industry consolidators (Wawanesa, Intact, Manulife)
- SaaS platforms (HubSpot, Salesforce, ServiceTitan)
- MGA consolidators (PCF, Hub International)
- Private equity (insurance tech thesis)
- Valuation range: 6-12x ARR = $30-150M

### Option C — PE Recapitalization
- Sell majority stake to PE firm
- Take cash off the table
- Remain as CEO with growth equity
- Target valuation: 8-10x ARR

### Option D — VC-Backed Scale
- Raise Series A ($3-8M) at $25-60M valuation
- Scale nationally and internationally
- Target $50M ARR exit at $300-500M valuation
- Timeline: 5-7 years from Year 1

### Decision Criteria

The right option depends on founder goals. Document revisited annually.

---

## 14. Operating Principles

These principles guide all strategic and tactical decisions:

1. **Platform first, products second.** Never hard-code vertical logic where configuration suffices.
2. **Ship to revenue, not to perfection.** Every week without paying customer feedback is wasted.
3. **One vertical at a time.** No second vertical until 10 paying clients in the first.
4. **Legal compliance is non-negotiable.** Never cut corners on CASL, FSRA, or client ownership.
5. **Founder sells until Month 12.** No sales hires until product-market fit is undeniable.
6. **Documentation is a first-class output.** Every major decision gets a document in this repo.
7. **Separate project only when forced.** Default to monorepo until legal, deployment, or ownership reasons force separation.
8. **Every new platform/vertical must prove itself in 60 days.** No sunk cost discipline on failing experiments.
9. **MGA sub-agents and external clients share a platform but have separate economics.** Never commingle MGA commissions with platform revenue reporting.
10. **The founder stays technical long enough to understand every layer.** Delegation without understanding creates fragility.

---

## Appendix A — Related Documentation

This document is the strategic spine. Other documents in the repository complement it:

- `docs/architecture/OPERATIONS_HANDBOOK.md` — day-to-day operations, SQL queries, troubleshooting
- `docs/architecture/migrations/2026-04-18-full-platform-foundation.sql` — the complete data model
- `docs/strategy/B2B_B2C_STRATEGY.md` — industry classification and enrichment routing
- `docs/architecture/COST_ANALYSIS.md` — cost projections and unit economics
- `docs/mga/` — MGA-specific operational documents (create this directory)

## Appendix B — Version History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-18 | Initial complete business plan & architecture blueprint |

---

*End of document. This is living strategy. Update as the business evolves.*
