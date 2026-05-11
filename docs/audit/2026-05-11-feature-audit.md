# Core Engine Feature Audit — May 11, 2026

> **Question:** For each of 7 specific universal features, is it actually built (with file paths) or just discussed?
>
> **Method:** Targeted grep across `db/migrations/`, `workflows/api/`, `workflows/` (legacy), plus per-feature workflow-node inspection.
>
> **One-line answer:** 1 fully built · 5 partially built · 1 not built. The unbuilt one (lead distribution) is the most strategically blocking gap; the partial ones each have a small concrete missing piece named below.
>
> **Cross-reference:** This is the deeper twin of [`2026-05-11-core-engine-universal-audit.md`](2026-05-11-core-engine-universal-audit.md). The universality audit asked *"is the engine vertical-agnostic?"* (yes). This audit asks *"is each feature actually implemented or just discussed?"* (mixed — see below).

---

## Feature 1 — No-show detection and response

**Status:** 🟡 Partial

**Files where implemented:**
- `db/migrations/delivery-channels-schema.sql:169` — `bookings.status` enum includes `no_show` value + CHECK constraint
- `workflows/clx-no-show-detector-v1.json` — 30-min scan workflow (top-level legacy, dormant)
- `workflows/clx-no-show-sms-recovery-v1.json` — auto-compose + Twilio SMS rebook offer (dormant)

**What works:**
- Schema captures missed appointments via `bookings.status='no_show'`
- 30-minute scan workflow detects appointments past their scheduled time without a `completed` transition
- Auto-sends rebook SMS via Twilio to the lead
- Reads per-advisor opt-in flag `agent_calendar_prefs.no_show_sms_enabled` (Mary toggles per advisor)

**What's missing:**
- **Multi-attempt rebook sequence** — current pattern is **single SMS only**. If the lead doesn't reply, no further escalation fires.
- **Cold-mark logic** — after N consecutive no-shows (e.g. 3 in 60 days) the lead should auto-transition to `lead_status='Closed Lost'` or similar. **Not implemented.**
- **No retry cadence** (1-day, 3-day, 7-day follow-up attempts)
- **No supervisor escalation** when a high-value lead repeatedly no-shows

**Strategic importance:** **High** for any service business with appointments. For Mary's insurance MGA specifically: no-show clients are a leading indicator of churn risk; the current single-attempt pattern leaks revenue.

**Recommended action:** Build a small follow-up workflow in **Part C** that chains off `no-show-sms-recovery-v1` to retry at 1d / 3d / 7d intervals, then auto-marks cold after the third failure. ~2 hours Claude Code. Can reuse the existing `clx-follow-up-v2` + `behavioral_triggers` pattern.

---

## Feature 2 — Mentor/supervisor relationships (universal)

**Status:** 🟡 Partial

**Files where implemented:**
- `db/migrations/role-enum-update.sql:65-70` — `team_members.reports_to_user_id` column + index. Documentation comment explicitly describes the hierarchy: *sub_agent → advisor → supervisor; advisor → mga_principal (MGA model); supervisor → client/principal*.
- `db/migrations/ai-agent-schema.sql:126` — `agent_escalations` table with `escalated_to_role` enum (advisor / supervisor / mga_principal / admin / compliance_officer)
- `workflows/api/agent/clx-agent-escalation-v1.json` — universal escalation router; finds recipient by client + role
- `workflows/clx-daily-summary-generator-v1.json` — supervisor-facing per-agent productivity summary (dormant)
- `workflows/clx-post-call-analyzer-v1.json` — per-call coaching analysis for supervisor review (dormant)
- `db/migrations/insurance-mga-operations-schema.sql` — `mga_hierarchy` table *(Layer 2 — insurance-only)*

**What works:**
- **Universal hierarchy primitive exists** — `team_members.reports_to_user_id` is a clean Layer 1 foundation.
- **Universal escalation router** works for any role allowlist.
- Daily summary + post-call coaching workflows surface supervisor visibility into subordinate work.

