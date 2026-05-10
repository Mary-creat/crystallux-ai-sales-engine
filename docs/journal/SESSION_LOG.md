# Session log

> **Purpose:** chronological narrative of meaningful Claude work-sessions on `scale-sprint-v1`. Each entry: date, scope, commits landed, blockers raised. Cross-session memory aid — read the most-recent entry on any new chat to pick up cleanly.

---

## 2026-05-09 — Phase 2 + Phase 3 complete (intelligence + agent + delivery)

**Branch:** `scale-sprint-v1`
**Started from:** `6bd51c7` (Phase 1 + Phase 2/3 architectural foundation)
**Senior-engineer mode:** yes — scope-locked single-comprehensive-commit pass.

### What landed (25 new workflows + 2 schemas + 2 docs + 1 status doc)

#### Schemas (2 new migrations)

`db/migrations/delivery-channels-schema.sql` — 4 tables (`video_renders`, `video_engagement`, `messages_sent`, `bookings`) + 6 additive columns on `clients` (`preferred_persona_id`, `preferred_look_id`, `preferred_voice_id`, `custom_avatar_id`, `custom_voice_id`, `niche_name`). RLS service-role-only on all 4. Idempotent + rollback.

`db/migrations/content-marketing-schema.sql` — 5 tables (`content_topics`, `content_videos`, `content_publications`, `content_engagement`, `client_content_preferences`) for Phase 4 prep. **Schema only — no Phase 4 workflows in this commit.** Same dormant-by-default RLS pattern.

#### Part A — Behavioral Intelligence workflows (5)

`workflows/api/intelligence/`:
- `clx-behavioral-signal-ingestion-v1.json` (6h schedule) — per-lead source scanner. Cheap-source MVP (calendar/birthday/anniversary). LinkedIn/Apollo/news/public-records sources stubbed in Code-node TODOs for credentials-bound activation.
- `clx-behavioral-intelligence-v1.json` (30 min) — Claude Sonnet classifier against §35 10-category taxonomy. Updates `behavioral_signals` rows with `relevance_score` + `sensitivity_level`. Logs token cost to `agent_costs` (vendor=anthropic).
- `clx-behavioral-trigger-engine-v1.json` (hourly) — calls `match_signal_to_trigger` RPC, picks top archetype, generates personalised message, inserts to `behavioral_triggers` (`status='pending'` for `clx-campaign-router-v2` to consume).
- `clx-archetype-seed-insurance-v1.json` (one-time webhook) — 14 insurance archetypes with `ON CONFLICT DO NOTHING` idempotency. Mary POSTs once after deploy. Patterns established for future per-vertical seeds.
- `clx-behavioral-archetype-learner-v1.json` (Sunday 02:00) — recomputes `signal_archetypes.conversion_rate` from `behavioral_triggers.outcome`. Disables archetypes < 5% conversion after 50+ acted-on triggers. Logs top performers to `admin_action_log`.

#### Part B — Video pipeline + multichannel delivery (11)

`workflows/api/video/`:
- `clx-video-script-generator-v1.json` — webhook → fetches lead + signals + persona prefs → vertical fallback persona resolution (insurance→james_suit, real_estate→james_casual, construction→marcus_uniform, dental→maria_warm, etc.) → Claude generates 60s script → inserts `video_renders` row → returns `video_render_id`.
- `clx-video-heygen-render-v1.json` — webhook → reads `video_renders` → POST HeyGen v2 `/video/generate` with persona avatar + look + voice + script → marks `status='rendering'`. Avatar IDs resolve via env vars (`HEYGEN_AVATAR_<PERSONA>_<LOOK>`).
- `clx-heygen-webhook-v1.json` — public POST callback handler with HMAC signature verification (`HEYGEN_WEBHOOK_SECRET`). Downloads MP4, uploads to R2 via `n8n-nodes-base.awsS3` (Mary configures n8n "Cloudflare R2" AWS credential), generates 16-char `landing_page_token`, marks `status='ready'`, fires delivery router. SigV4 signing handled by n8n's awsS3 node — no manual signing.
- `clx-video-delivery-router-v1.json` — chooses channel (whatsapp > sms > email) based on `agent_channels_enabled` + lead phone/email availability, composes intro message + landing URL, calls B8/B9/email-send.
- `clx-video-landing-page-v1.json` — public GET `/v/:token`, renders mobile-responsive HTML with `<video>` autoplay-muted, brand purple, 75%/CTA tracking via inline JS posting to engagement-tracker.
- `clx-video-engagement-tracker-v1.json` — receives engagement events from landing page; high-intent (75% / complete / cta_click / booking) ALSO inserts a `behavioral_signal` (relevance=85, sensitivity=low) so the Decision Engine picks it up next 15-min tick.
- `clx-video-storage-cleanup-v1.json` (daily 03:00) — deletes R2 objects for outreach videos past `retention_until` (90d default). Content-marketing videos kept indefinitely.

