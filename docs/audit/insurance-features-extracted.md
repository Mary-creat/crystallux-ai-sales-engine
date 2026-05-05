# Insurance-relevant features — extracted from Crystallux handbooks

**Generated:** 2026-05-05
**Purpose:** scoping reference for the **Advisor Dashboard** build phase. Mary needs the exhaustive list of every feature the handbooks reference for insurance brokers / advisors / sub-agents / MGA principals so nothing is missed during scoping.
**Sources:** `docs/architecture/OPERATIONS_HANDBOOK.md` (2,505 lines), `docs/architecture/BUSINESS_PLAN.md` (765 lines), `docs/architecture/migrations/*.sql` (35+ files), `docs/operations/*.md`, `docs/business/service-packages.md`, `docs/STRIPE_PRODUCTS_SPEC.md`, `docs/MARY_*.md`, `site/industries/insurance-brokers.html`, `workflows/*.json` (52 workflow files, 18 admin/client API JSONs).

---

## How to read this document

Three buckets. Every line links back to the canonical source so the spec/code-of-truth is one click away.

- **Bucket 1 — Already built**: workflow JSON exists in `workflows/`, migration is committed under `docs/architecture/migrations/`, and a dashboard panel ID is wired (even if `active: false` per the dormant-by-default policy). These need an **Advisor Dashboard surface** to be useful to the new role; the backend is done.
- **Bucket 2 — Designed but not built**: handbook describes the feature with enough detail that a workflow + migration + dashboard panel could be implemented from the spec alone. No code exists yet.
- **Bucket 3 — Mentioned but not specced**: one-line aspirations in the BUSINESS_PLAN, niche-overlay copy, or sales pages. No technical detail. Each needs a discovery pass before scoping.

> **Important framing — the platform is vertical-agnostic.** Per BUSINESS_PLAN §6, almost every "insurance" feature in this list is actually built as a generic platform capability that the `niche_overlays.insurance_broker` row tunes for advisors. The Advisor Dashboard is a *role + panel composition*, not a parallel codebase.

---

## Bucket 1 — Already built (backend complete; needs Advisor Dashboard surface)

### 1.1 Calendar reshuffling + no-show recovery
- **Source:** OPERATIONS_HANDBOOK §29 (Calendar Restructuring + No-Show Recovery, Phase B.12a-2).
- **Schema:** [`2026-04-24-calendar-restructuring.sql`](../architecture/migrations/2026-04-24-calendar-restructuring.sql) — adds `appointment_log`, `calendar_reshuffle_log`, `agent_calendar_prefs`, plus 4 SECURITY DEFINER RPCs (`mark_appointment_no_show`, `get_daily_appointments`, `get_reshuffle_candidates`, `record_reshuffle`).
- **Workflows (3, dormant):** `clx-no-show-detector-v1` (30-min Schedule), `clx-no-show-sms-recovery-v1` (Twilio SMS, CASL "Reply STOP"), `clx-reshuffle-suggester-v1`.
- **Dashboard panel:** `#yourDaySection` (admin + client) with date picker, summary strip, per-appointment timeline, status chips (completed / no-show / cancelled / rebooked / upcoming), join-meeting links.
- **Advisor Dashboard wiring needed:** expose `#yourDaySection` to the advisor role with `agent_id` filter; add a "Suggest replacement" button that calls `clx-reshuffle-suggester-v1` from the panel.

### 1.2 Morning priority task ordering ("Today's Plan")
- **Source:** OPERATIONS_HANDBOOK §30 (Morning Priority Task Ordering, Phase B.12a-3) + [`AGENT_PREFERENCE_ONBOARDING.md`](../operations/AGENT_PREFERENCE_ONBOARDING.md).
- **Schema:** [`2026-04-24-morning-priority-ordering.sql`](../architecture/migrations/2026-04-24-morning-priority-ordering.sql) — `daily_task_plan`, `task_completion_log`, extended `agent_calendar_prefs` (9 task-ordering fields incl. `morning_focus_block`, `daily_task_cap`, `reply_sla_hours`, `hot_lead_threshold`, `custom_order` jsonb, `notification_email`).
- **Workflows (2, dormant):** `clx-daily-plan-generator-v1` (07:00 Schedule + manual webhook; Claude Haiku re-rank), `clx-task-classifier-v1` (ad-hoc per-lead reclassification).
- **Dashboard panel:** `#todaysPlanSection` — `summary_line` header + ranked task list with category chip, due-by time, **SLA breach badge**, "Done" button writing `task_completion_log`, and "Regenerate" button.
- **Advisor surface needed:** `#todaysPlanSection` per advisor (currently admin + client only). Per-agent SLA / cap / focus block via `agent_calendar_prefs`.