**What's missing:**
- **No universal `clx-team-supervisor-overview-v1` webhook.** A non-insurance vertical with team structure (e.g. agency with team leads, brokerage with branch managers) has no "all my reports' work" data endpoint. Insurance has it inside `clx-mga-insurance-principal-overview-v1` but it's Layer 2.
- **No supervisor approval-workflow primitive.** Layer 2 has compliance_officer override (Part A); no universal "supervisor must approve this action" pattern.
- **No training/coaching tracking schema.** Insurance has `advisor_licenses.ce_hours_completed`; no universal equivalent for non-licensed verticals (sales training hours, certifications, internal courses).
- **No performance review automation.** No quarterly/annual review schema or workflow.

**Strategic importance:** **High** — every multi-person customer (MGA / agency / brokerage / large client) needs this. Mary's 10-advisor MGA is the first proof case; future agency customers will be the same shape.

**Recommended action:** Build in **Part C**:
1. `clx-team-supervisor-overview-v1` webhook (~3 hours) — reads `team_members.reports_to_user_id` and returns rolled-up activity + KPIs for any supervisor user.
2. Defer training/approval/review primitives to Phase 5b.

---

## Feature 3 — Accountability / KPI framework (universal)

**Status:** 🟡 Partial — **the biggest schema gap in the platform**

**Files where implemented:**
- `db/migrations/ai-agent-schema.sql:151-166` — `agent_performance` table with daily rollup: `messages_sent`, `messages_received`, `calls_outbound`, `calls_inbound`, `meetings_booked`, `meetings_attended`, `escalations_triggered`, `total_cost_cents`, `conversion_rate` (computed)
- `db/migrations/ai-agent-schema.sql:174` — `agent_costs` ledger (per-vendor cost tracking)
- `workflows/api/agent/clx-agent-daily-summary-v1.json` — daily aggregation + email
- `workflows/clx-daily-summary-generator-v1.json` — 23:00 per-agent productivity summary (legacy, dormant)
- `workflows/clx-activity-tracker-v1.json` + `clx-activity-classifier-v1.json` — Productivity Tier (§32, dormant)

**What works:**
- **Counts are tracked.** Per-day rollup of every activity an advisor performs.
- Cost tracking per vendor (Anthropic, Twilio, HeyGen) per client.
- Daily email summary surfaces yesterday's metrics.

**What's missing — the entire goal/target side of the framework:**
- **`agent_goals` / `agent_kpis` / `agent_targets` table — does not exist.** Grep confirmed zero matches across all 9 migrations.
- No way to express "Sarah's weekly goal is 50 messages, 5 meetings, $5k commission." Current schema can only answer "she sent 47 messages this week" — cannot answer "she's at 94% of her goal."
- **No performance scoring algorithm.** Just raw counts; no composite score.
- **No goal-vs-actual rollup workflow.** Without target storage, no comparison can run.
- **No quota / commit / accountability dashboards** beyond the daily-summary email.

**Strategic importance:** **High for any sales organization customer.** Sale conversation with an MGA or agency will hit this gap directly: *"How do I know if my reps are on track this quarter?"* Currently no answer.

**Recommended action:** Build in **Part C**:
1. Schema: `agent_goals` table (~30 lines) with `(advisor_id, period_start, period_end, kpi_name, target_value, baseline_value)` rows.
2. Workflow: `clx-kpi-rollup-v1` daily that joins `agent_performance` × `agent_goals` and emits goal-vs-actual percentages.
3. Surface in supervisor dashboard.

Total: ~6 hours Claude Code.

---

## Feature 4 — Calendar management (universal)

**Status:** 🟡 Partial — **one missing table referenced by 2 workflows**

**Files where implemented:**
- `db/migrations/delivery-channels-schema.sql:162` — universal `bookings` table (lead_id, advisor_id, scheduled_at, duration, status, provider, intake_answers, meeting_link)
- `db/migrations/ai-agent-schema.sql:240` — `agent_schedules.timezone` (default `America/Toronto`) + `quiet_hours_start`/`end` + `max_actions_per_day`
- `workflows/api/booking/clx-booking-create-v1.json` — Cal.com v2 API integration
- `workflows/clx-booking-v2.json` — Calendly webhook handler (top-level, production-active per audit)
- `workflows/clx-appointment-geocoder-v1.json` — Nominatim geocoding (dormant)
- `workflows/clx-route-optimizer-v1.json` — Haversine nearest-neighbour route ordering (dormant)
- `workflows/clx-reshuffle-suggester-v1.json` — replacement-lead suggestion when slot vacates (dormant)