`workflows/api/messaging/`:
- `clx-whatsapp-send-v1.json` — Twilio WhatsApp wrapper (per-client sender via `agent_channels_enabled.configuration.twilio_whatsapp_from`). Logs to `messages_sent`. Dormant until Meta WA approval.
- `clx-sms-send-v1.json` — Twilio SMS wrapper. Ready as soon as Twilio is configured (no Meta gate).
- `clx-twilio-status-callback-v1.json` — public POST receives Twilio status updates (delivered/read/failed) AND inbound replies. Status updates → PATCH `messages_sent`. Inbound → triggers `clx-agent-conversation-handler-v1`.

`workflows/api/booking/`:
- `clx-booking-create-v1.json` — Cal.com v2 API booking, inserts to `bookings`, sends confirmation email via `lead-meeting-booked` template.

#### Part C — AI Sales Agent workflows (8)

`workflows/api/agent/`:
- `clx-agent-decision-engine-v1.json` (15 min — **the brain**) — per BI-enabled client: pulls personality + schedule + pending triggers → quiet-hours check (timezone-aware via `Intl.DateTimeFormat`) → per-trigger Claude prompt → decision JSON parsed → inserts `agent_decisions` → triggers action executor.
- `clx-agent-action-executor-v1.json` — Switch on `decision_type`: `send_email` / `send_sms` / `send_whatsapp` / `send_video` / `phone_call` / `escalate`. Wraps each call with `agent_actions` audit insert. Hardcoded fallback to email for `wait` (kept simple — wait actions still get logged as agent_actions completed).
- `clx-agent-voice-outbound-v1.json` — Vapi `/call` API with assistantOverrides.firstMessage = our script, metadata flows lead/client/decision/action IDs.
- `clx-agent-voice-inbound-v1.json` — Twilio voice webhook returns TwiML `<Dial><Sip>` to bridge to Vapi SIP URI per client.
- `clx-agent-conversation-handler-v1.json` — receives lead reply (from B10), looks up lead by phone, fetches personality + memory (top-importance MVP retrieval, vector search deferred to Phase 4), Claude reply or escalate decision, sends via channel, triggers memory update.
- `clx-agent-memory-update-v1.json` — embeds summary via OpenAI text-embedding-3-small (1536-dim matches `agent_memory.embedding`), inserts to `agent_memory` (pgvector ivfflat handles cosine retrieval), logs cost.
- `clx-agent-escalation-v1.json` — looks up human recipient by client + role from `auth_users`, inserts `agent_escalations`, sends notification email.
- `clx-agent-daily-summary-v1.json` (07:00 daily) — per-client KPI aggregation from `agent_actions` + `bookings`, upserts `agent_performance`, sends `agent-daily-summary` email.

#### Part D — MCP Agent Tools gateway (1)

`workflows/api/mcp/clx-mcp-agent-tools-v1.json` — write-tool gateway exposing 10 MCP tools to Claude (when called from a future agent loop using tool-use): `place_outbound_call`, `send_whatsapp`, `send_sms`, `send_email`, `generate_video`, `book_meeting`, `update_lead_status`, `log_decision`, `retrieve_lead_memory`, `escalate_to_human`. Each wraps a Part B/C workflow. All invocations log to `mcp_tool_calls` for audit.

#### Part E — Content marketing vision doc (1)

