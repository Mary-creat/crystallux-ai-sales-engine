# Session log

> **Purpose:** chronological narrative of meaningful Claude work-sessions on `scale-sprint-v1`. Each entry: date, scope, commits landed, blockers raised. Cross-session memory aid — read the most-recent entry on any new chat to pick up cleanly.

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