**What works:**
- Universal `bookings` table is vertical-agnostic.
- Cal.com handles timezone + availability + conflict resolution natively.
- Per-client timezone in `agent_schedules` row.
- Geographic clustering: appointments geocoded then route-optimized.
- Slot-vacated reshuffle picks the best replacement lead.

**What's missing:**
- **`agent_calendar_prefs` table — referenced by `clx-no-show-sms-recovery-v1.json` but NOT created in any migration in this repo.** Either it was created by a pre-`scale-sprint-v1` migration that's not in `db/migrations/`, or it's an orphan reference. **Mary should verify in Supabase: `SELECT to_regclass('public.agent_calendar_prefs');`** Until then, the no-show recovery workflow may fail at run time on the missing table.
- **No recurring meeting (rrule) support.** Single-event bookings only. For verticals with weekly check-ins (e.g. dental cleanings every 6 months, beauty salon monthly facials) recurring would be a value-add.
- **No multi-attendee meetings.** Single-advisor + single-lead pattern only.

**Strategic importance:** **High** for the booking core; **Medium** for recurring + multi-attendee (vertical-specific).

**Recommended action:**
1. **Verify in Supabase** whether `agent_calendar_prefs` exists. If not, write a migration to add it (~15 min) — needed before activating no-show workflows.
2. Recurring + multi-attendee → Phase 5b.

---

## Feature 5 — Smart prioritization (hard tasks early)

**Status:** ✅ **Fully built** (the only one of the 7) — with one nuance

**Files where implemented:**
- `workflows/clx-daily-plan-generator-v1.json` — 12-node workflow: 07:00 cron / manual webhook → Parse Input → Fetch Active Clients → Fan Out → Compute Tasks (RPC) → Prep Claude Prompt → Claude Rerank → Parse + Fallback → Upsert Plan → Build Response
- `workflows/clx-task-classifier-v1.json` — ad-hoc single-lead reclassification

**What works:**
- Schedule trigger fires at 07:00 daily (per advisor).
- Heuristic base ranking via `Compute Tasks` RPC (Postgres function).
- **Claude Sonnet re-ranks** with explicit rules (verified inline):
  - SLA-breached replies first
  - Hot leads (`lead_score >= 80`)
  - No-show rebooks
  - Upcoming calls (sorted by time)
  - Stale follow-ups
  - Tiebreaker: higher `lead_score`
- Output is structured JSON with `rank` + `reason` per task + `summary_line` (≤140 char morning briefing).
- Plan upserted to a persistent `agent_daily_plans` table (referenced via `Upsert Plan` node — not verified in migrations, similar concern to `closing_scripts`).

**What's missing (nuance):**
- **No explicit energy management / "hard cognitive tasks when fresh" logic.** The prompt asks Claude to prioritize by urgency + lead score, not by cognitive load. A discovery call with a hot lead might rank above a complex objection-handling call, even though the objection call needs more energy.
- **No time-of-day optimization explicit.** The prompt doesn't say "schedule complex calls before noon, admin work after lunch."
- **`agent_daily_plans` table referenced via Upsert Plan node — Mary should verify it exists in Supabase** (same concern as `agent_calendar_prefs`).

**Strategic importance:** **Medium-High.** Core prioritization works; energy-management is icing.

**Recommended action:**
1. Verify `agent_daily_plans` table in Supabase.
2. Add energy-management to the Claude prompt in Phase 5b (single-line prompt addition — `"Prefer high-cognitive-load tasks (discovery, objection handling) early in the day; admin and quick-replies can fill afternoon"`). Zero schema change.

---

## Feature 6 — Closing pitch enhancement

**Status:** 🟡 Partial — **workflows built but the underlying table appears missing**