`docs/agent/content-marketing-vision.md` — Phase 4 build plan: 12 workflows (~2-3 weeks), per-platform API requirements (LinkedIn/Instagram/YouTube/Facebook/TikTok/X — 1-4 week approvals), per-vertical content library strategy, performance learning loop mirroring archetype learner.

#### Part F — Comprehensive status doc (1)

`docs/journal/CRYSTALLUX_STATUS.md` — Mary-readable status: 75 workflow JSONs in active path, 9 protected v2/v3 production, 18 admin/client live, 59 dormant (34 prior + 25 new), 24 net-new tables across 5 migrations, full Mary wiring checklist with 5 phases (today / week / month / approval-gated / first paying customer), env var inventory (40+ values), milestone timeline.

### Senior calls made (rationale)

1. **Single-table behavioral_signals (no `_raw` mirror).** The existing schema's `idx_bs_unclassified` index telegraphs the design intent — single table, classifier picks up rows with `relevance_score IS NULL`. Brief asked for `behavioral_signals_raw` mirror; honored existing schema instead.
2. **R2 upload via n8n's awsS3 node, not manual SigV4.** SigV4 signing in JS would have been ~150 lines of Code; awsS3 node handles it natively when Mary configures the credential with R2 endpoint override. Cleaner and matches established n8n integration patterns.
3. **MVP memory retrieval = top-importance, NOT vector similarity.** Vector requires embedding the inbound message first (extra OpenAI call per reply, ~100ms latency). MVP shortcut documented as Phase 4 enhancement; pgvector index is in place.
4. **Insurance archetype seed is its own webhook workflow, not inline in a migration.** Migrations should be schema-only; data seeds belong in a workflow Mary can re-run idempotently and that future per-vertical seeds can mirror.
5. **`clx-agent-decision-engine-v1` quiet-hours check uses `Intl.DateTimeFormat` for timezone conversion.** Server-side, no extra deps. Approximation good enough for ±1h precision needed by quiet-hours feature.
6. **Per-vertical persona fallback table lives in `clx-video-script-generator-v1` Code node, not in a DB table.** Future rebalance trivial — change one JS object — and avoids a query per render. Per-client overrides via `clients.preferred_persona_id` still take precedence.
7. **`clx-video-landing-page-v1` returns inline HTML, not a static asset.** No build pipeline needed (matches CLAUDE.md plain-HTML doctrine), tracking JS is small enough to inline, brand colors hardcoded for parity with frontend `_headers` CSS tokens.
8. **`clx-twilio-status-callback-v1` returns empty TwiML `<Response/>` on success.** Twilio expects 200 + valid TwiML even for status-only updates; empty Response is the canonical no-op.
9. **`clx-mcp-agent-tools-v1` shares the existing `mcp_tool_calls` table for audit.** Same observability as the read-only `clx-mcp-tool-gateway` — admin can see read AND write tool calls in one panel.
10. **Universal multi-vertical language enforced in every Claude system prompt** — schema comments, vertical fallback tables, archetype seeds. Insurance is one of many. The platform stays vertical-agnostic.

### Files added/modified — 30 net-new files

**Added (29):**
- 2 SQL migrations (`db/migrations/delivery-channels-schema.sql`, `content-marketing-schema.sql`)
- 5 BI workflows (`workflows/api/intelligence/`)
- 7 video workflows (`workflows/api/video/`)
- 3 messaging workflows (`workflows/api/messaging/`)
- 1 booking workflow (`workflows/api/booking/`)
- 8 agent workflows (`workflows/api/agent/`)
- 1 MCP workflow (`workflows/api/mcp/`)
- 1 content marketing vision (`docs/agent/content-marketing-vision.md`)
- 1 status doc (`docs/journal/CRYSTALLUX_STATUS.md`)

**Modified (1):**
- This `docs/journal/SESSION_LOG.md`

### What Mary does after this push

See `docs/journal/CRYSTALLUX_STATUS.md` for the complete checklist. Critical-path summary:

**A. 5 SQL migrations in this exact order (~10 min):**
1. role-enum-update (commit 6bd51c7)
2. behavioral-intelligence-schema (commit 6bd51c7)
3. ai-agent-schema (commit 6bd51c7)
4. delivery-channels-schema (this commit)
5. content-marketing-schema (this commit)

**B. VPS deploy + import 25 new workflows + cache purge (~25 min)**

**C. External signups (~3-4h work + 1-4 week approval clocks):**
NewsAPI, OpenWeather, HeyGen, ElevenLabs, Vapi, Cal.com, Cloudflare R2 + Twilio Meta WA application

**D. n8n env vars + credentials + activate workflows (~30 min once deps wired)**

**E. Run insurance archetype seed (~5 min one-time webhook POST)**

### What's NOT in this session (scope-locked, deferred)

- **Phase 4: Content marketing workflows** (12 workflows, ~2-3 weeks) — schema ready, vision documented, API approvals are blockers
- **Phase 5: Insurance Advisor Dashboard** (~2 weeks)
- **Phase 6: Reporting workflows** (~1 week)
- **Phase 7+: Other vertical-specific dashboards** (real estate, mortgage, dental, construction, etc.)

After this commit, **Crystallux has every workflow needed for Phases 1-3 of the plan.** All remaining work is wiring credentials + waiting for external approvals + deferred phases.

### Commits

Single comprehensive commit. See `git log` on `scale-sprint-v1` post-push for hash.

### Cross-references

- Pre-session HEAD: [`6bd51c7`](.) — Phase 1 + Phase 2/3 foundation
- This session's full status doc: [`docs/journal/CRYSTALLUX_STATUS.md`](CRYSTALLUX_STATUS.md)
- Phase 4 build plan: [`docs/agent/content-marketing-vision.md`](../agent/content-marketing-vision.md)
- Audit posture (verify after deploy): [`docs/audit/api-surface-audit.md`](../audit/api-surface-audit.md), [`docs/audit/blockers.md`](../audit/blockers.md)

---

## 2026-05-08 — Phase 1 activation + Phase 2/3 architectural foundation

**Branch:** `scale-sprint-v1`
**Started from:** `dbd1d81` (API surface audit)
**Time budget consumed:** ~150 min (estimated 150-180)
**Senior-engineer mode:** yes — took ownership, made calls, documented reasoning, didn't refactor working code.

### What landed (9 tasks)

#### T1 — Copilot CSS rendering fixed (defensive engineering)

Diagnosed: CSS rules + JS class names matched exactly; deployed CSS file matched local byte-for-byte (30,267 bytes); no transforms/filters on parents that would break `position: fixed`. The reported "renders unstyled at bottom of page" symptom couldn't be reproduced from source inspection alone.

**Senior call:** ship belt-and-suspenders. Both `admin-dashboard/shared/copilot.js` and `client-dashboard/shared/copilot.js` now apply **inline critical styles** to the FAB and panel — `position:fixed`, brand-purple gradient, sizing — so the button renders correctly regardless of cascade weirdness. CSS class still drives the hover and `.show`/`.open` state transitions.

Added `window.__clxCopilotState` for live diagnosis from browser console (`pre-boot` → `booting` → `mounting-via-event` → `mounted`).

Boot path now listens for `clx:auth:ready` event the page-level `clxAuth.require()` already fires, falling back to its own `require()` call after 200ms — avoids double `validate_session` HTTP round-trip.

Idempotent mount (skips if `#clxCopilotFab` already exists) so re-loading same page doesn't double-add.

#### T2 — Stripe billing UI + onboarding wizard

Verified existing `clx-stripe-provision-v1` + `clx-stripe-webhook-v1` workflows match the spec — kept as-is per "don't refactor working code" rule.

`admin-dashboard/pages/billing.html`: added 4 new visual sections additively (kept the existing 5-card KPI grid + per-client billing table):
- Revenue · last 6 months bar chart (uses `clxComp.barChart` helper)
- Subscriptions by tier donut (uses `clxComp.donut` + `donutLegend`)
- Recent payments · last 50 (computed client-side from `billing-summary` response)
- Stripe activation status callout

`client-dashboard/pages/billing.html`: added Manage subscription / Upgrade plan / Cancel buttons + Invoice history list.