### 1.3 Geographic / route optimization (drive-time minimisation)
- **Source:** OPERATIONS_HANDBOOK §31 (Phase B.12b-1).
- **Schema:** [`2026-04-24-geographic-optimization.sql`](../architecture/migrations/2026-04-24-geographic-optimization.sql) — geo columns on `appointment_log` (lat/long/geocoded_at/geocoder/travel_time_prev_min/drive_distance_km/route_batch_id), client base anchor (`base_latitude`, `base_longitude`, `travel_optimization_enabled`, `max_daily_km`, `preferred_drive_speed_kmh`), `travel_optimization_log` (one row per client/agent/date), 4 RPCs.
- **Workflows (2, dormant):** `clx-appointment-geocoder-v1` (Nominatim, free, 1 req/sec), `clx-route-optimizer-v1` (haversine nearest-neighbour from base).
- **Dashboard panel:** `#routeMapSection` — Leaflet (free, no key), Load route + Optimize buttons, before/after km + minutes.
- **Insurance relevance:** OPERATIONS_HANDBOOK §31 explicitly names insurance brokers as a target vertical for this feature ("verticals where agents travel between appointments").
- **Advisor surface needed:** wire `#routeMapSection` per advisor + per day; default `travel_optimization_enabled=true` for advisor-role accounts.

### 1.4 Productivity tracking + supervisor / accountability dashboard
- **Source:** OPERATIONS_HANDBOOK §32 (Productivity Tier Activation, Phase B.12b-2) + [`PRODUCTIVITY_TRACKING_CONSENT.md`](../operations/PRODUCTIVITY_TRACKING_CONSENT.md).
- **Schema:** [`2026-04-25-productivity-client-facing.sql`](../architecture/migrations/2026-04-25-productivity-client-facing.sql) — `agent_activity_log` (event-level; check constraints on activity_type + classification), `agent_daily_summary` (UNIQUE agent+date; trend = improving/stable/declining; `coaching_flags` jsonb), `team_members` consent columns (`productivity_tracking_consent`, `_at`, `_version`, `share_with_manager`), `clients.productivity_tier_enabled` + price + flip RPC, plus `record_agent_activity` (consent-gated), `classify_activity_heuristic`, `calculate_daily_summary`, `enable_productivity_tier`.
- **Workflows (3, dormant):** `clx-activity-tracker-v1` (15-min Schedule + webhook), `clx-activity-classifier-v1` (Claude Haiku batch of 20), `clx-daily-summary-generator-v1` (23:00 Schedule; sends congratulations email on `trend='improving'`, focus email on `score < 50`).
- **Dashboard panels:**
  - `#teamProductivitySection` (admin only — **the supervisor view**): client filter + date, green/yellow/red dot + score + trend arrow + 7-day average per agent, CSV export. Only consenting agents listed (no outing of opt-outs).
  - `#myProductivitySection` (client / agent self-view): today / 7d / 30d cards, productive vs neutral vs unproductive minutes, coaching flags callout, "Share with manager" toggle.