**Files where implemented:**
- `workflows/clx-realtime-script-suggester-v1.json` — 11-node workflow that matches call state → ranked script suggestions (dormant)
- `workflows/clx-script-matcher-v1.json` — async dashboard-facing version (dormant)
- `workflows/clx-script-learning-loop-v1.json` — 02:00 nightly recompute of `conversion_rate` per script over 90d (dormant)
- `workflows/clx-post-call-analyzer-v1.json` — per-call Claude Sonnet coaching analysis (dormant)
- `workflows/clx-transcript-classifier-realtime-v1.json` — Claude Haiku intent/sentiment/topics classifier (dormant)
- `workflows/clx-vapi-transcript-streamer-v1.json` — HMAC-verified Vapi transcript ingestion (dormant)
- **FK reference only:** `db/migrations/behavioral-intelligence-schema.sql:85` — `signal_archetypes.message_template_id` references `closing_scripts.id`

**What works (in theory):**
- The script-suggester pipeline is 6 workflows deep and architecturally complete.
- Real-time call transcripts → Claude intent classifier → script library match → ranked suggestions to dashboard.
- Learning loop tunes which scripts close best.

**What's missing — critical:**
- **`closing_scripts` table is NOT created in any committed migration.** Grep confirmed zero `CREATE TABLE.*closing_scripts` matches in `db/migrations/`. The table is referenced as a foreign key in BI schema (line 85), so **either it exists from a pre-`scale-sprint-v1` migration not in this repo, or the FK is dangling.** Mary should verify: `SELECT to_regclass('public.closing_scripts');`
- **If the table doesn't exist:** none of the 6 closing-pitch workflows can function. The `Match Scripts (RPC)` node in the suggester would fail.
- **No pre-meeting briefing workflow.** Separate concept from real-time suggestion. "Tomorrow you're meeting Sarah Johnson — here's her full context + 3 talking points + 2 likely objections." Not built.
- **No objection-handling library.** Depends on `closing_scripts` seed; even if the table exists, the universal/per-vertical script library needs seeding (similar to `signal_archetypes`).

**Strategic importance:** **High.** Direct revenue impact at the closing moment. Insurance MGA sales conversations explicitly reference "AI coaching during the call."

**Recommended action:** In **Part C**:
1. **Verify `closing_scripts` table.** If missing, write the migration (~30 lines).
2. Build the pre-meeting briefing workflow `clx-pre-meeting-briefing-v1` (~3 hours): reads tomorrow's bookings + lead context + recent signals → Claude generates briefing → emails advisor at 18:00.
3. Defer the per-vertical objection library seed to a follow-up (1-2h per vertical, similar pattern to archetype seeds).

---

## Feature 7 — Lead distribution engine

**Status:** 🔴 **Not built**

**Files where implemented:**
- `db/migrations/insurance-mga-operations-schema.sql:350` — `leads.assigned_advisor_id` column + index *(architectural note: Layer 2 migration touches a universal table; column itself is universal)*
- `workflows/api/insurance-mga/clx-mga-insurance-advisor-leads-v1.json` — **reads** `assigned_advisor_id` for advisor dashboard scoping
- `workflows/clx-campaign-router-v2.json` — verified inline: routes leads to **outreach campaigns**, NOT to advisors. Zero advisor-assignment logic.

**What works:**
- The column exists.
- Insurance dashboard can filter leads by assigned advisor (display only).

**What's missing — everything else:**
- **No round-robin assignment workflow.** A new lead lands with `assigned_advisor_id=NULL` and stays there forever unless manually set.
- **No geographic matching.** No workflow says "this lead in Mississauga → advisor closest to Mississauga."
- **No specialty matching.** No workflow routes "this lead needs term life" → "advisor X specializes in term life."
- **No performance-based distribution.** No "top-performer gets first pick" logic.
- **No capacity management.** No "advisor Y is full (book at max), assign next lead to advisor Z."
- **No client_assignment_rules table** to express vertical-specific rules.

**Strategic importance:** **Critical** for any multi-advisor customer. Mary's MGA has 10 advisors — without auto-assignment, Mary herself becomes the bottleneck for every new lead. **This is arguably the single most strategically important gap in the universal core.**

