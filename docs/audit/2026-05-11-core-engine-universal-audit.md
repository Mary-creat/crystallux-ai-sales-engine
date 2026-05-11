# Core Engine Universality Audit — 2026-05-11

> **Question this audit answers:** Is the Crystallux core engine truly universal — ready to serve insurance, mortgage, real estate, logistics, beauty, dental, etc. — or are there hidden insurance-specific assumptions that would block other-vertical onboarding?
>
> **Method:** Read every workflow in `workflows/api/` + the 8 legacy §29-§34 workflows in `workflows/`. Grep for `insurance|FSRA|carrier|policy|LLQP|MGA|broker` across core surfaces. Cross-reference universal schemas with PRODUCT_VISION + MULTI_VERTICAL_LAYER2_ARCHITECTURE.
>
> **One-line answer:** Yes, the core engine is universal. Two minor leakage spots flagged. Three meaningful gaps for any vertical with sales teams (auto lead-assignment, goal-tracking schema, universal supervisor webhook).

---

## Insurance-leakage scan (entire core engine)

| Surface | Insurance string matches | Verdict |
|---|---|---|
| `workflows/api/agent/` (8 workflows) | 2 mentions, both false-positive on inspection | ✅ Clean |
| `workflows/api/booking/` (1) | 0 | ✅ Clean |
| `workflows/api/video/` (7) | 1 — explicit 16-vertical fallback table including insurance | ✅ Clean (multi-vertical by design) |
| `workflows/api/intelligence/` (5) | 3 — comments/prompts mentioning insurance as one example of many | ✅ Mostly clean; 1 minor placeholder branch |
| `workflows/api/messaging/` (3) | 0 | ✅ Clean |
| `workflows/api/mcp/` (1) | 0 | ✅ Clean |
| `workflows/clx-{daily-plan,reshuffle,no-show,post-call,activity,daily-summary,realtime-script,route}*.json` (8 legacy §29-§34) | **0 across all 8** | ✅ Truly universal |

**Two non-clean items, both minor:**

1. **`workflows/api/agent/clx-agent-conversation-handler-v1.json`** — Claude system prompt includes the line *"Never make up product details or carrier names. Never quote a price."* The word "carrier" here is insurance lingo BUT the rule is universal hedge-against-hallucination. Cleaner wording for future: `"product details or vendor names"`. **Not blocking.**

2. **`workflows/api/intelligence/clx-behavioral-signal-ingestion-v1.json`** — Has an explicitly-gated placeholder branch:
   ```js
   if (niche_name === 'insurance' || niche_name === 'insurance_broker') {
     // placeholder — requires policies table (Phase 4)
   }
   ```
   This is a no-op pending the `policies` table. **Insurance-specific code lives behind a niche_name check**, so it's correctly scoped. Other verticals will not hit it. **Not blocking.**

---

## Per-feature audit

### 1. Lead Distribution / Assignment

**Built in core?**: 🟡 Partial
**File paths:**
- `leads.assigned_advisor_id` column → `db/migrations/insurance-mga-operations-schema.sql:350` *(architectural concern: a Layer 2 migration touches the universal `leads` table; functionally correct because the column is universal, but conceptually belongs in a Layer 1 migration)*
- `clx-campaign-router-v2.json` (top-level, production-active) — routes leads into outreach campaigns, NOT into advisors
- No dedicated round-robin / geographic / specialty / capacity-aware assignment workflow exists

**Universal?**: The `assigned_advisor_id` field is vertical-agnostic. No insurance assumptions.
**Works for**: insurance ✅ (already used) | mortgage ✅ | real estate ✅ | logistics ✅ | beauty ✅ | dental ✅ — assuming Mary manually populates `assigned_advisor_id`.
**Configuration per client**: none for the column. **Auto-assignment LOGIC must be built separately.**
**Missing pieces:** **The assignment logic itself.** No workflow that watches `leads.assigned_advisor_id IS NULL` + applies round-robin/geographic/load-balance rules. Currently 100% manual.
**Strategic importance:** **Critical** for Mary's MGA (10 advisors) and any agency-shaped customer.

---

### 2. Calendar Booking

