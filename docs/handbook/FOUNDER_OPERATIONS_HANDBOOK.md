# Crystallux Founder's Operations Handbook

> **Single source of truth for operating, understanding, and making decisions about the Crystallux platform.**
> **Last updated:** 2026-05-11
> **Maintainer:** Mary Akintunde, Founder

---

## How to use this handbook

**If you're stuck right now:**
1. First → **Section 4** (Emergency Procedures)
2. Second → **Section 3** (How to operate)
3. Third → **Section 7** (Decision Frameworks)
4. Last resort → contact a technical advisor or open Claude/Claude Code

**If you're new (employee, investor, technical advisor):**
1. Read **Section 1** (Strategic Context) — 20 min
2. Then **Section 2** (System Inventory) — 30 min
3. Reference everything else as needed
4. Estimated time to be "operational": 1-2 days for non-technical, 4-6 hours for technical

**If you're planning something:**
1. **Section 7** (Decision Frameworks)
2. **Section 5** (Roadmap & Recent Decisions)

**A note on this handbook:** It's deliberately written so a smart, non-technical person can read it cover-to-cover and understand the entire business. Avoid jargon where possible; when used, defined in **Section 8** (Glossary). If a sentence in here doesn't make sense, that's a bug — fix it next time you touch the file.

---

# SECTION 1 — Strategic Context

## 1.1 What Crystallux is

**Elevator pitch:** Crystallux is an AI-native sales engine for service businesses. It captures leads, conducts the conversation (voice, WhatsApp, SMS, email, video), books meetings, manages compliance, and follows up — all autonomously, around the clock, across any service vertical (insurance, mortgage, real estate, dental, beauty, logistics, agencies). One AI engine; one client base; one architecture. Insurance is the first vertical we own end-to-end.

**Three-layer architecture (memorize this):**

```
┌──────────────────────────────────────────────────────────┐
│  LAYER 3 — MARKETPLACE (Year 2-3 future)                 │
│  Other MGAs, agencies, brokerages license the platform   │
│  Crystallux earns marketplace fees                       │
└──────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────┐
│  LAYER 2 — VERTICAL MODULES (regulated business)          │
│  ┌────────────────┐  ┌────────────────┐  ┌─────────────┐ │
│  │ Insurance MGA  │  │ Mortgage MGA   │  │ Real Estate │ │
│  │ (LIVE today)   │  │ (Year 1-2)     │  │ (Year 2)    │ │
│  └────────────────┘  └────────────────┘  └─────────────┘ │
│  Each module = regulator + commission ledger + reviews   │
│  Tagged by vertical_id column on every table             │
└──────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────┐
│  LAYER 1 — UNIVERSAL CORE ENGINE (the SaaS)              │
│  AI Sales Agent · Behavioral Intelligence · Video        │
│  Pipeline · Multi-channel Delivery · Universal Auth      │
│  Used by every Layer 2 module + sold as standalone SaaS  │
└──────────────────────────────────────────────────────────┘
```

**Why this matters:**
- Layer 1 is a SaaS we sell to anyone (insurance brokers, mortgage brokers, real-estate agents, dental practices, beauty salons, logistics companies, agencies).
- Layer 2 modules are regulated businesses Crystallux *operates itself* (Crystallux Insurance Network is the first; Mary is the licensed principal). They use Layer 1 internally + add vertical-specific compliance.
- Layer 3 is the long-term marketplace: license the platform to other MGAs/agencies.

**Why we exist:** Service businesses spend the bulk of their operating cost on activities that AI can do better — qualifying leads, sending the right message at the right time, scheduling, follow-up, compliance paperwork. Crystallux replaces that operational middle. The advisor's job becomes *relationship + judgment*, not paperwork.

## 1.2 Business model

**Three revenue streams:**

1. **SaaS subscriptions** (Layer 1) — recurring monthly revenue from clients using the universal sales engine.
2. **MGA commissions** (Layer 2 Crystallux Insurance Network) — Mary's principal stake in the commission ledger of insurance policies sold through her advisors.
3. **Future marketplace fees** (Layer 3, Year 2-3) — % of revenue from other MGAs running on the platform.

**SaaS pricing tiers (from `client-dashboard/onboarding/index.html`):**

| Tier | Price/mo (CAD) | Promise | Target customer |
|---|---|---|---|
| **Starter** | $1,497 | 10-15 booked meetings/month | Solo broker, single-rep agency, dental practice |
| **Growth** | $2,997 | 20-30 booked meetings/month | 2-5 person team, growing agency |
| **Scale** | $5,997 | 50+ booked meetings/month | Larger agency, MGA, multi-location practice |

**Unit economics (approximate, illustrative):**
- Variable AI cost per active client per month: ~$30-50 (Claude tokens + HeyGen video + Twilio + Postmark + R2 storage). Detail in `docs/architecture/COST_ANALYSIS.md`.
- Gross margin at Growth tier: ~$2,800/mo per client ≈ 95%.
- Customer acquisition cost target: ≤ 3 months of subscription (one-month payback at Scale).

**Path to profitability:**
- Break-even on personal income: ~15-25 paying clients on Growth/Scale mix.
- Break-even on full overhead (employee + infrastructure scale): ~50-100 paying clients.
- Profitability at scale: > 100 clients → very high margin (pure software at that point).

## 1.3 Strategic positioning