- **Pricing:** **$1,000 / mo per client** add-on (per OPERATIONS_HANDBOOK §32; sized as Tier B in BUSINESS_PLAN's "Crystallux Manager" Service 4 pricing).
- **Coaching framework (built-in):** 3+ consecutive red days → coaching flag; improvement-streak celebration email; <60 min tracked → `LOW_TRACKED_TIME` flag with disclaimer.
- **Compliance:** PIPEDA-aware. Consent versioning + withdrawal flag flips through to the very next event. Retention 12 mo raw → anonymise.
- **Advisor surface needed:** `#teamProductivitySection` re-skinned for **MGA principal / supervisor** role with sub-agent rollup. Existing schema already supports it via `team_members.client_id` linkage.

### 1.5 Listening Intelligence (live-call transcription + post-call coaching)
- **Source:** OPERATIONS_HANDBOOK §33 (Phase B.12c-1) + [`CALL_RECORDING_CONSENT.md`](../operations/CALL_RECORDING_CONSENT.md).
- **Schema:** [`2026-04-25-listening-intelligence.sql`](../architecture/migrations/2026-04-25-listening-intelligence.sql) — `call_transcript_chunks` (per Vapi chunk; intent + sentiment + topics), `call_event_log` (per-call rollup; outcome, sentiment trajectory, key objections, claude_analysis), client + team_member consent columns + script disclosure, 5 RPCs incl. `process_transcript_chunk` (consent-gated; silently drops on fail), `get_call_insights`, `get_agent_call_patterns`, `enable_listening_intelligence`, `finalize_call_analysis`.
- **Workflows (3, dormant):** `clx-vapi-transcript-streamer-v1` (HMAC-verified, fast respond-200), `clx-transcript-classifier-realtime-v1` (Claude Haiku 4.5, 2.5s timeout), `clx-post-call-analyzer-v1` (Claude Sonnet 4.5).
- **Dashboard panels:** `#liveCallSection` (transcript live-tail, sentiment bar, intent strip, topic cloud, 2s polling — replace with Supabase Realtime at activation); `#postCallSection` (objections, opportunities missed, coaching recommendations).
- **Pricing:** **$2,500 / mo per client** add-on (Tier C in BUSINESS_PLAN; ~Crystallux Coach Executive equivalent).
- **Compliance:** Canadian two-party consent. Default disclosure script seeded into `clients.customer_consent_disclosure_script`. `CONSENT_VIOLATION_DETECTED` monitor at critical severity.

### 1.6 Real-time closing-script pop-ups + library
- **Source:** OPERATIONS_HANDBOOK §28 (Closing Intelligence Activation) + §34 (Real-Time Closing Script Pop-Ups).
- **Schema:** [`2026-04-18-closing-intelligence.sql`](../architecture/migrations/2026-04-18-closing-intelligence.sql) (library: `discovery_frameworks`, `objection_handlers`, `closing_scripts`, `post_call_sequences`, `proposal_templates`, `competitor_intelligence`) + [`2026-04-24-closing-intelligence-client-facing.sql`](../architecture/migrations/2026-04-24-closing-intelligence-client-facing.sql) (usage tracking, RPCs `record_script_usage`, `get_scripts_for_lead`, `get_agent_script_performance`) + [`2026-04-25-realtime-script-suggestions.sql`](../architecture/migrations/2026-04-25-realtime-script-suggestions.sql) (`script_suggestion_log`, `match_script_to_state`, `log_suggestion_shown`, `log_suggestion_feedback`, `refresh_script_conversion_rates`, `enable_realtime_script_suggestions`).
- **Insurance-specific seeded content (in `2026-04-18-closing-intelligence.sql`):**
  - **Discovery framework** for `insurance_broker` (6 questions covering products sold — life, disability, critical illness, group, P&C — book size, bottlenecks).
  - **9 insurance-specific objection handlers** (price / timing / trust / authority — incl. captive-agent / MGA-restriction logic / need / competitor / assumptive / urgency / risk_reversal / summary / choice / testimonial). Pre-loaded with FSRA-correct framing, RIBO-safe language, and ROI math grounded in $2,500-$8,000 commission-per-policy.
  - **Closing scripts** for `insurance_broker` × `pipeline` × `growth`.
  - **Post-call sequences** for `insurance_broker` × `interested / needs_think / price_objection / not_now / no_fit` (8 templates across email + SMS).
  - **Competitor intelligence** for `insurance_broker` covering Apollo + LinkedIn Sales Navigator + traditional MGA recruiters / DIY HubSpot.
- **Workflows (3, dormant):** `clx-script-matcher-v1` (Claude Sonnet 4.5 ranking with RPC fallback), `clx-realtime-script-suggester-v1` (live-call trigger), `clx-script-learning-loop-v1` (02:00 Schedule; recomputes conversion_rate over 90d).
- **Dashboard panels:** `#closingIntelligenceSection` (5 tabs: Discovery / Objections / Closing / Follow-up / Competitor; per-agent 30-day performance strip), `#scriptSuggestionCard` (floating bottom-right, Use this / Different one / Dismiss + Ctrl+U / Ctrl+N / Ctrl+D shortcuts), `#suggestionFeedSection` (post-call timeline of every suggestion + agent action + response time — manager coaching surface).

### 1.7 Voice notes (Whisper-powered)
- **Source:** OPERATIONS_HANDBOOK §22 (Admin Copilot, capability 4 — voice input).
- **Workflow (live):** `clx-copilot-whisper-v1` (MediaRecorder → Whisper API → transcription auto-populates input).
- **Cost:** $0.006 USD / minute of audio.
- **Currently:** admin-only via the ✦ Copilot FAB. **Advisor surface needed:** repurpose the Whisper workflow as a generic "voice note" capture for advisor field notes (post-meeting recap dictation). The transcription pipeline already exists; add a destination table (e.g., `advisor_voice_notes`) and a panel.

### 1.8 Multi-channel outreach (email / LinkedIn / WhatsApp / voice / video / SMS)
- **Source:** OPERATIONS_HANDBOOK §14 (Multi-Channel Activation) + niche-overlay copy.
- **Workflows (live or dormant):** `clx-outreach-generation-v2`, `clx-outreach-sender-v2`, `clx-linkedin-outreach-v1`, `clx-whatsapp-outreach-v1`, `clx-voice-outreach-v1` (DNCL-gated), `clx-voice-result-webhook-v1`, `clx-video-outreach-v1`, `clx-video-ready-v1`, `clx-no-show-sms-recovery-v1` (already cited).
- **Insurance-specific:** voice script template seeded in [`2026-04-23-multi-channel.sql`](../architecture/migrations/2026-04-23-multi-channel.sql) with renewal-window framing.

### 1.9 Renewal-window sourcing (lead intelligence)
- **Source:** [`site/industries/insurance-brokers.html`](../../site/industries/insurance-brokers.html) ("60 to 90 days before their renewal date") + [`2026-04-18-niche-overlays.sql`](../architecture/migrations/2026-04-18-niche-overlays.sql) (`pain_signals` includes "no renewal retention system visible") + niche-overlay search keywords (`insurance broker ontario / licensed insurance / financial advisor insurance`).
- **Implementation today:** the lead-discovery + lead-research workflows surface policyholders via Google Maps + Apollo using the seeded ICP. The "60-90 days before renewal" signal is *not* itself a real-time data source today — it's framed as an outreach window guarantee (not enforced by code).
- **Gap to close for Advisor Dashboard:** see Bucket 2 §2.4 ("renewal retention system") — the surface is sold but the signal is heuristic.

### 1.10 Compliance-aware outreach (CASL / RIBO / FSRA / DNCL / E&O / KYC framing)
- **Source:** [`2026-04-18-niche-overlays.sql`](../architecture/migrations/2026-04-18-niche-overlays.sql) `compliance_notes` column for `insurance_broker`.
- **What's coded:**
  - CASL footers (sender ID + mailing address + one-click unsubscribe) injected on every send.
  - DNCL gate on voice (`clx-voice-outreach-v1` short-circuits if `do_not_contact=true`).
  - FSRA-aware copy in objection handlers (no guaranteed-outcome promises, advisor authority over placement).
  - **Term glossary baked into Claude prompts:** policy, premium, underwriting, commission, renewals, KYC, LLQP, FSRA, MGA, carrier, E&O insurance, continuing education (CE), book of business, client suitability, needs analysis, beneficiaries.
- **Insurance-specific dashboard labels** (per `niche_overlays.dashboard_labels`):
  - Leads → "Prospects"
  - Outreach Sent → "Outreach Campaigns"
  - Replied → "Responses Received"
  - Meetings → "Discovery Calls"
  - Deals → "Policies in Pipeline"
  - Closed Won → "Policies Written"
  - Deal Value → "Estimated Commission"
  - Conversion Rate → "Close Rate"
- **Advisor Dashboard implication:** when role=advisor + niche=insurance_broker, the dashboard MUST swap labels per `niche_overlays.dashboard_labels`. The schema is already there — it's a UI plumbing job.

### 1.11 Smart reminders (SLA-driven)
- **Built-in:**
  - Daily-plan SLA badges (§30) escalate inbound replies after `reply_sla_hours` (default 4h) per agent.
  - Stale-lead detection (`clx-pipeline-update-v2`) with thresholds: 2h / 24h / 30d depending on lead status.
  - No-show detection runs every 30 min and fires SMS recovery (§29).
  - Agent daily summary email (§32) congratulates trend-improving / focuses score-<50 agents.
- **Pricing tier mapping:** OPERATIONS_HANDBOOK §32 ("traffic-light dashboards for managers, and a private self-view for agents") + STRIPE_PRODUCTS_SPEC.md products tied to founding $1,997 + add-ons.

### 1.12 Stripe billing for insurance broker tier
- **Source:** [`STRIPE_PRODUCTS_SPEC.md`](../STRIPE_PRODUCTS_SPEC.md) §10 (Crystallux Insurance Broker Founding $1,997/mo, `STRIPE_PRICE_INSURANCE_BROKER_FOUNDING_1997`).
- **Workflow (live):** `clx-stripe-provision-v1`, `clx-stripe-webhook-v1`.
- **Schema:** [`2026-04-23-stripe-billing.sql`](../architecture/migrations/2026-04-23-stripe-billing.sql) (subscription_status, subscription_plan, monthly_retainer, trial_ends_at, etc.).

### 1.13 Market Intelligence add-on (signal-driven scaling)
- **Source:** OPERATIONS_HANDBOOK §27 + [`ROADMAP_B9_MARKET_INTELLIGENCE.md`](../architecture/ROADMAP_B9_MARKET_INTELLIGENCE.md).
- **Insurance-specific signals already roadmapped:** Bank of Canada interest-rate moves → mortgage broker + travel insurance pivots; cross-sell logic between travel-insurance and mortgage-broker books (ROADMAP §line 436).

---

## Bucket 2 — Designed but not built (clear spec, no code)

### 2.1 Sub-agent / supervisor "MGA principal" dashboard
- **Source:** BUSINESS_PLAN §5 (MGA business line) + §4 Service 4 (Crystallux Manager: "Daily briefings on team productivity, leaderboards, alerts on at-risk team members, accountability tracking, performance reviews — all automated").
- **What exists today:** the `#teamProductivitySection` (admin-only) renders one client's agents. The MGA principal sub-agents are stored in `team_members.client_id = <MGA-client-uuid>`.
- **What's missing:** a dedicated **advisor / MGA-principal role** in the dashboard role model (currently only admin / client / ops / guest per OPERATIONS_HANDBOOK §26). Plus a multi-tenant rollup view for the principal that aggregates all sub-agents under their MGA umbrella, leaderboards by production, and alert fan-out.
- **Pricing already specced:** "Crystallux Manager — $497-$2,997 / mo per team" (BUSINESS_PLAN §4 Service 4).

### 2.2 CE (continuing education) tracking for sub-agents
- **Source:** BUSINESS_PLAN §5 ("MGA Requirements & Compliance" — "CE tracking for all sub-agents").
- **What exists:** the term `continuing education (CE)` appears only in the Claude prompt glossary (`niche_overlays.outreach_voice`) — purely as language guidance, no schema.
- **Spec needed:** `sub_agent_ce_log` (agent_id, course_name, hours, completed_at, certificate_url, fsra_category, expires_at) + a renewal alert workflow.

### 2.3 Document management (KYC / E&O / sub-agent contract / carrier contract)
- **Source:** BUSINESS_PLAN §5 (KYC, AML, complaint handling, privacy program; written compliance program; sub-agent contracts; E&O insurance min $2M aggregate; CE tracking) + [`docs/mga/README.md`](../mga/README.md) ("This directory will house: sub-agent contracts (templates), compliance checklists, carrier contact records, recruitment playbooks, onboarding runbooks, production tracking reports").
- **What exists:** zero. Currently expected to be folder-on-disk artefacts, gitignored under `docs/private/`.
- **Spec needed:** `compliance_documents` table (entity_type ∈ sub_agent / carrier / client / e_and_o, doc_kind, file_url, uploaded_by, expires_at, last_reviewed_at) + Cloudflare R2 storage backend + signed-URL viewer panel.

### 2.4 Renewal retention system / policy-renewal tracker
- **Source:** [`2026-04-18-niche-overlays.sql`](../architecture/migrations/2026-04-18-niche-overlays.sql) (`pain_signals` includes "no renewal retention system visible") + insurance-brokers landing page promises "60-90 day pre-renewal window".
- **What exists today:** no `policies` or `policy_renewals` table; renewal-window framing is purely in outreach copy + ICP keywords.
- **Spec needed:** `policies` (lead_id, carrier, policy_type ∈ life/disability/critical_illness/group/p_and_c, premium_annual, in_force_at, renewal_at, beneficiaries jsonb, commission_amount) + renewal-window scanner workflow (60-day + 30-day + 7-day reminders) + cross-sell trigger (e.g., life policyholder with no critical illness coverage).
- **Adjacent:** lead recycling (Bucket 2 §2.6).

### 2.5 Cross-sell strategy detection
- **Source:** [`2026-04-18-niche-overlays.sql`](../architecture/migrations/2026-04-18-niche-overlays.sql) (`pain_signals` includes "no visible cross-sell strategy") + niche-overlay outreach voice ("cross-sell opportunities") + ROADMAP §line 436 ("cross-sell to clients with both travel insurance and mortgage broker lines").
- **What exists:** market-intelligence roadmap mentions it; no implementation.
- **Spec needed:** logic that, given a closed policy, surfaces the next-best policy product for the same client (life → disability → critical illness → group benefits ladder). Depends on Bucket 2 §2.4 (`policies` table) existing first.

### 2.6 Lead recycling / re-engagement
- **Source:** OPERATIONS_HANDBOOK §29.x + the post-call sequence template `not_now` (30-day re-engagement). [`2026-04-24-closing-intelligence-client-facing.sql`](../architecture/migrations/2026-04-24-closing-intelligence-client-facing.sql) line 510 references "14-day re-engagement" target.
- **What exists today:** `clx-pipeline-update-v2` flags stale leads (2h / 24h / 30d thresholds) into a `pipeline_stats.stale_leads` log, but no automated recycling trigger.
- **Spec needed:** workflow that takes a `Closed Lost` / `Not Interested` / cold-`Contacted` lead after N days and re-enrols it into outreach with a fresh template (typically the `not_now` follow-up sequence already in `post_call_sequences`).

### 2.7 Carrier comparison tool / carrier strategy
- **Source:** [`2026-04-18-niche-overlays.sql`](../architecture/migrations/2026-04-18-niche-overlays.sql) (`pain_signals` includes "generic carrier logos without strategic positioning") + glossary mentions "carrier" as a key term.
- **What exists:** zero. Carriers appear only as text in objection-handler copy ("captive agent unable to use outside lead sources").
- **Spec needed:** `carriers` table (name, product_lines, fsra_category, contract_type ∈ direct / through_mga, last_pricing_update, override_rate) + a carrier-comparison side-panel that, given a prospect's needs analysis, surfaces best carriers. **Heaviest spec gap of all the insurance features.**

### 2.8 Group selling / group benefits quote
- **Source:** [`2026-04-18-niche-overlays.sql`](../architecture/migrations/2026-04-18-niche-overlays.sql) (`typical_products` lists "group benefits") + objection-handlers reference "$5K-$15K commission per closed policy" range that suggests group-quote scope.
- **What exists:** zero feature; only ICP keyword.
- **Spec needed:** a "group quote" intake form (employer + employee count + plan tier + carriers shortlist + lead_id link) + a comparison output PDF generator + handoff to outreach. Substantially scoped.

### 2.9 Recordkeeping / audit log for FSRA + complaint handling
- **Source:** BUSINESS_PLAN §5 (MGA must maintain "Record keeping compliant with FSRA requirements" + "complaint handling") + OPERATIONS_HANDBOOK general security posture.
- **What exists:** `admin_action_log` (Phase B.10 admin copilot audit) + `auth_sessions` + `scan_log` + `script_usage_log`. None of these is purpose-built for FSRA recordkeeping (advisor-policy-client interaction logs).
- **Spec needed:** `advisor_action_log` schema mirroring `admin_action_log` but for advisor-side actions (note added, policy event recorded, complaint logged, etc.) + retention policy aligned with FSRA (typically 7 years).

### 2.10 Crystallux Coach (Service 3)
- **Source:** BUSINESS_PLAN §4 Service 3 (Self-Directed $197 / Guided $497 / Executive $997).
- **What exists:** pricing structure is in BUSINESS_PLAN; no schema, workflow, or panel.
- **Spec needed:** a goal-setting + weekly-check-in panel + library of industry playbooks (the closing-intelligence library is closest existing analogue but oriented for live calls, not self-directed coaching).

### 2.11 Lead recycling workflow → Coach handoff
- **Source:** OPERATIONS_HANDBOOK §28 / `objection_handlers` row line 193 ("No book of business at all (send to Coach program instead)").
- **What exists:** the cross-sell handoff is *referenced* in the objection handler text. No mechanical handoff.
- **Spec needed:** when an advisor's pipeline shows fewer than N closes / month, the system auto-prompts a Coach upsell. Requires Crystallux Coach (§2.10) to exist first.

### 2.12 AI Manager briefings + leaderboards
- **Source:** BUSINESS_PLAN §4 Service 4 (Crystallux Manager) — "Daily briefings on team productivity, leaderboards, alerts on at-risk team members, accountability tracking, performance reviews".
- **Built today (close to it):** `clx-daily-summary-generator-v1` (§32) emits per-agent emails — an *adjacent* workflow.
- **Missing:** a single morning email to the principal aggregating all agents (rollup, ranked leaderboard, at-risk callouts, anomaly summary). Plus the dashboard rollup panel referenced in §2.1.

### 2.13 Behavioral Intelligence (Phase B.13)
- **Source:** [OPERATIONS_HANDBOOK §35](../architecture/OPERATIONS_HANDBOOK.md) (full spec, 16 subsections).
- **Status:** designed, schema + 5 workflows + dashboard panels not yet built. Pre-req for the vertical-specific signal category (#7) is Bucket 2 §2.4 (`policies` table) for insurance; equivalent vertical pre-reqs apply for other verticals (MLS-comp for real estate, recall calendar for dental, etc.). The behavioral feature can ship without any vertical-specific pre-req — the other 9 categories work universally.
- **Universal framing:** Behavioral Intelligence is a **universal feature**, not insurance-specific. It deploys across every Crystallux vertical (real estate, mortgage, dental, consulting, construction, agencies, financial advisors, more). This file documents it under "insurance-features-extracted" because Mary is scoping the *insurance* slice of the Advisor Dashboard right now, but the same engine and the same 10 categories serve every vertical — what changes per vertical is the seed archetype library.
- **What it is:** a continuous-monitoring layer that watches per-lead life + business + industry + sports + news + social + vertical-specific + financial + geographic + calendar signals, scores each for relevance + sensitivity, compounds them into trigger archetypes, and either auto-sends or surfaces a personalised outreach. Person-level companion to §27 Market Intelligence (which is vertical-level).
- **Insurance-specific signal types (subset of the 10 categories):**
  - `insurance.policy_renewal_60d` / `_30d` / `_7d` — pre-renewal windows
  - `insurance.policy_lapsed`
  - `insurance.beneficiary_change_request`
  - `insurance.claim_filed`
  - `insurance.coverage_gap_detected_from_life_event` — e.g., new baby + no life policy on file
- **Insurance-specific trigger archetypes (seed for `niche_overlays.insurance_broker`):**
  - `birthday_with_pending_renewal` — birthday + 60d-renewal → low-sensitivity congrats + renewal walkthrough ask
  - `expansion_signals_group_benefits` — headcount+10 + new office → group benefits intro
  - `new_parent_term_life` — new baby (HIGH sensitivity, mandatory advisor review) → term life copy at 90-day cooldown
  - `bereavement_pause` — high-sensitivity, NO outreach for 90 days, archive other triggers (compliance + decency)
  - `business_anniversary_renewal_walkthrough` — corp anniversary + renewal window
  - `industry_regulatory_change_review` — FSRA ruling affecting prospect's vertical → pro-active reach
- **Pricing:** **$1,500-$3,500/mo per client** as Tier D add-on (after Tier C Listening Intelligence). Bundled into Crystallux Operator Enterprise + every Crystallux MGA sub-agent contract.
- **Schema sketch:** `behavioral_signals` (per-lead per-event feed), `client_behavioral_prefs` (opt-in matrix), `behavioral_triggers` (compound archetype library, FK to `closing_scripts`). Plus 4 SECURITY DEFINER RPCs.
- **Workflows (5, all dormant per pattern):** `clx-behavioral-scanner-v1` (6h schedule, multi-source ingestion), `clx-behavioral-classifier-v1` (Claude Haiku score relevance + sensitivity), `clx-behavioral-trigger-v1` (compound match + outreach compose), `clx-behavioral-learning-loop-v1` (02:00 schedule, recompute conversion_rate), `clx-behavioral-consent-collector-v1` (lead-supplied intake).
- **Compliance load-bearing items (don't ship without these):**
  - `sensitivity_ceiling` per client (low / medium / high) caps auto-send
  - High-sensitivity signals (bereavement, illness, divorce, job loss, new baby) NEVER auto-send — mandatory advisor review with a "Sensitive trigger" banner
  - `BEHAVIORAL_HIGH_SENSITIVITY_AUTO_SEND_BLOCKED` monitoring threshold at critical severity (defence-in-depth against schema drift)
  - PIPEDA per-signal source attribution displayed to the lead on request
  - 18-month active retention then archived; full export available via `support@crystallux.org`
- **Why this is the headline differentiator:** see [PRODUCT_VISION.md](../architecture/PRODUCT_VISION.md). Apollo + ChatGPT can write a personalised email; only Crystallux can tell you *when* to send it.
- **Activation roadmap (sequenced, each gate independently shippable):**
  1. Pre-req: Bucket 2 §2.4 (`policies` table) for the insurance signal category.
  2. MVP: 4 of 10 categories (personal birthday, business hires, insurance renewal, internal calendar) on Tier 1 sources only.
  3. Tier 2 sources (Google News + Crunchbase) → news + social categories.
  4. Sensitive personal category (new baby, marriage, bereavement) with high-sensitivity gating fully tested.
  5. Full 10 categories; seed insurance-broker archetype library (10-15 archetypes).
  6. Activate the conversion-rate learning loop once each archetype has ≥ 50 acted-on rows.
- **Cost ceiling at scale:** ~$515/mo platform cost to deliver $30K-$60K MRR at 30 clients. Margin is the headline.

---

## Bucket 3 — Mentioned but not specced (one-line aspirations)

### 3.1 "Renewal notifications" workflow
Niche-overlay outreach voice mentions "renewal notifications" as a key advisor pain point. No technical spec. (Adjacent to Bucket 2 §2.4 but distinct: `2.4` tracks the policy; this is the agent's outbound notification flow to their existing client to retain them.)

### 3.2 "Carrier relationships" tracking
Mentioned in the niche-overlay glossary; not specced. Distinct from carrier comparison (§2.7) — this is *relationship*-level, not product-level.

### 3.3 "MGA overrides" / commission tracking
Niche-overlay copy references "MGA overrides". BUSINESS_PLAN §5 quantifies them ($100-300 per policy). No schema for tracking overrides paid vs. policies written.

### 3.4 "Beneficiaries" tracking
Glossary term. Field-level — would belong on a `policies.beneficiaries` jsonb column once §2.4 is built.

### 3.5 "Client suitability" / "needs analysis"
Glossary terms used in advisor prompts. Could become a structured intake form — no spec.

### 3.6 Sub-agent recruitment funnel
BUSINESS_PLAN §5 lists 4 recruitment targets (struggling licensed advisors, mid-tier advisors at other MGAs, newly licensed, retiring advisors with books to acquire). No tracking schema, no funnel workflow.

### 3.7 "Founding rate locked for 12 months" enforcement
Pricing copy promises 12-month price lock on founding tiers. Stripe Price metadata includes `founding_lock_months: 12` but no enforcement workflow auto-promotes from `founding_1997` → `standard_2497` at month 13.

### 3.8 "Book of business" portability / transfer
BUSINESS_PLAN §5 mentions buying retiring advisors' books. No schema for representing "book ownership" or a transfer event.

### 3.9 E&O insurance management
BUSINESS_PLAN §5 requires E&O policy ($2M+ aggregate). No tracking surface inside the platform — purely an off-platform admin task today.

### 3.10 Referral engine
[`docs/business/service-packages.md`](../business/service-packages.md) Enterprise tier line — ✓ "Referral Engine". Not built; no schema.

### 3.11 Carousel content generation
BUSINESS_PLAN §4 Service 2 (Crystallux Content Professional tier) names "carousel generation" as a deliverable. No workflow.

### 3.12 AI video avatar (advisor-content production, *not* outreach)
Tavus already integrated for *outreach* video (`clx-video-outreach-v1`). Service catalog adds "video scripts" + AI-face-avatar usage for the advisor's own content brand — different distribution. Not built.

---

## Cross-cutting: what the Advisor Dashboard build phase actually needs

A consolidated checklist for scoping. Tags: 🟢 backend done — needs panel, 🟡 panel exists for other role — needs role wiring, 🔴 net-new.

| Item | Status | Where the lift lands |
|------|--------|----------------------|
| Today's Plan (per advisor) | 🟡 | Re-skin `#todaysPlanSection` for advisor role; agent_id-scoped fetch |
| Calendar reshuffle / no-show recovery | 🟡 | `#yourDaySection` for advisor; reshuffle button wired |
| Route optimisation map | 🟢 | New panel `#advisorRouteSection` (or reuse `#routeMapSection`) |
| Productivity self-view | 🟡 | Re-skin `#myProductivitySection` for advisor |
| MGA principal supervisor view | 🔴 | New role + rollup panel above `#teamProductivitySection` |
| Closing-script library | 🟡 | `#closingIntelligenceSection` for advisor; lead-id input |
| Live-call transcript + suggestions | 🟡 | `#liveCallSection` + `#scriptSuggestionCard` for advisor |
| Voice notes (post-meeting recap) | 🟢 | New panel; reuses `clx-copilot-whisper-v1` |
| Insurance label swap | 🟡 | UI plumbing of `niche_overlays.dashboard_labels` |
| **Renewal-window pipeline / policies table** | 🔴 | Bucket 2 §2.4 — biggest schema lift |
| **Carrier comparison tool** | 🔴 | Bucket 2 §2.7 — biggest UX lift |
| **Group quote intake** | 🔴 | Bucket 2 §2.8 |
| **CE tracking** | 🔴 | Bucket 2 §2.2 |
| **Document management** | 🔴 | Bucket 2 §2.3 |
| **Cross-sell engine** | 🔴 | Bucket 2 §2.5 (depends on §2.4) |
| **Lead recycling workflow** | 🔴 | Bucket 2 §2.6 |
| **Smart renewal reminders to existing book** | 🔴 | Bucket 3 §3.1 (depends on §2.4) |
| **Behavioral Intelligence (per-lead signal feed + triggered outreach)** | 🔴 | Bucket 2 §2.13 — full spec in OPERATIONS_HANDBOOK §35 |

The 🟡 items are 80% of the perceived "Advisor Dashboard" surface area and most of the time saved by reusing existing backend. The 🔴 schema items (`policies`, `carriers`, `compliance_documents`, `sub_agent_ce_log`, `advisor_action_log`) are where genuinely new product work lives.

---

## What this document deliberately does NOT contain

- Estimates or sequencing — those are scoping decisions for Mary.
- Recommendations on which features to build next — read the buckets, decide by ROI.
- Prices or commercial framing for the new advisor surface — see BUSINESS_PLAN §4-5 + STRIPE_PRODUCTS_SPEC.md.
- Anything the handbook does not actually say. If a feature you expected is missing here, it's because no source document specifies it; flag it to me and I'll re-grep.