**Built in core?**: ✅ Yes
**File paths:**
- `workflows/api/booking/clx-booking-create-v1.json` (Cal.com v2 API integration, commit 25c0886)
- `workflows/clx-booking-v2.json` (legacy, Calendly webhook handler — production-active)
- `bookings` table → `db/migrations/delivery-channels-schema.sql`
- `agent_schedules` (per-client timezone + quiet hours) → `db/migrations/ai-agent-schema.sql`
- `clx-appointment-geocoder-v1.json` (Nominatim geocoding, dormant)
- `clx-route-optimizer-v1.json` (Haversine nearest-neighbour routing, dormant)
- `clx-reshuffle-suggester-v1.json` (replacement-lead suggestion when slot vacates, dormant)

**Universal?**: Yes. `bookings` table is vertical-agnostic. Cal.com handles timezone + conflict resolution natively. Route optimizer is pure geography.
**Works for**: all 6 verticals ✅
**Configuration per client**:
- `CALCOM_API_KEY` env var
- `CALCOM_DEFAULT_EVENT_TYPE_ID` env var (Phase 5b: per-client override via new `clients.calcom_event_type_id` column)
- `agent_schedules.timezone` row per client
- `clients.travel_optimization_enabled = true` to activate route optimizer (per audit)

**Missing pieces:** None for booking itself. Geographic grouping ("schedule these 6 home visits as a single Tuesday route") works via route-optimizer but it's dormant and not surfaced in any UI.
**Strategic importance:** **Critical**.

---

### 3. No-show Detection & Re-engagement

**Built in core?**: ✅ Yes
**File paths:**
- `workflows/clx-no-show-detector-v1.json` — 30-min scan for missed appointments (dormant)
- `workflows/clx-no-show-sms-recovery-v1.json` — auto-compose + send rebook SMS via Twilio (dormant)

**Universal?**: Yes. Zero insurance references in either workflow.
**Works for**: all 6 verticals ✅
**Configuration per client**:
- Twilio SMS credential bound for the tenant
- `agent_calendar_prefs.no_show_sms_enabled = true` per advisor (per CLAUDE.md / api-surface-audit references)
- Remove `TESTING_PHONE` override before going live

**Missing pieces:**
- **Multi-attempt rebook** — current pattern is single SMS; no escalation if first attempt doesn't land.
- **Eventual cold-mark logic** — if 3+ no-shows, lead status should auto-flip to `Closed Lost` or similar. Not built.
- Could be added via `behavioral_triggers` row chained to `clx-follow-up-v2`.

**Strategic importance:** **Critical** for any service business with appointments.

---

### 4. AI Conversation Handler

**Built in core?**: ✅ Yes
**File paths:**
- `workflows/api/agent/clx-agent-conversation-handler-v1.json` (commit 25c0886)
- `workflows/api/agent/clx-agent-memory-update-v1.json` (OpenAI text-embedding-3-small → pgvector)
- `agent_conversations` + `agent_memory` (1536-dim vector, ivfflat cosine index) → `db/migrations/ai-agent-schema.sql`
- `agent_personalities.vertical_context` per client (universal tuning knob)

**Universal?**: Yes. The single "carrier" mention is universal hedge-against-hallucination (see leakage scan above). Tone + vertical_context per client comes from `agent_personalities`, not hardcoded.
**Works for**: all 6 verticals ✅
**Configuration per client**:
- `agent_personalities` row with: `voice_tone`, `formality_level`, `vertical_context` (e.g. `mortgage_broker`, `beauty_studio`), `escalation_rules` jsonb, `prohibited_topics` text[]
- Channels enabled in `agent_channels_enabled`

**Missing pieces:** None for the engine itself. Vector retrieval is currently MVP (top-importance, not similarity) — Phase 5b enhancement noted in commit message.
**Strategic importance:** **Critical**.

---

### 5. Behavioral Intelligence