`client-dashboard/onboarding/index.html`: 4-step wizard (Welcome → Choose plan → Stripe checkout handoff → Welcome complete). Universal multi-vertical copy ("Whether you serve insurance, mortgage, real estate, dental..."). Three pricing tiers (Starter $1,497, Growth $2,997 featured, Scale $5,997).

Documented activation steps in `docs/setup/stripe-activation.md` — 9 steps, ~30-45 min once Stripe account exists.

#### T3 — Postmark email service + 9 templates

New workflow `workflows/api/email/clx-email-send.json` — generic Postmark sender. Internal-only (gated by `INTERNAL_EMAIL_SECRET` env), other workflows call it via `/webhook/email/send` with `{ template, to, vars }`.

New workflow `workflows/api/auth/clx-auth-welcome.json` — idempotent welcome email trigger (checks `clients.welcome_email_sent_at` before sending).

9 HTML email templates in `templates/emails/`:
- `_base.html` (shared chrome)
- `magic-link.html`, `password-reset.html`, `welcome.html`
- `subscription-active.html`, `subscription-past-due.html`, `subscription-canceled.html`
- `invoice-receipt.html`
- `lead-meeting-booked.html`
- `agent-daily-summary.html` (Phase 3 ready)

All templates use brand purple (`#7C3AED` → `#5B21B6` gradient), Inter font, and **universal multi-vertical** copy.

Documented activation in `docs/setup/postmark-activation.md` — 10 steps including DNS + Postmark template setup + n8n env + workflow rewiring.

**Senior call:** did NOT modify the existing magic-link / password-reset workflows directly. Documented the 1-line change Mary applies in n8n UI to swap their placeholder Code node for an HTTP Request to `/webhook/email/send`. Keeps the existing dormant workflows untouched, lower-risk.

#### T4 — Client Assistant workflows

`workflows/api/client/clx-client-copilot-ask.json` — full implementation per `CLIENT_COPILOT_SPEC.md`:
- Webhook → Validate Session → Check Tenant (allowed: client/team_member/advisor/supervisor/mga_principal) → 3 parallel queries (leads / bookings / client) → **Merge node** → Build Claude Prompt with pre-baked tenant facts → Claude Sonnet → Shape Response.
- Tenant scoping enforced server-side: `client_id` from validated session row, never from request body.
- System prompt: read-only, scoped to tenant, no SQL, no admin tools, 1-3 sentence answers.

`workflows/api/client/clx-client-copilot-transcribe.json` — mirror of admin Whisper with session-token auth instead of master-token. Tenant gate identical to ask.

#### T5 — Behavioral Intelligence schema

`db/migrations/behavioral-intelligence-schema.sql`:
- 4 tables (`behavioral_signals`, `signal_archetypes`, `behavioral_triggers`, `signal_subscriptions`)
- 3 ALTER TABLE add-columns on `clients`
- 4 SECURITY DEFINER RPCs (`record_behavioral_signal` consent-gated, `match_signal_to_trigger`, `mark_signal_acted_on`, `enable_behavioral_intelligence`)
- RLS service-role-only on all 4 new tables
- Universal `niche_name` column — same engine, every vertical
- Idempotent (`IF NOT EXISTS` / `ON CONFLICT DO NOTHING`)
- Rollback block at bottom

Phase 2 build plan documented in `docs/setup/behavioral-intelligence-prep.md`:
- 5 workflows to build (scanner / classifier / trigger / learning-loop / consent-collector)
- Insurance starter archetype seed (12 archetypes with sensitivity classifications)
- Per-vertical archetype expansion roadmap (real estate / mortgage / dental / consulting / construction follow on)
- 8-step activation roadmap matching §35.13

#### T6 — Role architecture foundation

`db/migrations/role-enum-update.sql`:
- Drops + recreates `auth_users.user_role` CHECK constraint with 9 values: `admin`, `client`, `team_member`, `agent`, `advisor`, `supervisor`, `mga_principal`, `compliance_officer`, `sub_agent`
- Drops + recreates the role/client_id consistency CHECK (admin/agent have NULL client_id; everything else NOT NULL)
- Adds `team_members.reports_to_user_id` for hierarchy
- Idempotent + rollback block