**Who we compete with (and what we're not):**

| Competitor | What they do | Where we differ |
|---|---|---|
| **Salesforce** | Enterprise CRM | Not AI-native; thousands of $/seat/mo; configuration project to set up |
| **HubSpot** | Mid-market CRM + marketing automation | Not AI-native; multi-vertical generic, no per-vertical depth |
| **Send** (UK) | MGA-platform incumbent | UK-focused; not AI-native; no behavioral intelligence layer |
| **Cogitate** (US) | MGA-platform incumbent | Enterprise-focused; not AI-native; no per-lead personalisation |
| **Bold Penguin** | Commercial-lines insurance distribution | Single-product focus; not advisor-experience-led |
| **Scoop Insurance** | Digital brokerage (Canada) | They ARE the broker; we POWER the broker — different business model |

**What makes us different:**
1. **AI-native, not retrofitted.** Every workflow is built around Claude, behavioral intelligence, and HeyGen video. Competitors bolt AI onto existing systems.
2. **Multi-vertical foundation.** One engine, every service vertical via `vertical_id` tagging. Competitors are single-vertical.
3. **Behavioral signal → review → video pipeline.** Every life event (birthday, marriage, baby, new job, etc.) becomes a personalized 60-second video. **No traditional MGA has this.** Documented in `docs/insurance-mga/VIDEO_ENGAGEMENT_STRATEGY.md`.
4. **Audit trail by design.** Every regulated event lands in `regulatory_audit_log` (append-only). FSRA / FINTRAC / regulator request → one SQL query.
5. **The advisor's job changes shape.** From paperwork → relationship + judgment.

**Why customers buy us:**
- A solo broker can act like a 10-person team.
- A 10-person agency can act like a 50-person agency.
- An MGA can carry double the book per advisor.
- Every life event of every client becomes a real touchpoint, not a forgettable email.

**Who we serve:**
- Service businesses with paid advisors / brokers / agents / consultants
- Verticals: insurance, mortgage, real estate, dental, beauty, logistics, consulting, agencies, financial advisors, legal, construction
- Geographic focus: Canada first (FSRA + PIPEDA + CASL alignment baked in), USA next

## 1.4 Vision & roadmap (high-level)

**Year 1 (we are here, 0-12 months):**
- 50-100 paying SaaS customers
- $300K-$1M ARR
- 1-2 active carrier appointments (Crystallux Insurance Network MGA)
- First employee (likely customer success or compliance officer)
- Possibly raise seed

**Year 2 (12-24 months):**
- 200-500 customers
- Multi-vertical expansion (mortgage, real estate, dental at minimum)
- $1M-$5M ARR
- 3-5 active carrier appointments
- First MGA principal customer (other than Crystallux Insurance Network) running on platform — start of Layer 3
- Possibly Series A

**Year 3 (24-36 months):**
- 500-2,000 customers
- Marketplace functionality fully active (Layer 3)
- $5M-$15M ARR
- Multi-region (US expansion)
- Hiring meaningful eng + sales + CS team

**Year 5 (~48-60 months):**
- Category-defining player ("Salesforce for service verticals")
- $50M+ ARR
- Acquisition or growth-stage funding decision

**Decision: don't sell early.** At 10 clients the company is worth $500K-$3M. At 50-100 clients on the same platform it's worth $5M-$15M. At 200-500 clients it's $30M-$100M+. 18-24 months of patience = 5-10× more value at exit.

---

# SECTION 2 — System Inventory

## 2.1 Components we use

| Component | What it does | Why we chose it | Cost (~$/mo at this scale) | Login URL | If it goes down |
|---|---|---|---|---|---|
| **Supabase** | Postgres database + auth + storage | Hosted Postgres with great DX, free tier covers us until ~100 active clients | $0-25 | dashboard.supabase.com | All workflows fail. Critical. Check status.supabase.com. |
| **n8n** (self-hosted, Docker) | Workflow engine running 100+ workflows | Open-source, visual, self-hosted means no per-execution fees at our volume | $0 (VPS hosting only) | automation.crystallux.org (workflows live here) | All automation stops. Critical. SSH to VPS, `docker ps`. |
| **Cloudflare** | DNS + Pages (frontend hosting) + R2 (video storage) | Free CDN at our scale + R2 has no egress fees | $0-20 | dash.cloudflare.com | Sites unreachable. Check status.cloudflare.com. |
| **Anthropic** | Claude API (all AI calls) | The brain. No serious alternative for current Claude Sonnet 4.5 capability. | ~$30-100 | console.anthropic.com | All AI workflows fail. **Single point of failure.** Have a second key in cold standby. |
| **OpenAI** | Whisper transcription + text embeddings | Industry standard for both | ~$5-15 | platform.openai.com | Memory layer + voice transcription degrade. |
| **Stripe** | Billing + Identity verification (KYC) | The standard. Identity is bundled into the same account. | Pass-through (we charge customers) + $1.50/KYC | dashboard.stripe.com | Billing stops; new customer signups stuck. |
| **Postmark** | Transactional email | Reliable delivery + great inbox placement | $0-15 | account.postmarkapp.com | Auth emails fail; customer-facing emails fail. |
| **Twilio** | SMS + WhatsApp + Voice (via Vapi SIP) | Industry standard for telephony | ~$10-50 | twilio.com | SMS / WA / Voice agent fail. |
| **HeyGen** | Avatar video generation | Best lip-sync + custom-avatar capability | $29/mo Creator + pay-as-you-go API | app.heygen.com | Video pipeline stops. |
| **ElevenLabs** | Voice cloning for personas | Best voice quality + Vapi-compatible | $5/mo | elevenlabs.io | Voice agent uses default voice instead. |
| **Vapi** | AI voice agent infrastructure | Recommended over Retell per cost + integration ease (see `docs/agent/build-phases.md`) | ~$0.10/minute pay-as-you-go | vapi.ai | Voice agent down; SMS/WA continue. |
| **Cal.com** *(or Calendly)* | Booking | Open-source self-hostable option exists; flexible API | $0-12 | cal.com | Booking fails; existing meetings unaffected. |
| **Zoho Sign** | E-signature for disclosures | $8 flat/mo, simple OAuth | $8 | sign.zoho.com | Disclosure signing fails; manual workaround = email PDF. |
| **Apollo.io** | Lead generation (B2B sourcing) | Best price-to-quality at our scale | $50-100 | app.apollo.io | New B2B leads stop; existing pipeline continues. |
| **Hunter.io** | Email finding | Best price | $0-50 | hunter.io | Email enrichment fails; campaigns continue with fewer hits. |
| **Unipile** | LinkedIn DM (outreach + Phase 4 content) | Multi-platform social automation | Per-account | unipile.com | LinkedIn channel down; other channels continue. |
| **NewsAPI** | Market intelligence (news signal source) | Free tier covers us until ~50 clients | $0 | newsapi.org | Market Intelligence loses news feed; other signal sources continue. |
| **OpenWeather** | Market intelligence (weather signals — for triggered claim outreach) | Free tier covers us | $0 | openweathermap.org | Weather signals lost. |
| **Certn** *(Phase 5b)* | Background checks for advisor onboarding | Canadian-focused; FSRA-aligned | $30/check | certn.co | Manual background checks (slower); not blocking. |

**Key principle:** every external vendor we use is either (a) the clear category leader or (b) the right cost-to-quality at our stage. **No vendor lock-in we can't migrate from in <2 weeks** with the documented playbooks.

## 2.2 Domains & subdomains

All DNS managed via Cloudflare (account: Mary's).

| Domain | What lives there | Status |
|---|---|---|
| **crystallux.org** | Marketing site (`site/` folder) | Live |
| **app.crystallux.org** | Client dashboard (`client-dashboard/`) | Live |
| **admin.crystallux.org** | Admin dashboard (`admin-dashboard/`) | Live |
| **automation.crystallux.org** | n8n webhooks (the workflow engine) | Live |
| **mga.crystallux.org** | Insurance MGA dashboard (`insurance-mga-dashboard/`) | **Pending Cloudflare Pages deploy** |
| **videos.crystallux.org** | Cloudflare R2 custom domain for video files | Live |

Each dashboard is its own **Cloudflare Pages project**:
- Source: a folder in the git repo (e.g. `client-dashboard/`)
- Auto-deploys on push to `main`
- The Pages project for `mga.crystallux.org` needs to be created (one-time setup).

## 2.3 Credentials inventory

**This handbook does NOT contain actual credentials.** It documents where they live. Real credentials live in **Mary's password manager** (recommend 1Password).

**Locations:**

1. **n8n credential vault** (configured in n8n UI at `automation.crystallux.org`):
   - `Supabase Crystallux` (HTTP Header Auth — for service-role API calls)
   - `Supabase Crystallux Custom` (HTTP Custom Auth — for service-role with apikey + Bearer pattern)
   - `Stripe Crystallux` (HTTP Header Auth — Bearer for Stripe API)
   - `Twilio Crystallux` (HTTP Basic Auth — Account SID + Auth Token)
   - `Cloudflare R2` (AWS-type credential with R2 endpoint override)
   - `Postmark` (via env var only, not n8n credential)
   - `Anthropic API` (via env var only — `ANTHROPIC_API_KEY`)
   - `OpenAI API` (via env var only — `OPENAI_API_KEY`)

2. **VPS env file** (`/root/crystallux/n8n/.env`):
   - `ANTHROPIC_API_KEY`
   - `OPENAI_API_KEY`
   - `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` + `STRIPE_IDENTITY_WEBHOOK_SECRET`
   - `POSTMARK_API_TOKEN`
   - `INTERNAL_EMAIL_SECRET` (used by internal workflow-to-workflow calls)
   - `LICENSE_ENCRYPTION_KEY` (AES-256 key for encrypting advisor licenses/E&O policy numbers)
   - `HEYGEN_API_KEY` + `HEYGEN_WEBHOOK_SECRET` + `HEYGEN_AVATAR_*` (per-persona avatar IDs) + `HEYGEN_VOICE_*`
   - `ELEVENLABS_API_KEY`
   - `VAPI_API_KEY` + `VAPI_ASSISTANT_ID` + `VAPI_PHONE_NUMBER_ID` + `VAPI_SIP_URI`
   - `R2_ACCESS_KEY_ID` + `R2_SECRET_ACCESS_KEY` + `R2_ENDPOINT` + `R2_BUCKET` + `R2_PUBLIC_URL`
   - `CALCOM_API_KEY` + `CALCOM_DEFAULT_EVENT_TYPE_ID`
   - `TWILIO_ACCOUNT_SID` + `TWILIO_SMS_FROM` + `TWILIO_WHATSAPP_FROM`
   - `ZOHO_SIGN_TOKEN` + `ZOHO_SIGN_WEBHOOK_SECRET`
   - `NEWSAPI_KEY`, `OPENWEATHER_API_KEY`
   - `N8N_INTERNAL_BASE` (typically `http://localhost:5678`)
   - `N8N_PUBLIC_BASE` (typically `https://automation.crystallux.org`)
   - `LANDING_PAGE_BASE`, `LANDING_PAGE_TRACKER_BASE`

3. **Cloudflare account** — Mary's login. All Pages projects, DNS, R2, and Workers (if any) under this account.

4. **Stripe account** — Mary's login. Customer Portal, Identity verification, webhooks all configured here.

5. **Supabase project** — `zqwatouqmqgkmaslydbr.supabase.co`. Mary's login.

6. **VPS** — SSH key on Mary's laptop. Server access via `ssh root@<vps-ip>`. n8n container running in Docker.

**Discipline:** when a credential rotates, update the env file AND the password manager AND a 1-line entry in `docs/journal/SESSION_LOG.md` (just date + "rotated `<name>`").

## 2.4 Database structure (plain English)

The database has ~30 tables across 9 migrations. Grouped by purpose:

**Authentication / users:**
- `auth_users` — every person who can log in (admins, clients, advisors, sub-agents, supervisors, compliance officers). Has a `user_role` field.
- `team_members` — sub-users under a paying client + their reports-to chain.

**Lead generation engine (universal):**
- `leads` — every lead Crystallux has ever discovered.
- `clients` — every paying SaaS customer (or Crystallux Insurance Network internally).
- `niche_overlays` — per-vertical configuration (currently insurance).
- `market_signals_raw` + `market_signals_processed` — Market Intelligence pipeline.

**AI Sales Agent (universal Layer 1):**
- `agent_decisions` — every choice the agent makes + reasoning.
- `agent_actions` — every message sent, call placed.
- `agent_conversations` — per-channel thread state.
- `agent_memory` — pgvector-backed semantic memory (1536-dim embeddings).
- `agent_escalations` — human handoff queue.
- `agent_performance` — daily count rollup per client.
- `agent_costs` — per-vendor cost ledger.
- `agent_personalities` — per-client tone tuning.
- `agent_channels_enabled` — per-client per-channel switches.
- `agent_schedules` — quiet hours, caps, timezone.

**Behavioral Intelligence (universal Layer 1):**
- `behavioral_signals` — every detected life event per lead.
- `signal_archetypes` — per-vertical compound trigger patterns (`UNIQUE(niche_name, archetype_name)`).
- `behavioral_triggers` — fired triggers per lead.
- `signal_subscriptions` — per-client opt-in matrix.

**Video & delivery (universal Layer 1):**
- `video_renders` — every HeyGen render's lifecycle.
- `video_engagement` — landing-page analytics.
- `messages_sent` — universal channel send log.
- `bookings` — Cal.com / Calendly normalized bookings.

**Content marketing (Layer 1, Phase 4 schema only — workflows deferred):**
- `content_topics`, `content_videos`, `content_publications`, `content_engagement`, `client_content_preferences`.

**Insurance MGA Layer 2 Part A — compliance:**
- `compliance_reviews` — every AI compliance check + human override.
- `kyc_verifications` — Stripe Identity lifecycle.
- `suitability_assessments` — AI conversational needs analysis.
- `policy_recommendations` — AI-ranked carrier products.
- `compliance_disclosures` — required CASL/PIPEDA/FSRA disclosures.
- `regulatory_audit_log` — append-only event log (7-year retention).
- `policy_applications` — auto-completed carrier application.

**Insurance MGA Layer 2 Part B — operations:**
- `mga_hierarchy` — principal/parent/child advisor relationships.
- `advisor_licenses` — license + CE tracking (encrypted).
- `advisor_eo_insurance` — E&O coverage (encrypted).
- `carrier_appointments` — per-advisor carrier authorizations + commission splits.
- `commission_ledger` — per-policy commission allocation in cents.
- `advisor_onboarding` — 5-step onboarding lifecycle.
- `policy_reviews` — **the central abstraction** — 7 review types.
- `review_tasks` — sub-tasks per review.
- `video_review_templates` — 12 trigger-event-specific scripts.

**Vertical tagging:**
- Layer 1 universal tables have NO `vertical_id` column (they're vertical-agnostic).
- Layer 2 insurance tables ALL have `vertical_id text NOT NULL DEFAULT 'insurance'` + an `idx_*_vertical` index.
- Same Layer 2 tables will serve future mortgage / real estate / etc. with their own `vertical_id` value. No schema migration needed.

Full schema lives in `db/migrations/` (9 SQL files, all applied to Supabase per night notes).

**Approximate size at scale:**
- At 100 paying clients × 1,000 leads each = ~100K leads
- `regulatory_audit_log` at scale: ~100K events/year/active-MGA client (recommend partitioning by month at 5-10 active MGA clients per `docs/audit/2026-05-11-comprehensive-audit.md`).

## 2.5 Workflow inventory

Workflows are organized in two locations:

**Top-level `workflows/` folder (50 files):** legacy workflows including the 7 protected v2/v3 production-active set + the 8 dormant §29-§34 cluster (calendar, daily plan, no-show, route, productivity, listening intelligence, real-time script suggester). **Don't touch the protected v2/v3 — they run the lead-generation engine in production.**

**`workflows/api/` (95 files in 11 subfolders):**

| Folder | Files | Layer | Purpose |
|---|---|---|---|
| `auth/` | 8 | 1 | Login / logout / magic-link / password reset / welcome / session validation |
| `admin/` | 9 | 1 | Admin dashboard data webhooks |
| `client/` | 11 | 1 | Client dashboard data webhooks (incl. 2 copilot/assistant) |
| `email/` | 1 | 1 | Postmark generic sender (`clx-email-send`) |
| `agent/` | 8 | 1 | AI Sales Agent (decision engine, action executor, voice in/out, conversation handler, memory, escalation, daily summary) |
| `intelligence/` | 5 | 1 | Behavioral Intelligence (ingestion, classify, trigger engine, archetype seed, learner) |
| `video/` | 7 | 1 | Video pipeline (script-gen, HeyGen render, callback, delivery router, landing page, engagement tracker, storage cleanup) |
| `messaging/` | 3 | 1 | WhatsApp send, SMS send, Twilio status callback |
| `booking/` | 1 | 1 | Cal.com booking create |
| `mcp/` | 1 | 1 | MCP agent-tools gateway |
| `insurance-mga/` | 41 | 2 | Insurance MGA (Part A 12 + Part B 29) |

**Total in the repo: 145 workflows.**

**Active vs dormant:**
- 7 protected production workflows are ACTIVE in n8n.
- All `workflows/api/` workflows ship with `active: false` (dormant). They are imported into n8n but must be flipped ON deliberately by Mary in the n8n UI.
- The 41 Layer 2 workflows are imported per night notes (2026-05-10) but ALL DORMANT until activation.

**When to activate:** see Section 3.4 and the per-commit activation checklists in `docs/journal/SESSION_LOG.md`.

## 2.6 External services (criticality matrix)

| Service | Monthly cost | Criticality | What breaks if down |
|---|---|---|---|
| Anthropic | $30-100 | **CRITICAL** | All AI workflows |
| Supabase | $0-25 | **CRITICAL** | All workflows + dashboards |
| Cloudflare (Pages + DNS + R2) | $0-20 | **CRITICAL** | All dashboards + video files inaccessible |
| n8n (self-hosted on VPS) | $20-40 VPS only | **CRITICAL** | All automation |
| Twilio | $10-50 | High | SMS + WA + voice agent |
| Postmark | $0-15 | High | All transactional email |
| Stripe | Pass-through | High | Billing + KYC |
| HeyGen | $29 + pay-as-you-go | High | Video pipeline |
| Apollo.io | $50-100 | Medium | New lead sourcing (existing pipeline continues) |
| Hunter.io | $0-50 | Low | Email enrichment |
| OpenAI | $5-15 | Medium | Memory + Whisper |
| Vapi | Pay-as-you-go | Medium | Voice agent only |
| Zoho Sign | $8 | Medium | Disclosure signing |
| Cal.com | $0-12 | Medium | New bookings (existing unaffected) |
| Unipile | Per-account | Low | LinkedIn channel only |
| NewsAPI / OpenWeather | $0 | Low | Some market signals |
| ElevenLabs | $5 | Low | Voice cloning quality |
| Certn (Phase 5b) | $30/check | Low | Manual workaround |

Approximate total external services cost at 10 paying clients: ~$200-400/mo. At 100 clients: ~$1,500-3,000/mo. Detail: `docs/architecture/COST_ANALYSIS.md`.

---

# SECTION 3 — How to operate

## 3.1 Daily routine (5 min, every morning)

Open these 5 tabs in this order:

1. **Cloudflare** → `dash.cloudflare.com` → Workers & Pages → glance at each project (admin/client/site/mga) for "live" status.
2. **n8n** → `automation.crystallux.org` → click on `Executions` in left nav → scan for any rows tagged "Error" or "Failed" in the last 24h.
3. **Supabase** → `app.supabase.com` → SQL Editor → run `SELECT count(*) FROM scan_errors WHERE created_at > now() - interval '24 hours';` — should be 0 or very low.
4. **Stripe** → `dashboard.stripe.com` → glance at Disputes + Failed Payments (top of dashboard) — anything new?
5. **Email** (Crystallux inbox + Postmark dashboard at `account.postmarkapp.com`) — any customer issues? any bounced emails?

If everything's green: close tabs, get to work. **Total: 5 minutes.**

## 3.2 Weekly routine (30 min, every Monday)

1. **Previous week's lead generation numbers.** Run in Supabase:
   ```sql
   SELECT count(*) AS leads_added, count(*) FILTER (WHERE lead_status='Booked') AS booked
     FROM leads WHERE date_created > now() - interval '7 days';
   ```
2. **New customer signups** — open admin dashboard → Onboarding pipeline page → review the 5-stage rollup.
3. **Compliance audit log** — for any active MGA client, in Supabase:
   ```sql
   SELECT event_type, count(*) FROM regulatory_audit_log
   WHERE occurred_at > now() - interval '7 days' AND vertical_id='insurance'
   GROUP BY event_type ORDER BY count DESC;
   ```
   Look for anomalies (lots of `compliance_review_failed` events = problem).
4. **Carrier appointment renewals 30 days out**:
   ```sql
   SELECT advisor_id, carrier_name, expires_date
   FROM carrier_appointments WHERE vertical_id='insurance' AND status='active'
     AND expires_date BETWEEN now() AND now() + interval '30 days';
   ```
5. **Update `CRYSTALLUX_STATUS.md`** if anything material changed (new vendor, new credential, new vertical onboarded).

## 3.3 Monthly routine (2 hours, every 1st of month)

1. **Revenue + churn + growth** — Stripe dashboard → Reports → MRR, churn, net revenue retention.
2. **Infrastructure cost vs revenue** — sum all vendor bills, compare to MRR. Target: vendor cost ≤ 5% of MRR.
3. **Pending compliance reviews** — run:
   ```sql
   SELECT review_type, count(*) FROM compliance_reviews
   WHERE status='human_review_required' GROUP BY review_type;
   ```
   Aim for zero backlog at end of month.
4. **Next month's priorities** — block 30 min to write a 3-bullet "what matters most this month" into a fresh `docs/journal/2026-MM-DD-monthly-priorities.md`.
5. **Roadmap update** — touch `Section 5.3` of this handbook + `CRYSTALLUX_STATUS.md`.

## 3.4 Common operations (step-by-step)

### How to add a new paying client
1. Customer hits `app.crystallux.org/onboarding/` → 4-step wizard → Stripe checkout.
2. Stripe webhook fires `clx-stripe-webhook-v1` → creates `clients` row + `auth_users` row.
3. Mary verifies in Supabase: `SELECT id, client_name, status FROM clients ORDER BY created_at DESC LIMIT 5;`
4. Optionally promote a user to `team_member` (or for an MGA client, to `mga_principal` / `advisor`).
5. Set the client's `niche_name` if not already set: `UPDATE clients SET niche_name='insurance' WHERE id=$1;`
6. Activate relevant per-client feature flags (e.g. `behavioral_intel_enabled`).

### How to add a new advisor (insurance MGA only)
1. Mary logs in as `mga_principal` at `mga.crystallux.org`.
2. POSTs to `/webhook/mga/insurance/advisor-onboarding-start` with `{ email, full_name, phone, jurisdiction, internal_secret }` → creates `auth_users` + `advisor_onboarding` row → sends welcome email.
3. Advisor receives welcome email with link to onboarding portal.
4. Advisor uploads license + E&O proof (license_number is AES-256-GCM encrypted at insert).
5. Mary creates one or more `carrier_appointments` for the advisor (with commission splits summing to 100).
6. Mary completes background check (currently manual; Phase 5b automates via Certn).
7. Mary POSTs to `/webhook/mga/insurance/onboarding-complete` → if ALL 5 steps complete, advisor is approved and user goes live.

### How to check workflow status
- n8n → `automation.crystallux.org` → Workflows → search by name → click → see "Active" toggle + last execution time.
- Or via terminal: `docker exec n8n n8n list:workflow | grep <name>`

### How to view audit log
Plain SQL in Supabase. For a specific client:
```sql
SELECT event_type, performed_by_role, occurred_at, event_data
FROM regulatory_audit_log
WHERE client_id = '<uuid>' AND vertical_id='insurance'
ORDER BY occurred_at DESC LIMIT 200;
```

### How to run a SQL query in Supabase
1. `app.supabase.com` → your project → **SQL Editor** (lightning-bolt icon in left nav).
2. Paste query → click **Run** (Ctrl+Enter).
3. Results appear below.
4. For destructive queries (UPDATE/DELETE), wrap in a transaction first: `BEGIN; ... ROLLBACK;` to preview, then re-run with `COMMIT;`.

### How to restart n8n if needed
SSH into VPS:
```bash
ssh root@<vps-ip>
cd /root/crystallux/n8n
docker compose -f docker-compose.prod.yml restart n8n
```
Watch logs for 30s:
```bash
docker compose -f docker-compose.prod.yml logs -f n8n
```
Wait for `Editor is now accessible via:` line. n8n is back up.

### How to deploy a code change (frontend)
1. Make edits in the repo locally (or via Cursor/IDE).
2. `git add <files> && git commit -m "what changed and why"`
3. `git push origin scale-sprint-v1`
4. Cloudflare Pages auto-deploys within 1-2 min.
5. **Cache purge if needed:** Cloudflare dashboard → Pages project → Caching → Purge Cache.

### How to deploy a workflow change
1. Edit JSON in `workflows/api/<folder>/<file>.json`.
2. `git push`.
3. SSH to VPS: `cd /root/crystallux/n8n && git pull`.
4. Re-import: `docker exec n8n n8n import:workflow --separate --input=/tmp/workflows/api/<folder>`.
5. In n8n UI, deactivate the old version of the workflow + activate the new one (n8n imports as deactivated by default).

### How to check Cloudflare DNS
- `dash.cloudflare.com` → choose `crystallux.org` → **DNS** → confirm A/CNAME records are correct.
- All A records should point to either Cloudflare proxy (orange cloud icon ON) or the VPS IP for `automation.crystallux.org` (orange cloud icon OFF — n8n can't go through proxy without webhook tweaks).

## 3.5 Common errors + fixes

### "Failed to fetch" in admin/client dashboard
- **What it means:** the page can't reach `automation.crystallux.org`.
- **Check:** is the VPS up? `docker ps` from SSH. Is n8n running?
- **Fix:** restart n8n (see 3.4). If still down, check Cloudflare proxy status on `automation.crystallux.org` DNS record.

### Workflow returning 500 error
- **Check in n8n UI:** click the workflow → Executions → click the failed run → see which node failed.
- **Most common cause:** missing env var. Confirm `/root/crystallux/n8n/.env` has the expected variable.
- **Second most common:** Supabase row doesn't exist (e.g. missing `agent_calendar_prefs` table per audit). Check `SELECT to_regclass('public.<table>');`.

### Database connection failures
- **Check Supabase status:** `status.supabase.com`.
- **Check credential validity:** Supabase → Settings → API → confirm anon + service-role keys.
- **Rotated credential?** Update n8n credential vault entry.

### Email not being delivered
- **Postmark dashboard** → Servers → message log → search by recipient.
- Bounces / spam complaints surface here.
- **DKIM / SPF / DMARC** check: Postmark → Sender Signatures → verify status.

### Stripe webhook failures
- Stripe dashboard → Developers → Webhooks → click endpoint → see failed deliveries with response codes.
- Most common cause: signing secret mismatch. Re-copy `STRIPE_WEBHOOK_SECRET` from Stripe → update n8n env → restart n8n.

### Cloudflare cache issues
- Page showing old version after deploy → Cloudflare → Pages project → Caching → Purge Cache.
- For specific URL: Purge Cache → Custom Purge → paste URL.

### Docker container not starting
SSH to VPS:
```bash
cd /root/crystallux/n8n
docker compose -f docker-compose.prod.yml logs --tail=200 n8n
```
Look for "error" / "panic" / "permission denied" lines. Common causes:
- Disk full: `df -h` → if `/` > 90%, clean Docker: `docker system prune -af`.
- Memory exhausted: `free -h` → restart container.
- Corrupted volume: contact Supabase / Docker expert via Upwork emergency.

---

# SECTION 4 — Emergency Procedures

**Universal first rule: don't panic. Most things resolve in <30 min once the right URL is checked.**

## 4.1 "Everything is down" playbook

1. **Open a piece of paper** and note the time you noticed.
2. **Status pages in this order** (each takes 10 seconds):
   - `status.cloudflare.com` — if red, your sites are down because Cloudflare is. Wait.
   - `status.supabase.com` — if red, database is unavailable. Wait.
   - `status.anthropic.com` — if red, all AI workflows fail. Other features OK.
   - `status.stripe.com` — if red, billing/KYC affected.
3. **SSH to VPS:** `ssh root@<vps-ip>`. If you can't connect, the VPS itself is down → check your VPS provider's status page (Linode/DigitalOcean/Hetzner — depends on what Mary picked).
4. **`docker ps`** — confirm n8n container is running. If not: `cd /root/crystallux/n8n && docker compose -f docker-compose.prod.yml up -d`.
5. **Disk + memory:** `df -h` (look for >90% usage), `free -h` (look for swap usage). Free space if needed: `docker system prune -af`.
6. **n8n logs:** `docker compose -f docker-compose.prod.yml logs --tail=200 n8n` — scan for repeated errors.
7. **If unclear after 30 min:** hire an emergency DevOps person via Upwork (see Section 4.7).

## 4.2 "Lead generation stopped" playbook

1. **Check the 7 protected v2/v3 workflows are active in n8n** — they run the production lead engine.
2. **Apollo.io** — `app.apollo.io` → check account status (suspended? out of credits? billing failed?).
3. **Hunter.io** — same check.
4. **Anthropic credit balance** — `console.anthropic.com` → Billing → top-up if needed.
5. **n8n execution log** — filter to last 24h, status=Error, scope=production workflows. Read the actual error.
6. **Cloudflare R2 + Supabase** still healthy? (Section 4.1 steps 2-3).
7. **Manual workaround if you need leads NOW:** pause new acquisition, work existing pipeline manually, file a 1-day fix-task in `docs/audit/blockers.md`.

## 4.3 "I lost my keys" playbook

1. **Password manager recovery first** — 1Password / Bitwarden / whatever Mary uses → master password recovery if forgotten.
2. **Per-vendor recovery:**
   - **Stripe** → support.stripe.com → account recovery (proof of identity + business docs).
   - **Anthropic** → support.anthropic.com → API key recovery (issue a new key, deactivate the old).
   - **Supabase** → email login → if email lost, contact support.
   - **Cloudflare** → 2FA backup codes (stored in password manager).
3. **Last resort: rotate everything.** New Anthropic key, new Stripe key, new Supabase service-role key, new VPS SSH key. Painful but recoverable.
4. **Lesson:** every quarter, do a 15-minute "credential drill" — confirm you can log into every vendor.

## 4.4 "Customer says something is broken" playbook

1. **Get specifics:**
   - What were they doing?
   - What did they expect?
   - What actually happened?
   - Screenshot or screencast.
   - Browser + device.
   - When did it start?
2. **Try to reproduce** — log in as them (admin Copilot can impersonate via the admin Q&A surface, or as a last resort `UPDATE auth_users SET impersonating_user_id=...` with audit log entry).
3. **Check n8n execution log** for that customer's `client_id` in the last hour → see if any workflow failed.
4. **Check Supabase** for any row anomalies (e.g. `clients.status='active'` correct? `agent_channels_enabled` rows present?).
5. **Fix or escalate.** If hard fix needed:
   - Quick fix: update DB row, communicate to customer.
   - Code fix: branch from `scale-sprint-v1`, make change, push, deploy.
   - Open Claude Code for any non-trivial diagnosis.
6. **Always:** reply to the customer within 2 hours during business hours, even if just "investigating — I'll have an answer by end of day."

## 4.5 "I need to roll back" playbook

1. **`git log --oneline -20`** in the repo → identify the last commit you know was good.
2. **`git revert <commit-hash>`** for the offending commit(s) — creates a NEW commit that undoes the change.
3. **`git push origin scale-sprint-v1`** → Cloudflare Pages auto-deploys the reverted frontend.
4. **SSH to VPS:** `cd /root/crystallux/n8n && git pull` → re-import affected workflows.
5. **Note:** never use `git reset --hard` on `scale-sprint-v1` — you'll lose work. Always `revert`, never `reset`.
6. **Smoke test** the affected flows after rollback.

## 4.6 "Database is broken" playbook

1. **Supabase status:** `status.supabase.com`.
2. **Supabase project dashboard** → Database → check connection status + active queries.
3. **Backups exist:** Supabase has automatic point-in-time recovery on Pro tier; daily backups on free. Confirm in Settings → Database → Backups.
4. **Restore from backup if needed** — Supabase support helps (contact via dashboard chat). **Always communicate to affected customers** if data restored to an earlier point.
5. **Worst case:** Supabase contact `support.supabase.com` — they have engineers on call.

## 4.7 Emergency contacts

- **Upwork** (https://upwork.com) — search "n8n expert", "Supabase expert", "Docker engineer". Top-rated freelancers can pair on emergencies same-day. Budget $50-150/hour. Recommend pre-vetting one or two as "on-call advisors" in normal times.
- **Toptal** (https://toptal.com) — premium freelancers; longer hire process but higher quality.
- **Gun.io** — alternative to Toptal.
- **Insurance technology advisor:** _to be added — Mary's network_.
- **Anthropic support:** `support.anthropic.com`
- **Supabase support:** dashboard chat at `app.supabase.com`
- **Stripe support:** `support.stripe.com`
- **Cloudflare support:** `dash.cloudflare.com` → Support tab
- **Twilio support:** console live chat

**Pre-emptive advice:** when calm, write down the names + URLs + cost-per-hour of 2-3 on-call DevOps freelancers from Upwork/Toptal that Mary trusts. **Cost: zero until needed.** Saves 2 hours of "who do I call?!" panic in the actual emergency.

---

# SECTION 5 — Roadmap & Recent Decisions

## 5.1 Phase completion status

| Phase | Name | Status | Commit | Notes |
|---|---|---|---|---|
| 1 | Foundation activation | ✅ Code complete · ⏳ external integrations pending | `6bd51c7` | Stripe billing / Postmark / auth-flow rewire — verify external |
| 2-3 | Universal Core Engine | ✅ Code complete · ⏳ external integrations pending | `25c0886` | 25 workflows; gated on NewsAPI/HeyGen/Vapi/R2/Cal.com signups |
| Layer 2A | AI Compliance Engine | ✅ Complete | `b4f5ec0` | Stripe Identity + Zoho Sign external setup pending |
| Layer 2B | MGA Operations + Reviews + Video | ✅ Code complete · ⏳ 5 Mary activation tasks remaining | `f5a73cf` | All 7 migrations applied; 41 workflows imported (dormant); LICENSE_ENCRYPTION_KEY set |
| Layer 2C | Insurer-Facing Mode + reports + demo | 🟡 Next session | TBD | 4-6h scope; expansion-to-14h scope recommended per audits |
| Phase 4 | Content Marketing workflows | 🔴 Future (2-3 weeks) | — | Schema ready in `25c0886`; gated on social-platform API approvals |
| Phase 5b | Polish (Certn, partition, dispute table, etc.) | 🔴 Future (1 week) | — | List in `docs/audit/2026-05-11-comprehensive-audit.md` |
| Phase 6 | Carrier API integrations | 🔴 Future (12-18 mo) | — | Business-development driven |
| Phase 10 | Advanced compliance automation | 🔴 Future | — | When > $5M production |

## 5.2 Recent strategic decisions

### Multi-vertical architecture (commit `b4f5ec0` → `f5a73cf`)
- Every Layer 2 table has `vertical_id text NOT NULL DEFAULT 'insurance'` + `idx_*_vertical` index.
- Every Layer 2 webhook URL includes `/insurance/` in path.
- Every Layer 2 SQL query filters or sets `vertical_id='insurance'`.
- Future verticals (mortgage / real estate / group benefits / commercial insurance) plug into the SAME Layer 2 tables with their own `vertical_id` value. **No schema migration required.**
- Detail: `docs/architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`.

### Three-layer business architecture
- **Layer 1** Crystallux SaaS — universal sales engine, sold to anyone.
- **Layer 2** Crystallux Insurance Network MGA — regulated business Mary operates herself; first proof of Layer 2 module. Future Layer 2: mortgage MGA, real estate brokerage, etc.
- **Layer 3** Marketplace (Year 2-3) — other MGAs/agencies license the platform.

### Behavioral signal → review → video pipeline (Layer 2 Part B)
- Behavioral Intelligence detects life events (birthday, marriage, baby, new job, home purchase, business expansion, job loss, etc.).
- `clx-mga-insurance-review-triggered-event-v1` maps signals to 7 review types.
- `clx-mga-insurance-review-video-generator-v1` personalizes one of 12 seeded video templates via Claude.
- Chains existing video pipeline (commit 25c0886): HeyGen render → R2 store → landing page → multi-channel delivery.
- Engagement-status ratchet (`not_sent → sent → viewed → replied → meeting_booked`) drives daily AI follow-ups.
- **This is the moat.** No traditional MGA has this. Detail: `docs/insurance-mga/VIDEO_ENGAGEMENT_STRATEGY.md`.

### MGA principal user separation
- `info@crystallux.org` is the Crystallux Inc. admin (SaaS product) — `user_role='admin'`.
- Crystallux Insurance Network is a separate `clients` row (the MGA eats its own dog food).
- Mary as `mga_principal` is a different user (or same email with different role context depending on session).
- This separation is **architectural discipline** — it keeps regulatory accountability clean and enables the Year-2-3 marketplace play where other MGAs run on the platform.

### Migration playbook (when to leave the current stack)
- **Don't migrate to Node.js services until > $300K MRR.** n8n is fine until then.
- **Don't migrate Supabase until > $500K MRR.** Pro tier covers us comfortably.
- **Use Strangler Fig pattern** for any migration (parallel run, gradual cutover).
- **Plan migrations 6+ months in advance.** Always have a rollback path.
- Detail: `docs/architecture/scaling-strategy.md`.

### Scaling thresholds
- **0-100 clients:** current stack sufficient. No changes needed.
- **100-500 clients:** optimize n8n (more workers, more indexes, partition `regulatory_audit_log`).
- **500-2,000 clients:** add Supabase read replicas, n8n cluster, selective Node.js services for high-throughput paths.
- **2,000-10,000 clients:** microservices, multi-region, dedicated engineering team.
- **10,000+ clients:** enterprise architecture (Kafka, ClickHouse for analytics, etc.).

### Valuation framework (don't sell early)
- At 10 clients (where Mary is heading): $500K-$3M acquisition value.
- At 50-100 clients on the same platform: $5M-$15M.
- At 200-500 clients: $30M-$100M.
- **18-24 months patience = 5-10× more value at exit.**
- Don't entertain any acquisition conversation until at least 100 paying customers.

## 5.3 Next 30 days priority

1. **Complete Mary's 5 Layer 2 Part B activation tasks** (per night notes `2026-05-10-night-wrapup.md`):
   - Promote `info@crystallux.org` → `mga_principal`
   - Seed 12 video review templates via webhook
   - Deploy `insurance-mga-dashboard/` to Cloudflare Pages (`mga.crystallux.org`)
   - Confirm Phase 1/2/3 external integration status (Stripe / Postmark / NewsAPI / HeyGen / Vapi / R2 / Twilio WA approval / Cal.com)
   - Smoke test end-to-end
2. **Layer 2 Part C build** (Claude Code, 4-6 hours minimum — see audit recommendation to expand scope).
3. **Verify three flagged tables exist** (5 minutes in Supabase):
   ```sql
   SELECT to_regclass('public.closing_scripts');       -- F6 depends
   SELECT to_regclass('public.agent_calendar_prefs');  -- F1 + F4 depend
   SELECT to_regclass('public.agent_daily_plans');     -- F5 Upsert Plan depends
   ```
4. **Onboard first paying customer.**
5. **First insurer pitch meeting.**

## 5.4 Next 90 days priority

1. 5-10 paying customers (across at least 2 verticals).
2. 1-2 carrier appointment conversations active.
3. Validate product-market fit (key metric: < 5% monthly churn).
4. Plan Phase 4 (Content Marketing) build.

## 5.5 Next 12 months priority

1. 50+ paying customers.
2. 3+ active carrier appointments.
3. First non-Crystallux-Insurance-Network MGA principal customer (start of Layer 3 / marketplace).
4. Hire first employee (likely customer success or compliance officer).
5. Decision on seed funding (raise vs bootstrap further).

---

# SECTION 6 — Vendor Relationships

For each vendor: what they do, why we chose them, what to do if their service is interrupted, backup plan.

### Anthropic (Claude API)
- **What:** Powers every AI call in the platform. Sonnet 4.5 model.
- **Why:** Best-in-class reasoning + lowest hallucination rate + extended context.
- **Account contact:** Mary's email; web console at `console.anthropic.com`.
- **Pricing:** Pay-as-you-go. Estimated ~$30-100/mo at current scale.
- **If interrupted:** All AI features down. Voice agent + Behavioral Intelligence + Compliance Agent all fail. Use only one provider — **this is a single point of failure.** Mitigate by keeping a second key in a different Anthropic account as cold standby.
- **Backup option:** Could swap to OpenAI GPT-4o for text-only calls in 2-3 hours of Claude Code work (prompts would need light reformatting). Not feasible for the Anthropic-specific tool-use patterns.

### Supabase (database + auth + storage)
- **What:** Postgres database hosting all 30+ tables. Also handles auth.
- **Why:** Best DX for Postgres + integrated auth + generous free tier.
- **Account contact:** Mary's email; `app.supabase.com`.
- **Pricing:** Free tier covers us until ~100 paying clients; then Pro ($25/mo).
- **If interrupted:** Everything stops. Critical. Daily automatic backups on Pro tier.
- **Backup option:** Could migrate to AWS RDS or Render Postgres in ~1 week (dump + restore + reconfigure n8n credentials). Not feasible during an outage.

### Cloudflare (DNS + Pages + R2 + WAF)
- **What:** DNS, frontend hosting (4 dashboards = 4 Pages projects), R2 object storage for videos + disclosures.
- **Why:** Free at our scale, R2 has no egress fees, global CDN.
- **Account contact:** Mary's login.
- **Pricing:** $0-20/mo (small charge for R2 storage above 10 GB).
- **If interrupted:** All sites unreachable. Status: `status.cloudflare.com`.
- **Backup option:** DNS can move to Route 53 / Namecheap in hours. Pages can move to Vercel/Netlify in days. R2 can mirror to S3.

### n8n (workflow engine, self-hosted)
- **What:** Visual workflow engine running 145 workflows.
- **Why:** Open-source self-hostable; no per-execution fees at our volume; visual editing means Mary can read workflows.
- **Account contact:** Self-hosted in Docker on Mary's VPS. No external account.
- **Pricing:** $0 software + ~$20-40/mo VPS.
- **If interrupted:** All automation stops. SSH playbook in Section 4.
- **Backup option:** Same n8n image on a second VPS as cold standby (Phase 5b).

### Stripe (billing + Identity)
- **What:** Subscriptions + invoicing + KYC verification.
- **Why:** The standard; Identity bundles into the same account.
- **Account contact:** Mary's email.
- **Pricing:** Pass-through (we charge customers) + $1.50/KYC verification.
- **If interrupted:** New signups fail; existing subscriptions continue billing.
- **Backup option:** Paddle / Lemon Squeezy as alternative billing platforms (week-long migration if needed).

### Postmark (email)
- **What:** All transactional email (auth, billing, MGA notifications, daily summaries).
- **Why:** Best inbox placement + simple API.
- **Account contact:** `account.postmarkapp.com`.
- **Pricing:** ~$0-15/mo at our scale.
- **If interrupted:** Auth emails fail; customer notifications fail. **Important:** keep DKIM/SPF/DMARC verified.
- **Backup option:** SendGrid / Resend in ~1 day of swap work.

### Twilio (SMS + WhatsApp + Voice)
- **What:** SMS sends, WhatsApp sends (gated on Meta Business approval), voice agent SIP via Vapi.
- **Why:** Industry standard; ecosystem support.
- **Account contact:** `console.twilio.com`.
- **Pricing:** ~$10-50/mo at our scale.
- **If interrupted:** SMS + WA + voice fail.
- **Backup option:** MessageBird / Plivo for SMS; no easy WA alternative.

### HeyGen (avatar video)
- **What:** Generates 4-persona AI avatar videos for outreach + reviews + content.
- **Why:** Best lip-sync + custom-avatar capability.
- **Account contact:** `app.heygen.com`.
- **Pricing:** $29/mo Creator + ~$0.30/video pay-as-you-go.
- **If interrupted:** Video pipeline stops; messages without video still send.
- **Backup option:** Synthesia or Tavus as alternative providers (Phase 5b — recommend warming up a Synthesia account as failover).

### ElevenLabs (voice cloning)
- **What:** Voice cloning for 4 persona voices.
- **Why:** Highest voice quality + Vapi-compatible.
- **Account contact:** `elevenlabs.io`.
- **Pricing:** $5/mo.
- **If interrupted:** Voice agent + HeyGen videos use default voice instead.
- **Backup option:** PlayHT.

### Vapi (voice agent)
- **What:** AI voice agent for inbound + outbound calls.
- **Why:** Lower per-minute cost than Retell; existing Crystallux integration patterns.
- **Account contact:** `dashboard.vapi.ai`.
- **Pricing:** Pay-as-you-go.
- **If interrupted:** Voice agent stops; SMS + WA + email continue.
- **Backup option:** Retell (per `docs/agent/build-phases.md`).

### Cal.com / Calendly (booking)
- **What:** Booking management + calendar integration.
- **Why:** Cal.com is open-source; Calendly is incumbent — currently Calendly path is wired via `clx-booking-v2` (production-active).
- **Account contact:** `cal.com` or `calendly.com`.
- **Pricing:** $0-12/mo.
- **If interrupted:** New bookings fail; existing bookings unaffected.
- **Backup option:** the other one. Migration is hours, not days.

### Zoho Sign (e-signature)
- **What:** Disclosure document signing for insurance MGA workflows.
- **Why:** Flat $8/mo, OAuth-based, doesn't require per-document pricing.
- **Account contact:** `sign.zoho.com`.
- **Pricing:** $8/mo.
- **If interrupted:** Disclosure signing fails; workaround = email PDF + verbal acknowledgment.
- **Backup option:** DocuSign / HelloSign.

### Apollo.io (lead generation)
- **What:** B2B lead sourcing.
- **Why:** Best price-to-quality ratio at our scale.
- **Account contact:** `app.apollo.io`.
- **Pricing:** ~$50-100/mo.
- **If interrupted:** New B2B leads stop sourcing; existing pipeline continues.
- **Backup option:** ZoomInfo (expensive), Lusha, Sales Navigator.

### Hunter.io (email finding)
- **What:** Email verification + finding.
- **Why:** Cheap and reliable.
- **Account contact:** `hunter.io`.
- **Pricing:** $0-50/mo.
- **If interrupted:** Lead-enrichment hit rate drops; non-blocking.
- **Backup option:** Apollo's built-in email finder; Findymail.

### Unipile (LinkedIn DM)
- **What:** LinkedIn outreach + multi-platform social (also relevant for Phase 4 content marketing).
- **Why:** Best multi-platform coverage.
- **Account contact:** `unipile.com`.
- **Pricing:** Per-account.
- **If interrupted:** LinkedIn channel down; other channels continue.

### NewsAPI / OpenWeather (market intelligence)
- **What:** News and weather signals for Market Intelligence pipeline.
- **Why:** Free tiers cover our scale.
- **Account contact:** `newsapi.org` / `openweathermap.org`.
- **Pricing:** $0.
- **If interrupted:** Some Market Intelligence signal sources lost; pipeline continues with reduced coverage.

### Certn (background checks — Phase 5b)
- **What:** Background checks for advisor onboarding.
- **Why:** Canadian-focused, FSRA-aligned.
- **Account contact:** `certn.co`.
- **Pricing:** $30/check.
- **If interrupted:** Manual background checks (slower); not blocking.

---

# SECTION 7 — Decision Frameworks

## 7.1 Build vs buy

For any new capability, ask in this order:

1. **Is there a vendor that does this for < $200/mo per relevant unit?** If yes and the API is decent, BUY it. Time saved >> cost.
2. **Does building it create a moat?** If the capability is *only* valuable when integrated with everything else (like behavioral signals → reviews → video), BUILD it. Otherwise BUY.
3. **What's the maintenance cost of building?** Estimate 1.5× the build cost over 24 months. If that exceeds 24× the buy price, BUY.
4. **Is the vendor likely to survive 3+ years?** If they're VC-funded with no profitability, treat as risky.

**Defaults at our stage:**
- Build: anything that's core to the differentiation (BI engine, video pipeline, AI agent, vertical modules).
- Buy: anything else (auth, billing, KYC, email, SMS, voice, video rendering, social media APIs).

## 7.2 Feature requests (from customers)

When a customer asks for a feature:

1. **Is it core to the value proposition?** "Better AI calls" — yes. "Custom Excel export" — probably no.
2. **Will at least 3 other customers want it?** If only one customer cares, defer or charge separately.
3. **What's the cost to build?** < 4 hours Claude Code: usually yes. > 1 week: needs strong justification.
4. **What's the strategic fit?** Does it move us toward multi-vertical, AI-native, or compliance-mature? Or does it pull us toward generic CRM?

**Defaults:**
- Ship: small features that match the engine's existing patterns.
- Defer: big features that introduce new external dependencies.
- Decline politely: features that pull us off-strategy.

**Say no in writing** when you do, with a one-line reason. Customers respect clear "no" more than vague "we'll see."

## 7.3 Pricing decisions

**Raise prices when:** 30%+ of new customers don't blink at current price (they're getting too much value for too little). Raise the top tier first; never the bottom.

**Lower prices:** rarely. The cost of acquiring a customer doesn't drop with price — keep the floor.

**Add new tiers:** when an existing customer says "I'd pay $X if you'd just X" and the X serves a clearly distinct segment. **The current 3-tier ladder ($1,497 / $2,997 / $5,997) is the right shape for SaaS in this category — defend it.**

**Custom enterprise pricing:** only above $10,000/mo. Below that, just sell Scale.

**Negotiate enterprise deals:** discount in 12-month commitments, not in price-per-month. Cash-in-advance discount = OK; ongoing rate discount = avoid.

## 7.4 Hire vs outsource

**The first 3 hires:**
1. **Customer Success Manager** — first hire when > 10 paying customers AND > 20 hours/week of customer interaction. Full-time or part-time contract.
2. **Compliance Officer** — first hire when > 3 active carrier appointments. Must be FSRA-licensed. Can start fractional.
3. **Engineering hire (DevOps/fullstack)** — first hire when Claude Code is no longer sufficient OR when there's a 24/7 on-call need. Usually > $300K MRR.

**Outsource for:**
- Specific technical projects with clear scope (e.g. "set up cold-standby VPS")
- Crisis DevOps (Upwork / Toptal)
- Marketing creative (content, copy, design)
- Bookkeeping + accounting (already)

**Don't outsource:**
- Anything customer-facing in the early days (you, founder, must hear every conversation)
- Anything that requires deep product context (decisions about Phase 4 scope, vertical priority)
- Sales (until > $50K MRR)

## 7.5 Migration decisions

See Section 5.2 "Migration playbook" — thresholds + Strangler Fig pattern + 6-month planning rule.

## 7.6 Customer decisions

**Red flags at onboarding (consider declining):**
- Refuses to use the AI features (wants Crystallux as a fancy CRM only) — wrong fit
- Demands extensive customization out of the gate — wrong fit
- Pays from a personal credit card with no business address — fraud risk
- Asks for monthly contracts with month-to-month flexibility AND custom features — too high-touch for too little price

**When to fire a customer:**
- Their support cost exceeds 3× their MRR for 3+ consecutive months
- They abuse staff (rude, threatening)
- They violate ToS (spam complaints, regulator referrals)
- **How:** 30-day notice, refund unused portion of pre-pay, no drama.

**When to upgrade a customer:**
- They're consistently using > 80% of their tier's promise (e.g. Growth customer booking 28+ meetings/mo)
- They have a team growing past their current tier's user count
- They ask for a feature that's already in a higher tier — don't custom-build, sell the upgrade.

**Refund vs negotiate:**
- < 30 days in: full refund, no questions.
- 30-90 days in: pro-rated refund for unused months IF they're being reasonable.
- > 90 days in: credit toward future months only.

## 7.7 Investor decisions

**When to raise:**
- You have product-market fit signal (< 5% monthly churn at > 20 paying customers).
- You can articulate exactly how the capital accelerates growth (not "we need it to survive").
- You're not personally desperate (desperation = bad terms).

**When to reject capital:**
- Term sheet wants > 25% in seed round.
- Investor doesn't understand the multi-vertical thesis.
- Investor wants board control out of the gate.
- The total raise crowds out the next round's milestones.

**Choosing investors:**
- Operator background > pure financial background.
- Insurance + vertical SaaS portfolio companies > generalist SaaS.
- Reference-check their other founders aggressively. Ask "are they easy to work with when things go wrong?"

**Valuation:**
- Seed: $5-15M post-money is reasonable at 10-30 paying customers + clear traction.
- Don't fight for $30M post on $200K ARR — investors won't pay it and you'll waste 3 months.
- A "reasonable" valuation + good investor > "best" valuation + bad investor. **Every time.**

---

# SECTION 8 — Glossary

## 8.1 Insurance terms

- **MGA (Managing General Agent)** — A licensed entity that has carrier appointments and can manage advisors/sub-agents who sell on behalf of the carrier. Crystallux Insurance Network is an MGA.
- **LLQP (Life License Qualification Program)** — Canadian license to sell life insurance.
- **FSRA (Financial Services Regulatory Authority)** — Ontario's insurance + mortgage + credit-union regulator.
- **RIBO (Registered Insurance Brokers of Ontario)** — Ontario property + casualty insurance regulator.
- **AMF (Autorité des marchés financiers)** — Quebec's financial regulator.
- **E&O (Errors and Omissions Insurance)** — Professional liability insurance every advisor must carry. Crystallux requires ≥ $2M.
- **CE (Continuing Education)** — Annual education hours licensed advisors must complete.
- **AML (Anti-Money Laundering)** — Compliance regime under FINTRAC.
- **PEP (Politically Exposed Persons)** — High-AML-risk individuals requiring extra due diligence.
- **KYC (Know Your Customer)** — Identity verification required before binding insurance.
- **CASL (Canadian Anti-Spam Legislation)** — Federal commercial-electronic-message regime.
- **PIPEDA (Personal Information Protection and Electronic Documents Act)** — Federal privacy law.
- **FINTRAC** — Financial Transactions and Reports Analysis Centre. Receives AML reports.
- **OSFI** — Office of the Superintendent of Financial Institutions. Federal prudential supervisor (mostly relevant to carriers, not us).
- **Suitability Assessment** — Documented analysis of whether a product fits a client's needs. Required by FSRA.
- **Replacement Disclosure** — Mandatory disclosure when replacing existing life insurance. FSRA requires.
- **Carrier Appointment** — Authorization from an insurance carrier (Manulife, Sun Life, etc.) for an MGA + advisor to sell their products.

## 8.2 Technical terms (plain English)

- **API (Application Programming Interface)** — A way for one program to ask another program to do something.
- **Webhook** — A URL that, when called, triggers a workflow. Our webhooks live at `automation.crystallux.org/webhook/...`.
- **Workflow** — In n8n, a connected set of steps (nodes) that runs in sequence. Our workflows are JSON files in `workflows/`.
- **Database** — Organized data storage. Ours is Postgres, hosted by Supabase.
- **Migration** — A change to the database structure (adding a table, adding a column). Stored as a `.sql` file in `db/migrations/`. **Always additive** — we never delete columns.
- **Encryption** — Scrambling sensitive data so it's unreadable without the key. We use AES-256-GCM for license numbers + E&O policy numbers.
- **Authentication** — Confirming WHO you are (login).
- **Authorization** — Confirming WHAT you can do (role check after login).
- **Vertical** — An industry or sector (insurance, mortgage, real estate, dental).
- **Schema** — The definition of a database table — its columns + constraints.
- **Dormant** — A workflow that exists in code but is not currently running. `active: false` in n8n.
- **Production** — The live, customer-facing version. Don't break it.
- **Staging** — A safe environment to test changes before they hit production. We don't have a formal staging env yet; small changes go straight to production via Cloudflare Pages preview branches.
- **Rollback** — Reverting to a previous version. See Section 4.5.
- **RLS (Row Level Security)** — Postgres feature that restricts which rows a connection can see. We use service-role-only RLS — workflows have full access; direct customer access is blocked.
- **CSP (Content Security Policy)** — A web security header that limits which external resources a page can load. We lock CSP tightly to prevent injection.
- **CDN (Content Delivery Network)** — Globally distributed cache for static files. Cloudflare provides ours.

## 8.3 Crystallux-specific terms

- **Layer 1** — Universal core engine (AI agent, BI, video pipeline, multi-channel delivery). Vertical-agnostic.
- **Layer 2** — Vertical-specific modules (Insurance MGA is the first). Tagged by `vertical_id`.
- **Layer 3** — Future marketplace where other MGAs/agencies run on the platform.
- **Vertical tagging** — Architectural rule: every Layer 2 table has `vertical_id`; every Layer 2 webhook URL has `/insurance/` in the path; every Layer 2 query filters/sets `vertical_id`.
- **Behavioral signal** — A detected life event for a lead (birthday, marriage, baby, etc.) — see `behavioral_signals` table.
- **Triggered review** — A policy review created by a behavioral signal landing on a lead with an in-force policy. See `policy_reviews.review_type='triggered_event'`.
- **Compliance officer override** — Layer 2 design rule: any AI compliance decision can be overridden by a user with role `compliance_officer`. Regulator floor, not optional.
- **Production reports** — Layer 2 Part C feature (next session) — insurer-facing aggregated reports.
- **Pitch mode** — Layer 2 Part C feature — demo-friendly view of the audit trail + KPI rollups for showing carrier prospects.
- **Niche** — A specific vertical (e.g. `insurance`, `mortgage_broker`, `dental`). Stored as `niche_name` on `clients`, `leads`, `behavioral_signals`, `signal_archetypes`.

---

# SECTION 9 — Maintenance

## 9.1 How to keep this handbook updated

- **After every major release:** add the new commit hash + brief description to Section 5.1.
- **After every new vendor signup:** add row to Section 6 + add credential location to Section 2.3.
- **Quarterly:** review Section 4.7 emergency contacts — are they still active? are rates still right?
- **Quarterly:** revisit Section 7 decision frameworks. Has Mary changed her thinking?
- **As discovered:** add new common errors to Section 3.5. **Every error solved once = an entry that saves 2 hours next time.**

## 9.2 Versioning

- This file lives in git like any other doc — track changes via commit history.
- Material updates merit a SESSION_LOG.md entry (`docs/journal/SESSION_LOG.md`).
- Don't fork or copy this file. Single source of truth principle.

## 9.3 Onboarding a new person to use this handbook

**For a non-technical hire (e.g. customer success):**
- Day 1 morning: read Section 1 (Strategic Context) + Section 8 (Glossary).
- Day 1 afternoon: read Section 2 (System Inventory).
- Day 2: shadow Mary running Section 3 daily routine.
- Day 3: read Section 4 (Emergency Procedures) — they need to know what to do when Mary's not available.
- Day 4-5: read Section 5 + 7 (Roadmap + Decisions) for context.

**For a technical hire (e.g. DevOps):**
- Morning 1: Section 1 + Section 2.
- Afternoon 1: walk the codebase (`db/migrations/`, `workflows/api/`, `insurance-mga-dashboard/`).
- Day 2: read Section 4 + Section 6 + run Section 3.4 ops.
- They should be operational in 4-6 hours.

**For an investor:**
- Section 1 (10 min).
- Section 5 (15 min).
- Section 7 (10 min).
- Glossary as needed.

---

# SECTION 10 — Appendices

## 10.1 Common commands quick reference

**Git basics:**
```bash
git status                                # what changed
git log --oneline -10                     # last 10 commits
git pull origin scale-sprint-v1           # pull latest
git add docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md
git commit -m "what changed and why"      # commit
git push origin scale-sprint-v1           # push
git revert <commit-hash>                  # undo a commit safely
```

**Docker (on VPS):**
```bash
docker ps                                                  # what's running
docker exec n8n n8n list:workflow                          # list all workflows
docker exec n8n n8n list:workflow | grep '<name>'          # find one
docker compose -f docker-compose.prod.yml logs --tail=200 n8n   # last 200 log lines
docker compose -f docker-compose.prod.yml restart n8n      # restart n8n
docker system prune -af                                    # free disk space
df -h                                                      # disk usage
free -h                                                    # memory usage
```

**Supabase SQL (run in SQL Editor):**
```sql
SELECT count(*) FROM leads;                                -- total leads
SELECT count(*) FROM clients WHERE status='active';        -- active customers
SELECT count(*) FROM scan_errors WHERE created_at > now() - interval '24 hours';
SELECT to_regclass('public.<table>');                      -- check table exists (returns NULL if not)
BEGIN; UPDATE x SET y=z WHERE id='...'; ROLLBACK;          -- preview destructive query
```

**Cloudflare cache purge:** `dash.cloudflare.com` → Pages project → Caching → Purge Cache.

**Anthropic API key check:** `console.anthropic.com` → API Keys → status.

## 10.2 Useful resources

**Anthropic / Claude:**
- Docs: `docs.anthropic.com`
- Cookbook: `github.com/anthropics/anthropic-cookbook`
- Discord: `discord.gg/anthropic`

**n8n:**
- Docs: `docs.n8n.io`
- Community forum: `community.n8n.io`

**Supabase:**
- Docs: `supabase.com/docs`
- Discord: `discord.supabase.com`

**Insurance regulators (Canada):**
- FSRA: `fsrao.ca`
- RIBO: `ribo.com`
- AMF: `lautorite.qc.ca`
- FINTRAC: `fintrac-canafe.gc.ca`
- OSFI: `osfi-bsif.gc.ca`

**Industry publications:**
- Canadian Underwriter (CU): `canadianunderwriter.ca`
- InsuranceBusiness Canada: `insurancebusinessmag.com/ca`
- Insurance Innovation Reporter: `insuranceinnovationreporter.com`

## 10.3 Founder's recommended reading

**Business strategy:**
- *Crossing the Chasm* — Geoffrey Moore. How to move from early adopters to mainstream.
- *The Hard Thing About Hard Things* — Ben Horowitz. The unglamorous truth of running a startup.
- *The Mom Test* — Rob Fitzpatrick. How to actually validate customer interest (not what they say — what they do).

**Sales & growth:**
- *Predictable Revenue* — Aaron Ross. How outbound sales actually works at scale.
- *From Impossible to Inevitable* — Aaron Ross & Jason Lemkin. The next stage.

**Insurance industry:**
- *The Future of Insurance* (3-volume series) — Bryan Falchuk. State of insurance innovation.
- *Distribution: The Last Mile of Insurance* — multiple authors.

**Mental models:**
- *Thinking, Fast and Slow* — Daniel Kahneman.
- *Algorithms to Live By* — Brian Christian + Tom Griffiths. Computational thinking applied to life.

---

## Index of cross-referenced documents

- Strategic context: `docs/architecture/PRODUCT_VISION.md`
- Business model: `docs/architecture/BUSINESS_PLAN.md`
- Architecture doctrine: `docs/architecture/ARCHITECTURE_DOCTRINE.md`
- Operations handbook (technical): `docs/architecture/OPERATIONS_HANDBOOK.md`
- Multi-vertical pattern: `docs/architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`
- Scaling strategy: `docs/architecture/scaling-strategy.md`
- Cost model: `docs/architecture/COST_ANALYSIS.md`
- Roles + access: `docs/architecture/ROLES.md`
- Auth architecture: `docs/architecture/AUTH_ARCHITECTURE.md`
- AI Agent vision: `docs/agent/AGENT_VISION.md`
- Agent build phases: `docs/agent/build-phases.md`
- Content marketing (Phase 4): `docs/agent/content-marketing-vision.md`
- Insurance Layer 2 vision: `docs/insurance-mga/AI_COMPLIANCE_VISION.md`
- Insurance regulatory framework: `docs/insurance-mga/REGULATORY_FRAMEWORK.md`
- MGA operations: `docs/insurance-mga/MGA_OPERATIONS_VISION.md`
- Review management: `docs/insurance-mga/REVIEW_MANAGEMENT_VISION.md`
- Video engagement strategy: `docs/insurance-mga/VIDEO_ENGAGEMENT_STRATEGY.md`
- Security framework: `docs/insurance-mga/SECURITY_FRAMEWORK.md`
- Audits (state-of-the-platform): `docs/audit/2026-05-11-comprehensive-audit.md`
- Audits (universality): `docs/audit/2026-05-11-core-engine-universal-audit.md`
- Audits (feature completeness): `docs/audit/2026-05-11-feature-audit.md`
- Session journal: `docs/journal/SESSION_LOG.md`
- Cumulative state: `docs/journal/CRYSTALLUX_STATUS.md`
- Night notes (recent): `docs/journal/2026-05-10-night-notes.md`, `2026-05-10-night-wrapup.md`

---

*End of handbook. ~12,000 words / ~45 pages printed.*

*Maintainer: Mary Akintunde. Updated: 2026-05-11.*