**Built in core?**: ✅ Yes
**File paths:**
- `workflows/api/intelligence/` (5 workflows from commit 25c0886):
  - `clx-behavioral-signal-ingestion-v1.json` (6h schedule)
  - `clx-behavioral-intelligence-v1.json` (30 min Claude classifier)
  - `clx-behavioral-trigger-engine-v1.json` (hourly archetype matcher)
  - `clx-archetype-seed-insurance-v1.json` *(per-vertical seed — insurance only so far)*
  - `clx-behavioral-archetype-learner-v1.json` (Sunday 02:00 conversion-rate updater)
- `behavioral_signals`, `signal_archetypes`, `behavioral_triggers`, `signal_subscriptions` → `db/migrations/behavioral-intelligence-schema.sql`
- `signal_archetypes.niche_name` UNIQUE(niche_name, archetype_name) — **truly multi-vertical schema**

**Universal?**: Yes. The §35 10-category taxonomy is universal (personal / business / industry / sports / news / social / vertical_specific / financial / geographic / calendar). The Claude classifier prompt explicitly comments *"Universal multi-vertical: signal can be from insurance, mortgage, real estate, dental, etc."* Per-vertical specifics are entirely in the seed archetypes.
**Works for**: all 6 verticals ✅ — **but only insurance has its seed library committed.**
**Configuration per client**:
- `clients.behavioral_intel_enabled = true` (per BI schema)
- `signal_subscriptions` rows per category (opt-in matrix, per client)
- `clients.niche_name` set (e.g. `mortgage_broker`, `beauty_studio`)

**Missing pieces:** **Per-vertical archetype seed workflows** for non-insurance verticals. Pattern is established (`clx-archetype-seed-insurance-v1` → mirror for mortgage / real_estate / dental / construction / beauty / logistics). Each is ~1-2 hours Claude Code per vertical, ~10-15 archetypes per vertical.
**Strategic importance:** **Critical** — this is the moat. Without per-vertical archetypes, the behavioral signals fire but the trigger engine has nothing to match against.

---

### 6. Daily Prioritization Engine

**Built in core?**: ✅ Yes
**File paths:**
- `workflows/clx-daily-plan-generator-v1.json` — 07:00 cron, Claude Haiku ranks tasks (dormant)
- `workflows/clx-task-classifier-v1.json` — mid-day single-lead reclassification (dormant)
- `agent_calendar_prefs` table referenced in CLAUDE.md / api-surface-audit (per-agent capacity + energy preferences)

**Universal?**: Yes. Zero insurance references in either workflow.
**Works for**: all 6 verticals ✅
**Configuration per client**:
- `agent_calendar_prefs` row per advisor (capacity, quiet hours, energy preferences)
- Anthropic API key bound
- 07:00 schedule trigger activated per advisor

**Missing pieces:** Energy management and hard-tasks-early features are described in §30 but the workflow body needs verification (only the prompt was inspected — workflow node-level config not exhaustively checked).
**Strategic importance:** **Important** — what differentiates "agent has 50 leads in pipeline" from "agent knows exactly which 3 to call first thing this morning."

---

### 7. Accountability / KPI Framework

**Built in core?**: 🟡 Partial
**File paths:**
- `agent_performance` table → `db/migrations/ai-agent-schema.sql:151` — daily rollup per client (messages_sent, messages_received, calls_outbound, calls_inbound, meetings_booked, meetings_attended, escalations_triggered, total_cost_cents, conversion_rate)
- `workflows/api/agent/clx-agent-daily-summary-v1.json` — 07:00 daily aggregation + email
- `workflows/clx-daily-summary-generator-v1.json` (legacy, dormant) — 23:00 per-agent summary
- `agent_costs` ledger (per-vendor cost tracking)

**Universal?**: Yes. All columns are vertical-agnostic.
**Works for**: all 6 verticals ✅
**Configuration per client**:
- `agent_channels_enabled` rows (defines which channels count toward metrics)
- Email recipient (advisor + supervisor)

**Missing pieces — this is the biggest gap in the framework:**

- **No `agent_goals` / `agent_kpis` / `agent_targets` table.** Performance is *tracked* but there is no schema for the *target* values. You can see "Sarah sent 47 messages this week" but you can't see "Sarah's weekly goal is 50, she's at 94%."
- **No goal-vs-actual rollup workflow.** Without target storage, no comparison exists.
- **No performance scoring formula.** Just raw counts.
- A targeted schema (~30 lines) + 1 rollup workflow (~150 lines) would close this.