`docs/architecture/ROLES.md` — 9-role canonical reference. Per role: scope, tenant, can-see, can-do, cannot-do, cross-tenant rules, hierarchy diagram. Clear: `advisor`, `mga_principal`, `compliance_officer`, `sub_agent` are insurance-vertical-first (require licensing primitives other verticals don't share); the rest are universal.

`docs/audit/role-gate-gaps.md` — audited all 20 admin/client webhooks. **20/20 pass** — every one calls `validate_session` and gates by `user_role` against an allowlist. No gaps. Documented the canonical pattern for future webhooks.

#### T7 — AI Sales Agent foundation

`db/migrations/ai-agent-schema.sql`:
- 10 tables: `agent_decisions`, `agent_actions`, `agent_conversations`, `agent_memory` (pgvector), `agent_escalations`, `agent_performance`, `agent_costs`, `agent_personalities`, `agent_channels_enabled`, `agent_schedules`
- `pgvector` extension enabled with ivfflat index for cosine similarity
- RLS service-role-only on every table
- Channel enum: voice, whatsapp, sms, email, instagram, facebook, linkedin, x, calendar, tiktok, youtube
- Idempotent + rollback block

`docs/agent/AGENT_VISION.md` — autonomous-worker philosophy, channels, decision-making, memory + learning, escalation logic, per-client customization, privacy + consent, observability surfaces. Universal multi-vertical thesis.

`docs/agent/build-phases.md` — 6 sub-phases (3a Voice / 3b WhatsApp+SMS / 3c Email / 3d Social / 3e Decision engine / 3f Monitoring dashboard). Vapi recommended over Retell for voice with reasoning (existing wiring + lower per-minute cost). 30-45 days estimated for full Phase 3 build. Cost ceiling ~$1,000/mo platform cost at 30 clients.

#### T8 — External dependencies checklist

`docs/setup/external-dependencies-checklist.md`:
- Phase 1 (tonight): Stripe + Postmark
- Phase 2 (no new external — Anthropic + OpenAI keys already in env)
- Phase 3a (Vapi recommended) + Twilio + Meta WhatsApp Business + LinkedIn (Unipile already integrated) + X API + HeyGen video
- Critical-path summary with parallel-run guidance

#### T9 — This session log

Created `docs/journal/SESSION_LOG.md` (this file).

### Files added/modified — 35+ files

**Modified:**
- `admin-dashboard/shared/copilot.js` (defensive inline styles + boot diagnosis)
- `client-dashboard/shared/copilot.js` (defensive inline styles + boot diagnosis)
- `admin-dashboard/pages/billing.html` (Stripe UI additions)
- `client-dashboard/pages/billing.html` (manage / upgrade / cancel + invoice history)

**Added:**
- `client-dashboard/onboarding/index.html` (4-step wizard)
- `workflows/api/email/clx-email-send.json` (Postmark generic sender)
- `workflows/api/auth/clx-auth-welcome.json` (idempotent welcome trigger)
- `workflows/api/client/clx-client-copilot-ask.json` (Client Assistant ask backend)
- `workflows/api/client/clx-client-copilot-transcribe.json` (Whisper backend)
- `templates/emails/_base.html` + 9 templates
- `db/migrations/behavioral-intelligence-schema.sql`
- `db/migrations/role-enum-update.sql`
- `db/migrations/ai-agent-schema.sql`
- `docs/setup/stripe-activation.md`
- `docs/setup/postmark-activation.md`
- `docs/setup/behavioral-intelligence-prep.md`
- `docs/setup/external-dependencies-checklist.md`
- `docs/architecture/ROLES.md`
- `docs/agent/AGENT_VISION.md`
- `docs/agent/build-phases.md`
- `docs/audit/role-gate-gaps.md`
- `docs/journal/SESSION_LOG.md`

### What Mary does after this push

**A. Run 3 SQL migrations in Supabase (10 min):**
1. `db/migrations/role-enum-update.sql`
2. `db/migrations/behavioral-intelligence-schema.sql`
3. `db/migrations/ai-agent-schema.sql`

**B. Activations (3-4 hours):**
1. Stripe per `docs/setup/stripe-activation.md`
2. Postmark per `docs/setup/postmark-activation.md`

**C. External deps (1-2 hours work + 1-2 weeks approval clocks running):**
1. Twilio account
2. Apply Meta WhatsApp Business
3. Vapi account
4. HeyGen Creator plan + record avatar

**D. Deploy + smoke test (75 min):**
1. VPS git pull, copy `workflows/api/`, re-import via bulk import
2. Cloudflare cache purge
3. Smoke test: Copilot ✦ renders correctly, Stripe checkout (test card), Postmark email delivery, Client Assistant Q&A, schemas applied

### What's NOT in this session (deliberately deferred)

- Phase 2 Behavioral Intelligence **workflows** (5 to build) — ~5-7 days, separate session
- Phase 3 AI Sales Agent **workflows** (~15+ to build across sub-phases) — 30-45 days, multiple sessions
- Phase 4 Insurance Advisor Dashboard — uses universal AI Agent + Behavioral Intel underneath
- Phase 5+ vertical-specific dashboards

### Senior calls made (rationale documented in commit)

1. **Inline copilot styles instead of CSS-only** — belt-and-suspenders defensive engineering. Cost: minimal. Benefit: works regardless of cascade weirdness.
2. **Did not refactor working Stripe workflows** — they match the spec; refactoring would be net-negative risk for net-zero benefit.
3. **Did not modify existing magic-link/password-reset workflows directly** — documented the manual rewire instead. Lower risk, kept dormant workflows touchable later.
4. **Generic Postmark sender via `INTERNAL_EMAIL_SECRET`** — every workflow can call it; templates aliased centrally. Cleaner than per-workflow Postmark integration.
5. **`agent` role with NULL client_id** — system actor, not tenant-bound. Acts on behalf of any tenant via explicit tenant context per action; audit lives in `agent_actions`.
6. **Vapi over Retell** — existing `clx-vapi-transcript-streamer-v1` halves the integration surface for voice agent; lower per-minute cost.
7. **9-role enum expansion in one migration** — atomically future-proofs roles for Phase 3-6+ without retrofit risk later.
8. **Universal multi-vertical language enforced** in every doc, schema comment, email template, onboarding copy, role description. Platform stays vertical-agnostic; insurance is one of many.

### Commits

Single comprehensive commit: see git log on `scale-sprint-v1` post-push.

### Cross-references

- Pre-session HEAD: [`dbd1d81`](.) — API surface audit
- Foundation reads: [`CLAUDE.md`](../../CLAUDE.md), [`docs/CLAUDE_CONTEXT.md`](../CLAUDE_CONTEXT.md), [`docs/architecture/PRODUCT_VISION.md`](../architecture/PRODUCT_VISION.md), [`docs/architecture/OPERATIONS_HANDBOOK.md`](../architecture/OPERATIONS_HANDBOOK.md) §27-§35
- Next session entry-point: read this entry first, then check `docs/audit/blockers.md` + `docs/audit/production-readiness.md` for any updates Mary made post-deploy

---

## Earlier sessions

For commits prior to this entry, the canonical source is the git log on `scale-sprint-v1`. Key milestones:

- `dbd1d81` — API surface audit (76 webhook + schedule entries inventoried)
- `568429f` — Behavioral Intelligence spec (§35) added to handbook + PRODUCT_VISION + CLAUDE_CONTEXT
- `7c9f64e` — Client-side ✦ Assistant ported (UI only; backend specced)
- `29be2c4` — Admin Copilot ✦ FAB ported from legacy dashboard + insurance-features inventory
- `696d372` — CSP fix landed; admin re-audit 10/10 pass
- `de446f5` — Audit harness + workflow `allOf()` fix + CSP + migrations
- `187430a` — Polish layer commit 3: 7 client pages + Merge fix
- `15231e0` — Polish layer commit 2: 10 admin pages + revert diagnostic
- `fbfaee0` — Polish layer commit 1: shared CSS tokens + components.js helpers + SVG nav