**Recommended action:** Build in **Part C** as the highest-priority addition:
1. Schema: `client_assignment_rules` jsonb column on `clients` (~5 lines) expressing per-client strategy.
2. Workflow `clx-lead-auto-assign-v1` (~150 lines, ~4 hours): watches new `leads` rows with `assigned_advisor_id IS NULL`, evaluates rule (round-robin / geographic / specialty / capacity), populates the column, logs to `regulatory_audit_log` (if vertical_id set) or a universal `assignment_log` audit table.
3. Surface a "next lead in queue" view in advisor dashboards.

Total: ~5-6 hours Claude Code.

---

## Summary

### Counts

| Status | Count | Features |
|---|---|---|
| ✅ Fully built | **1 of 7** | F5 Smart prioritization (daily plan generator) |
| 🟡 Partial | **5 of 7** | F1 No-show · F2 Mentor/supervisor · F3 KPI framework · F4 Calendar · F6 Closing pitch |
| 🔴 Not built | **1 of 7** | F7 Lead distribution |
| ❓ Documented but not implemented | 0 of 7 | — |

### Critical gaps for first paying customer

In rank order of strategic blocking:

1. **F7 Lead distribution** — every multi-rep customer needs this. Mary's 10-advisor MGA is the immediate proof case.
2. **F3 KPI framework — missing the entire goal/target side.** Sale-conversation killer ("how do I see if reps are on track?").
3. **F6 Closing pitch** — workflows built but `closing_scripts` table appears missing; Mary should verify.
4. **F1 No-show multi-attempt + cold-mark** — moderate gap; first-attempt SMS works.
5. **F2 Universal supervisor-overview webhook** — important for non-insurance customers.

### Two flagged verifications (Mary, 5 minutes in Supabase)

```sql
SELECT to_regclass('public.closing_scripts');       -- F6 depends on this
SELECT to_regclass('public.agent_calendar_prefs');  -- F1 + F4 depend on this
SELECT to_regclass('public.agent_daily_plans');     -- F5 Upsert Plan node depends on this
```

If any returns `NULL`, that's a missing table referenced by a built workflow — needs a migration before activation. **High-priority pre-Part-C item.**

### Recommended Part C scope (revised)

Adding to the original "insurer-facing dashboards + production reports + demo tools" (4-6 hours):

**Priority additions (~10 hours total Claude Code → Part C becomes 14-16 hours):**

1. **F7 — Lead auto-assignment workflow + `client_assignment_rules` column** (~5-6 hours). **Highest strategic value.**
2. **F3 — `agent_goals` schema + KPI rollup workflow** (~6 hours). Enables supervisor accountability view.
3. **F2 — Universal `clx-team-supervisor-overview-v1` webhook** (~3 hours). Reuses `team_members.reports_to_user_id`.
4. **F1 — Multi-attempt rebook + cold-mark chained off no-show recovery** (~2 hours).
5. **F6 — Pre-meeting briefing workflow + verify/create `closing_scripts` table** (~3 hours).

**Alternative — original 4-6 hour scope** keeps Part C insurer-facing only and defers F7 / F3 / F2 / F1 / F6 to a Phase 5b sprint. Less risky in a single session but delays multi-vertical readiness by ~2 weeks.

**Strong recommendation: include at minimum F7 in Part C** (lead distribution). Without it, Mary's MGA cannot scale past her personal capacity to manually assign leads — that's a launch-week blocker, not a polish item.

---

## Cross-references

- Comprehensive state audit: [`2026-05-11-comprehensive-audit.md`](2026-05-11-comprehensive-audit.md)
- Universality audit (vertical-agnostic check): [`2026-05-11-core-engine-universal-audit.md`](2026-05-11-core-engine-universal-audit.md)
- Phased build plan: [`../agent/build-phases.md`](../agent/build-phases.md)
- Agent vision: [`../agent/AGENT_VISION.md`](../agent/AGENT_VISION.md)
- Operations handbook: [`../architecture/OPERATIONS_HANDBOOK.md`](../architecture/OPERATIONS_HANDBOOK.md)