**Strategic importance:** **Important** — required for the "are we on track?" view at supervisor / mga_principal level. Sale conversation with an MGA will hit this gap.

---

### 8. Mentor / Supervision (Universal)

**Built in core?**: 🟡 Partial
**File paths:**
- `team_members.reports_to_user_id` → `db/migrations/role-enum-update.sql:69` *(universal hierarchy primitive, Layer 1)*
- `mga_hierarchy` table → `db/migrations/insurance-mga-operations-schema.sql` *(insurance-only — `vertical_id='insurance'`)*
- `workflows/api/agent/clx-agent-escalation-v1.json` — escalates by `escalated_to_role` (advisor / supervisor / mga_principal / admin / compliance_officer)
- Daily summary workflows route to supervisor by role

**Universal?**: Partially. **The hierarchy primitive `team_members.reports_to_user_id` is universal**, but the only hierarchy-expansion logic that exists today lives in the insurance-MGA module (`mga_hierarchy` table + insurance-specific webhooks).
**Works for**: insurance ✅ | others: need universal supervisor-overview webhook.
**Configuration per client**:
- Populate `team_members.reports_to_user_id` (already works for any role + vertical)
- Define which roles supervise which roles per vertical

**Missing pieces:**
- **No universal `clx-team-supervisor-overview-v1` workflow.** Any non-insurance vertical with a supervisor structure (e.g. agency with team leads, beauty studio with senior aestheticians, mortgage brokerage with branch managers) currently has no way to query "all my reports' work."
- **No universal approval-workflow primitive.** Insurance has compliance_officer override (Layer 2 Part A); no universal "supervisor must approve this action" pattern.
- **Training/coaching tracking** has CE tracker for insurance, no universal equivalent.

**Strategic importance:** **Important** — every multi-person customer needs this.

---

### 9. Closing Pitch Enhancement

**Built in core?**: ✅ Yes
**File paths:**
- `workflows/clx-realtime-script-suggester-v1.json` — matches call state → ranked script suggestions (dormant)
- `workflows/clx-script-matcher-v1.json` — async dashboard-facing version (dormant)
- `workflows/clx-script-learning-loop-v1.json` — 02:00 nightly recompute of `conversion_rate` over 90 days (dormant)
- `workflows/clx-post-call-analyzer-v1.json` — per-call Claude Sonnet coaching analysis (dormant)
- `workflows/clx-transcript-classifier-realtime-v1.json` — Claude Haiku intent/sentiment/topics classifier (dormant)
- `workflows/clx-vapi-transcript-streamer-v1.json` — HMAC-verified Vapi transcript ingestion (dormant)
- `closing_scripts` table referenced as FK in `signal_archetypes.message_template_id` (BI schema line 85)

**Universal?**: Yes. Zero insurance references across any of these.
**Works for**: all 6 verticals ✅
**Configuration per client**:
- `clients.realtime_script_suggestions_enabled = true`
- Vapi webhook secret + Anthropic key
- `closing_scripts` library seeded per vertical (similar pattern to `signal_archetypes`)

**Missing pieces:**
- **Pre-meeting briefings** — not a dedicated workflow. Would be a useful net-new (~3 hours Claude Code): "Tomorrow you're meeting Sarah Johnson — here's their full context + 3 talking points + 2 likely objections."
- **`closing_scripts` table** is referenced as an FK but I did NOT verify the table itself exists in the migrations. May be Phase 4 follow-up.
- **Objection handling library** — same as `closing_scripts`; per-vertical seed needed (similar pattern to behavioral archetypes).

**Strategic importance:** **Important** — direct revenue impact.

---

### 10. Video Generation Pipeline

**Built in core?**: ✅ Yes
**File paths:**
- `workflows/api/video/` — 7 workflows (commit 25c0886):
  - `clx-video-script-generator-v1.json` — explicit 16-vertical persona fallback table (lines covered in leakage scan)
  - `clx-video-heygen-render-v1.json`
  - `clx-heygen-webhook-v1.json` (R2 automation)
  - `clx-video-delivery-router-v1.json`
  - `clx-video-landing-page-v1.json`
  - `clx-video-engagement-tracker-v1.json`
  - `clx-video-storage-cleanup-v1.json`
- `video_renders`, `video_engagement` → `db/migrations/delivery-channels-schema.sql`
- `clients.{preferred_persona_id, preferred_look_id, preferred_voice_id, custom_avatar_id}` (universal persona prefs)

**Universal?**: Yes — **explicitly designed multi-vertical**. The script-generator includes 16 verticals in its persona/look fallback table (insurance, insurance_broker, mortgage, real_estate, consulting, agencies, financial_advisors, legal, construction, contractors, field_services, cleaning, moving, personal_services, dental, service_industry).
**Works for**: all 6 verticals ✅ (4 personas × 3 looks = 12 combinations + custom_avatar_id for Scale tier)
**Configuration per client**:
- `clients.niche_name` set (drives the fallback)
- Optional: `clients.preferred_persona_id` + `preferred_look_id` override
- Optional: `clients.custom_avatar_id` (Scale tier — bring-your-own HeyGen avatar)

**Missing pieces:** None for the pipeline. Layer 2 video templates (`video_review_templates`) only seeded for insurance — other verticals need their own seed similar to behavioral archetypes.
**Strategic importance:** **Critical** — the moat.

---

## Summary

### Universal core engine completion status

| Status | Count | Features |
|---|---|---|
| ✅ Fully universal, ready as-is | **6/10** | Calendar Booking · No-show Detection · AI Conversation Handler · Behavioral Intelligence (engine, not seeds) · Daily Prioritization · Video Generation Pipeline |
| 🟡 Partial — small gap to close | **3/10** | Lead Distribution (assignment logic) · KPI Framework (goal-target schema) · Mentor/Supervision (universal supervisor webhook) |
| 🔴 Insurance-leaking | **0/10** | none |
| ✅ Bonus universal: **Closing Pitch Enhancement** is built across 6 workflows, all dormant | 1/10 | covered above |

The "10 features" actually came in at 7 fully universal + 3 partial + 0 leaking. **No feature has hard insurance assumptions blocking other-vertical use.**

### Recommended actions

**Priority 1 — Blocks first paying customer in any vertical:**
1. **Build per-vertical archetype seed workflows** for whichever verticals Mary onboards next (mortgage / real_estate / beauty / dental / logistics / agencies). Pattern is established by `clx-archetype-seed-insurance-v1`. ~1-2 hours per vertical × ~10-15 archetypes each = a single 1-day Claude Code session covers 4-6 verticals.
2. **Build lead auto-assignment workflow** (`clx-lead-auto-assign-v1`): watches `leads.assigned_advisor_id IS NULL`, applies round-robin / geographic / capacity-aware rules from a new `client_assignment_rules` jsonb column. ~4-6 hours Claude Code.

**Priority 2 — Important but not blocking first customer:**
3. **Add `agent_goals` schema + goal-vs-actual rollup workflow** (~6 hours). Enables performance scoring + "on-track?" supervisor view.
4. **Build universal supervisor-overview webhook** (`clx-team-supervisor-overview-v1`) reading from `team_members.reports_to_user_id` so any vertical with teams gets the same "all my reports' work" view. ~3 hours.
5. **Build pre-meeting briefing workflow** (`clx-pre-meeting-briefing-v1`): morning email to advisor with each day's meeting context + talking points + likely objections. ~3 hours.
6. **Seed `closing_scripts` table** if it doesn't exist + 1 universal script-library seeder per vertical.

**Priority 3 — Defer to Phase 5:**
7. Multi-attempt rebook + cold-mark logic in no-show workflow.
8. Surface §29-§34 dormant workflows in `insurance-mga-dashboard/` (and equivalent vertical dashboards) — "Daily Plan" / "Coaching" pages.
9. Universal approval-workflow primitive (Mary's supervisor must approve X) — generalizes the compliance_officer override pattern from Layer 2.
10. Move `leads.assigned_advisor_id` ALTER from `insurance-mga-operations-schema.sql` into a Layer 1 migration (clean-up).

### Verticals ready to onboard NOW

| Vertical | Status | Blockers |
|---|---|---|
| **Insurance** | ✅ Yes (with caveats) | Layer 2 activation pending per night notes (5 Mary tasks remaining) |
| **Mortgage** | 🟡 Almost | Needs (a) mortgage archetype seed workflow [1-2 hours], (b) niche_name configured, (c) optional Layer 2 mortgage module for FINTRAC compliance + lender appointments + commission ledger |
| **Real Estate** | 🟡 Almost | Needs real_estate archetype seed + niche_name + optional Layer 2 module (RECO compliance, brokerage hierarchy) |
| **Logistics** | ✅ Yes (with one quick add) | Just needs the logistics archetype seed (~1 hour). No regulator-driven Layer 2 module required. |
| **Beauty** | ✅ Yes (with one quick add) | Needs beauty archetype seed (~1 hour). Plus persona/look picker — likely Maria/warm. No Layer 2 needed. |
| **Dental** | ✅ Yes (with one quick add) | Needs dental archetype seed (~1 hour). RCDSO compliance is light vs FSRA; can defer Layer 2. |

**Bottom line:** for non-regulated verticals (logistics, beauty, dental, agencies, consulting, real_estate-non-licensed roles), Mary can onboard a customer this week if she has the per-vertical archetype seed. **The core engine itself is ready.**

### Recommended Part C scope (revised based on this audit)

Original Part C scope per night notes: insurer-facing read-only dashboards + production reports + compliance scorecards + demo tools (~4-6 hours Claude Code).

**Recommendation: split Part C into two halves OR expand scope:**

**Option A (faithful to original brief — 4-6 hours):**
- Keep insurer-facing dashboards as-is.
- Acknowledge in the doc that core-engine gaps (auto-assignment, goal schema, universal supervisor webhook) are deferred to Phase 5b.

**Option B (recommended — 6-8 hours, expanded Part C):**
- Core insurer-facing dashboards (4 hours) + production reports (1 hour) — unchanged.
- **PLUS the Priority-1 universal gap-closure:**
  - Per-vertical archetype seed workflows for mortgage + real_estate + beauty + dental + logistics + agencies (~2 hours total — they're seed data heavy, code is the same pattern).
  - Lead auto-assignment workflow (~2 hours).
- After Option B, Crystallux is ready to onboard any of 5-6 verticals THIS WEEK, not just insurance.

**Strong recommendation: Option B.** Insurer-facing dashboards are essential for selling to carriers, but multi-vertical readiness is essential for any non-insurance customer to be sellable at all. The marginal Claude Code cost is small; the strategic upside is large.

### Notes on uncertainty

- I did NOT inspect every Code-node body in every workflow. The leakage scan was textual grep + spot-check of flagged files. A workflow could contain a hidden insurance assumption inside a long Code node that didn't match the regex (e.g. logic that only makes sense for term life). Confidence is HIGH but not 100% — call it 90%.
- I assumed `closing_scripts` table exists per the FK in `signal_archetypes.message_template_id`. **Did not verify** with a separate migration grep — if the table doesn't exist, Closing Pitch Enhancement feature requires a schema add first.
- `agent_calendar_prefs` referenced in CLAUDE.md / api-surface-audit but **did not verify** with schema grep. Likely exists from §29-§31 era; if not, daily-plan-generator activation requires a schema add.

## Cross-references

- Comprehensive state audit (2026-05-11): [`2026-05-11-comprehensive-audit.md`](2026-05-11-comprehensive-audit.md)
- API surface audit: [`api-surface-audit.md`](api-surface-audit.md) — Bucket 2 dormant workflows including §29-§34 cluster
- Multi-vertical architecture: [`../architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`](../architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md)
- Product vision: [`../architecture/PRODUCT_VISION.md`](../architecture/PRODUCT_VISION.md)
- Agent vision: [`../agent/AGENT_VISION.md`](../agent/AGENT_VISION.md)
- Layer 2 insurance specs: [`../insurance-mga/`](../insurance-mga/) (vision + regulatory + reviews + video + security)
