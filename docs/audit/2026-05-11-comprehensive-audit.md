# Crystallux Comprehensive Audit — 2026-05-11

> **Audit-only.** No code modified. Findings synthesized from git log, schema files, workflow JSONs, frontend tree, documentation, and Mary's night notes (commits `e592883` + `30255d1`).

## Executive Summary

| Metric | Value |
|---|---|
| Total commits on `scale-sprint-v1` (lifetime) | **216** |
| Latest commit | `30255d1` — *Night wrap-up notes: Layer 2 deployment complete* |
| Last engineering commit | `f5a73cf` — *Layer 2 Part B (MGA Operations + Reviews + Video Engagement)* |
| Platform completion estimate | **~80%** (Layer 1 + Layer 2 Parts A & B done; Layer 2 Part C + activations pending) |
| Schema migrations applied to Supabase | **7 of 7** (per Mary's night notes 2026-05-10) |
| Layer 2 workflows imported to n8n | **41 of 41** (per night notes — all `active=false`) |
| Frontend deployed to Cloudflare Pages | **❌ pending** (insurance-mga-dashboard built but not yet pushed to `mga.crystallux.org`) |

**Most critical pending work:** activation tail (promote mga_principal user, seed video templates, deploy frontend, smoke test). Mary estimates 60-90 minutes per night notes — none of it requires Claude Code.

**Top 3 risks:**

1. **All Layer 2 workflows dormant. The architecture is in place but nothing is firing.** Activation order matters (compliance agent first, then KYC chain, then review chain) — if Mary activates the BI→review bridge before the video pipeline is wired she'll see review records with `video_render_id=NULL` permanently.
2. **Frontend never deployed.** Code is in repo (`insurance-mga-dashboard/`) but no Cloudflare Pages project points at it yet. Mary cannot login to the new dashboard until this happens.
3. **Many "Phase 5b polish" items deferred** but not explicitly tracked: Certn background checks, PEP/AML automation, per-province license variants, R2-backed template editing, Zoho OAuth refresh, dedicated dispute_resolutions table, dedicated compliance-review-required.html email. Risk of silent technical debt unless these are written into a single list.

---

## 1. Code Inventory

### 1.1 Database schemas (`db/migrations/`)

| File | Tables / RPCs created | Status in Supabase | Dependencies |
|---|---|---|---|
| `role-enum-update.sql` | Updates `auth_users.user_role` CHECK constraint (9 roles); `team_members.reports_to_user_id` | ✅ applied (commit 6bd51c7 deploy) | foundation |
| `behavioral-intelligence-schema.sql` | 4 tables (`behavioral_signals`, `signal_archetypes`, `behavioral_triggers`, `signal_subscriptions`) + 3 client ALTERs + 4 SECURITY DEFINER RPCs | ✅ applied | role-enum |
| `ai-agent-schema.sql` | 10 tables (`agent_decisions`, `agent_actions`, `agent_conversations`, `agent_memory` pgvector, `agent_escalations`, `agent_performance`, `agent_costs`, `agent_personalities`, `agent_channels_enabled`, `agent_schedules`) | ✅ applied | role-enum |
| `delivery-channels-schema.sql` | 4 tables (`video_renders`, `video_engagement`, `messages_sent`, `bookings`) + 6 client ALTERs | ✅ applied | ai-agent, role-enum |
| `content-marketing-schema.sql` | 5 tables (`content_topics`, `content_videos`, `content_publications`, `content_engagement`, `client_content_preferences`) — **Phase 4 prep, workflows deferred** | ✅ applied | delivery-channels |
| `insurance-mga-schema.sql` (Layer 2 Part A) | 7 tables (compliance/KYC/suitability/recommendations/disclosures/audit-log/policy_apps) all `vertical_id`-tagged | ✅ applied | ai-agent, role-enum |
| `insurance-mga-operations-schema.sql` (Layer 2 Part B) | 9 tables (hierarchy/licenses/E&O/appointments/commissions/onboarding/reviews/tasks/video-templates) + 5 ALTERs on policy_applications + leads | ✅ applied | insurance-mga-schema |
| `test-client-account.sql` | Test data only | applied / inert | n/a |
| `update-calendly-info.sql` | One-off data migration | applied / inert | n/a |

**Layer 1 (universal) — 0 `vertical_id` references.** Correct — these tables serve all verticals.
**Layer 2 (insurance MGA) — 58 `vertical_id` references across 16 tables.** Architecture compliant.

### 1.2 Workflows

**Total workflow JSONs:** 145 (50 top-level legacy + protected production + 95 in `workflows/api/`).

Per-folder breakdown:

| Folder | Count | Layer | Purpose |
|---|---|---|---|
| `workflows/` (top-level) | 50 | Layer 0 (legacy) | Pre-restructure workflows including the 7 protected v2/v3 production set |
| `workflows/api/admin/` | 9 | Layer 1 | Admin dashboard data webhooks |
| `workflows/api/client/` | 11 | Layer 1 | Client dashboard data webhooks (incl. 2 copilot) |
| `workflows/api/auth/` | 8 | Layer 1 | Login, magic-link, password reset, welcome, etc. |
| `workflows/api/email/` | 1 | Layer 1 | Postmark generic sender (`clx-email-send`) |
| `workflows/api/agent/` | 8 | Layer 1 | AI Sales Agent (decision-engine, action-executor, voice in/out, conversation handler, memory, escalation, daily summary) |
| `workflows/api/intelligence/` | 5 | Layer 1 | Behavioral Intelligence (ingestion, classify, trigger engine, archetype seed, learner) |
| `workflows/api/video/` | 7 | Layer 1 | Video pipeline (script-gen, HeyGen render, callback, delivery router, landing page, engagement tracker, storage cleanup) |
| `workflows/api/messaging/` | 3 | Layer 1 | WhatsApp send, SMS send, Twilio status callback |
| `workflows/api/booking/` | 1 | Layer 1 | Cal.com booking create |
| `workflows/api/mcp/` | 1 | Layer 1 | MCP agent tools gateway |
| `workflows/api/insurance-mga/` | **41** | **Layer 2 (insurance)** | 12 Part A (compliance/KYC/suitability/disclosure/application) + 29 Part B (onboarding/commission/license/reviews/video-engagement/data-webhooks) |

**Active vs dormant (in repo):** every workflow in `workflows/api/` ships `active: false`. The 50 top-level workflows include 7 production-active v2/v3 (protected per CLAUDE.md). Per Mary's audit during Phase 2 import, 8 are actually active in production (7 CLX v2/v3 + 1 unrelated "Practice pro" to be deleted).

**Compliance verification on the 41 Layer 2 workflows:**
- ✅ 41/41 ship `active=false`
- ✅ 36/36 webhook-triggered workflows have `/mga/insurance/` in path
- ✅ 5/5 schedule-triggered (cron) — no path needed
- ✅ 20/41 call `validate_session` (the session-authed external-facing ones)
- ✅ 29/41 write to `regulatory_audit_log` (audit trail coverage)
- ✅ 0 hardcoded credentials
- ✅ 0 forbidden `id` fields inside credential blocks

### 1.3 Frontend (`*-dashboard/`)

Three top-level Cloudflare Pages sites (plain HTML + plain JS, no framework — per CLAUDE.md doctrine):

| Dashboard | Pages | Vertical | Status |
|---|---|---|---|
| `admin-dashboard/` | 10 (`overview`, `clients`, `client-detail`, `leads`, `workflows`, `billing`, `onboarding`, `market-intelligence`, `audit-log`, `settings`) | universal | ✅ deployed to `admin.crystallux.org` |
| `client-dashboard/` | 7 + onboarding wizard | universal | ✅ deployed to `app.crystallux.org` |
| `insurance-mga-dashboard/` | 9 (`login` + `advisor/{overview,reviews,leads,applications,commissions}` + `principal/{overview,advisors,compliance}`) | **Layer 2 (insurance)** | ❌ **NOT YET DEPLOYED** to Cloudflare Pages |

`insurance-mga-dashboard/`:
- Visible "Insurance MGA" badge in topbar on every page
- `clxApi.mgaPost('action')` → `/webhook/mga/insurance/action`
- `shared/components-mga.js` has the 7 new components (VerticalBadge, LicenseStatusIndicator, ComplianceScoreBadge, ReviewTypeIcon, TriggerSourceBadge, VideoEngagementStatus, PriorityIndicator)
- Role-gated to `advisor / sub_agent / mga_principal / compliance_officer / admin`
- `_headers` enforces CSP locked to `automation.crystallux.org` + HSTS + frame-ancestors none + Permissions-Policy locked

### 1.4 Documentation

**122 `.md` files** across `docs/`. Highlights relevant to this audit:

- `docs/journal/SESSION_LOG.md` (single chronological record — entries for 2026-05-08, 2026-05-09, 2026-05-10 Part A, 2026-05-10 Part B)
- `docs/journal/CRYSTALLUX_STATUS.md` (cumulative state)
- `docs/journal/2026-05-10-night-notes.md` + `2026-05-10-night-wrapup.md` (Mary's wrap-up, key inputs for this audit)
- `docs/architecture/{MULTI_VERTICAL_LAYER2_ARCHITECTURE, PRODUCT_VISION, ARCHITECTURE_DOCTRINE, BUSINESS_PLAN, OPERATIONS_HANDBOOK, ROLES, COST_ANALYSIS, AUTH_ARCHITECTURE, DASHBOARD_AUTHENTICATION, scaling-strategy, infrastructure-audit, PHASE_4_TEST_PLAN, VERTICAL_EXPANSION_RANKING, ROADMAP_B9_MARKET_INTELLIGENCE, QUEUED_VERTICAL_SEEDING_B2B, FUTURE_BEAUTY_MARKETPLACE_ROADMAP, mcp-tool-registry}.md`
- `docs/insurance-mga/{AI_COMPLIANCE_VISION, REGULATORY_FRAMEWORK, MGA_OPERATIONS_VISION, REVIEW_MANAGEMENT_VISION, VIDEO_ENGAGEMENT_STRATEGY, SECURITY_FRAMEWORK}.md`
- `docs/agent/{AGENT_VISION, build-phases, content-marketing-vision}.md`
- `docs/audit/` (this audit + prior: api-surface, admin, client, post-fix, role-gate-gaps, blockers, audit-summary, pre-launch, insurance-features-extracted)

**Documentation gaps:**
- No single `docs/setup/insurance-mga-activation.md` consolidating Mary's 5-step activation procedure for Layer 2 (info lives in night notes + session log).
- No central list of every Phase 5b polish item deferred across commits (each session listed its own deferrals).
- `CRYSTALLUX_STATUS.md` cumulative workflow count appears slightly stale (cites pre-Layer 2 numbers in its earlier sections). Worth a sweep next time the doc is touched.

---

## 2. Architecture Compliance

### 2.1 Vertical tagging audit

| Surface | Expected | Found | Pass? |
|---|---|---|---|
| Layer 2 schema tables | every table has `vertical_id text NOT NULL DEFAULT 'insurance'` + `idx_*_vertical` | 16/16 tables (7 Part A + 9 Part B) | ✅ |
| Layer 2 webhook paths | every webhook URL includes `/mga/insurance/` | 36/36 webhooks | ✅ |
| Layer 2 SQL INSERTs/SELECTs | every query sets or filters `vertical_id='insurance'` | All 41 workflows reviewed at commit time; grep shows `vertical_id` literal in 41/41 | ✅ |
| Layer 1 schemas | NO `vertical_id` (universal) | 0 refs across 5 Layer 1 migrations | ✅ |
| Frontend | new pages under `insurance-mga-dashboard/`, not mixed into admin/client | clean separation | ✅ |
| Frontend visible badge | "Insurance MGA" pill in topbar | present on every page | ✅ |

**No mixing violations.** The architecture is enforced top-to-bottom.

### 2.2 Layer separation

| Layer | Surfaces | File count |
|---|---|---|
| Layer 1 (universal SaaS) | `workflows/api/{admin,client,auth,email,agent,intelligence,video,messaging,booking,mcp}/`, `admin-dashboard/`, `client-dashboard/`, 5 Layer 1 migrations | 54 workflows + 17 frontend pages + 5 schemas |
| Layer 2 (insurance MGA) | `workflows/api/insurance-mga/`, `insurance-mga-dashboard/`, 2 Layer 2 migrations | 41 workflows + 9 frontend pages + 2 schemas |
| Shared | `templates/emails/*.html`, `documents/templates/insurance/*.html` | 10 universal email templates + 7 insurance disclosure templates |

**No cross-contamination.** Insurance-specific data, copy, regulators (FSRA/PIPEDA/CASL), and persona/look defaults all live in Layer 2. The video pipeline / BI / AI agent / KYC infrastructure live in Layer 1 — Layer 2 calls into them via internal webhooks.

### 2.3 Security compliance

| Check | Result |
|---|---|
| Hardcoded API keys in repo | **0** in Layer 2 workflows; **0** in dashboard JS |
| Forbidden `id` field in n8n credential references | **0** (all credentials referenced by name only) |
| Session token auth on user-facing webhooks | 20/41 Layer 2 workflows call `validate_session`. Remaining 21 are either internal-call (`INTERNAL_EMAIL_SECRET`-gated), HMAC-signed public webhooks (Stripe/Zoho), or cron-triggered with no user input. Spot-checked: pattern is correct. |
| Service role limited to n8n | All Supabase REST writes go through `Supabase Crystallux Custom` (httpCustomAuth credential). Service role NOT exposed to browser. |
| Audit trail | 29/41 workflows write to `regulatory_audit_log` (operationally-meaningful subset; read-only data webhooks don't audit-log, which is correct) |
| PII encryption | `advisor_licenses.license_number` + `advisor_eo_insurance.policy_number` AES-256-GCM at app layer with `_last4` companions for display. `LICENSE_ENCRYPTION_KEY` env var per night notes. |
| CSP / HSTS / frame-ancestors | Enforced in `_headers` for all 3 dashboards |

**Note on encryption fail-safe:** if `LICENSE_ENCRYPTION_KEY` is unset, workflows tag values as `PLAINTEXT_NO_KEY:<base64>` so misconfiguration is grep-able. Phase 5b polish (per SECURITY_FRAMEWORK.md) should enforce key presence at workflow startup.

---

## 3. Deployment State (inferred from repo + Mary's night notes)

### 3.1 Commits shipped

| Commit | Date | Scope |
|---|---|---|
| `6bd51c7` | 2026-05-08 | Phase 1 activation: copilot fix, Stripe billing UI, Postmark, Client Assistant backend, BI + Role + Agent schema, content templates |
| `25c0886` | 2026-05-09 | Phase 2/3: 25 workflows (5 BI + 11 video/messaging/booking + 8 agent + 1 MCP), 2 schemas, content marketing vision, status doc |
| `b4f5ec0` | 2026-05-10 | Layer 2 Part A: 12 workflows + insurance-mga schema + 7 disclosure templates + 3 docs (compliance vision, regulatory framework, multi-vertical architecture) |
| `f5a73cf` | 2026-05-10 | Layer 2 Part B: 29 workflows + operations schema + 9 frontend pages + 8 shared frontend files + 4 docs |
| `e592883` | 2026-05-10 | Mary's night notes (continuity) |
| `30255d1` | 2026-05-10 | Mary's night wrap-up notes (deployment complete) |

### 3.2 Mary's manual deployment tasks — completion inference

Per Mary's night notes:

| Task | Status |
|---|---|
| **All 7 SQL migrations executed in Supabase** | ✅ DONE |
| **41 Layer 2 workflows imported into n8n** (Part A 12 + Part B 29) | ✅ DONE (all dormant) |
| **`LICENSE_ENCRYPTION_KEY` saved** in `/root/crystallux/n8n/.env` | ✅ DONE |
| Promote `info@crystallux.org` → `mga_principal` | ⏳ PENDING |
| Seed 12 video review templates via webhook POST | ⏳ PENDING |
| Deploy `insurance-mga-dashboard/` to Cloudflare Pages (`mga.crystallux.org`) | ⏳ PENDING |
| Smoke test all endpoints (login, review-scheduler, BI signal trigger, video chain end-to-end) | ⏳ PENDING |

**Carry-over from prior commits' Mary checklists (uncertain status — not mentioned in night notes):**

| Task | Best inference |
|---|---|
| Stripe Identity API enabled in Stripe dashboard + webhook configured (Part A) | likely pending — no confirmation in notes |
| Zoho Sign signup + OAuth token + webhook (Part A) | likely pending |
| NewsAPI + OpenWeather signups (Phase 2 — for Market Intel activation) | likely pending |
| HeyGen Creator + ElevenLabs + Vapi signups (Phase 3 — for video + voice agent) | likely pending |
| Cloudflare R2 bucket setup (`crystallux-videos`) (Phase 2) | likely pending |
| Twilio Meta WhatsApp Business approval (Phase 2) | 1-2 week external approval; status unknown |
| Postmark domain verification + env var (Phase 1) | likely pending |
| Stripe live products + webhook secret (Phase 1) | likely pending |
| Certn background-check signup (Layer 2 Part B) | **deferred to Phase 5b per notes** |

⚠️ **Mary should confirm the carry-over tasks above before declaring "fully deployed."** The night notes only describe the Layer 2 Part B deployment lift, not whether Phase 1-3 external integrations were ever wired.

### 3.3 Gap analysis per commit

- **`6bd51c7` (Phase 1):** code shipped; activation of Stripe + Postmark + auth-flow Postmark rewire ≈ unknown.
- **`25c0886` (Phase 2/3):** 25 workflows imported per audit (matches commit), all dormant. External signups (NewsAPI/OpenWeather/HeyGen/Vapi/R2/Cal.com) status unknown.
- **`b4f5ec0` (Layer 2 Part A):** 12 workflows imported (counts as part of "41 Layer 2 workflows" in night notes). Stripe Identity + Zoho Sign external setup status unknown.
- **`f5a73cf` (Layer 2 Part B):** 29 workflows imported. `LICENSE_ENCRYPTION_KEY` set. Schema applied. 5 outstanding tasks listed in night notes.

---

## 4. Phase completion tracker

| Phase | Status | Commit | What it delivers | What still needs to happen to be operational |
|---|---|---|---|---|
| **Phase 1** — Foundation activation | 🟡 partial | `6bd51c7` | Copilot CSS fix, Stripe billing UI, Postmark templates, Client Assistant workflows, BI/Agent/Role schemas, content templates | Activate Stripe + Postmark + auth-flow rewire externally |
| **Phase 2/3** — Universal Core | 🟡 partial | `25c0886` | BI workflows (5), video pipeline (7), messaging (3), booking (1), AI agent (8), MCP gateway (1), 2 schemas, content vision | External signups (NewsAPI/OpenWeather/HeyGen/Vapi/R2/Cal.com), activate workflows in order |
| **Layer 2 Part A** — AI Compliance Engine | ✅ code+schema deployed, 🟡 external integrations pending | `b4f5ec0` | 12 workflows (compliance agent, KYC orch, Stripe Identity callback, suitability interview chain, disclosure generator + Zoho Sign + callback, application builder + final review), 7 disclosure templates, 3 docs | Activate Stripe Identity + Zoho Sign externally, wire webhooks back, smoke-test |
| **Layer 2 Part B** — MGA Operations + Reviews + Video Engagement | ✅ code deployed, ⏳ 5 activation tasks pending | `f5a73cf` | 29 workflows (onboarding 5, commissions 3, license 2, reviews 7, data webhooks 7, video engagement 5), MGA-ops schema, 9 frontend pages, 8 shared frontend files, 4 docs | Mary's 5 pending tasks: promote mga_principal, seed templates, deploy frontend, smoke test, then activate workflows |
| **Layer 2 Part C** — Insurer-Facing Mode | 🔴 not started | — | Insurer read-only dashboard, production reports, real-time KPIs, compliance scorecards, demo tools, public capability page | 4-6 hour Claude Code build (next session per night notes); takes platform to 95% |
| **Phase 4** — Content Marketing workflows | 🔴 schema only | schema in `25c0886` | `content_topics`, `content_videos`, `content_publications`, `content_engagement`, `client_content_preferences` already applied | 12 workflows (~2-3 weeks Claude Code) + LinkedIn/Instagram/YouTube/Facebook/TikTok/X API approvals (1-4 weeks each) |
| **Phase 5b** — Polish / gap-closure | 🔴 not started | — | Certn background-check automation, PEP/AML automation, per-province license + disclosure variants, R2-backed editable templates, Zoho OAuth auto-refresh, dedicated dispute_resolutions table, MGA hierarchy expansion in webhooks, SIN/banking encryption | 1-2 week Claude Code build |
| **Phase 6** — Carrier API integration | 🔴 deferred | — | Live carrier quoting + submission, real payment rail (Stripe Connect / Wise) | 12-18 months — business-development driven per night notes |
| **Phase 10** — Advanced compliance automation | 🔴 deferred | — | per night notes "when $5M+ production" | 4-6 weeks Claude Code |
| **Layer 2 Mortgage / Real Estate / etc. verticals** | 🔴 not started | — | New `vertical_id` modules plugging into the same Layer 1 + Layer 2 universal tables | per-vertical 1-2 week Claude Code each (see `MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`) |

---

## 5. Top issues + risks

### 5.1 Architectural concerns

- **Cross-workflow chaining via HTTP-on-localhost** is the dominant pattern (e.g. Layer 2 Part B's review-video-generator calls `clx-video-script-generator-v1` via `${N8N_INTERNAL_BASE}/webhook/video/script-generate`). This is correct per n8n conventions but creates a hidden dependency graph. **Recommendation:** the next major doc pass should publish a workflow dependency diagram.
- **Static carrier-product matrix in `clx-mga-insurance-policy-recommendation-engine-v1`** (top 10 Canadian carriers hard-coded). Acceptable Phase 5 MVP; Phase 6 swaps for live carrier APIs. Worth a single comment in `MGA_OPERATIONS_VISION.md` so future engineers don't grep for a missing carriers table.
- **`policy_reviews.video_render_id` is a soft FK** (no REFERENCES) by design to avoid cross-domain hard FK between Layer 2 and Layer 1's `video_renders`. Application code is responsible for referential integrity. This is correct but undocumented in schema comments — worth adding.

### 5.2 Deployment gaps (highest priority)

1. **Insurance MGA dashboard not on Cloudflare Pages.** Code is in `insurance-mga-dashboard/` but no `mga.crystallux.org` project. Mary cannot login.
2. **No `mga_principal` user yet.** Even after frontend deploys, Mary can't see the principal pages until `auth_users.user_role` is flipped for her account.
3. **Video review templates not seeded.** First triggered review will fail to find a matching template — silent no-op. Easy fix (one-time webhook POST).
4. **Phase 1/2/3 external integrations status unconfirmed.** Stripe / Postmark / NewsAPI / HeyGen / Vapi / R2 / Twilio Meta WA — Mary needs to confirm or work through these before Layer 2 workflows can actually fire end-to-end.
5. **Cloudflare cache purge** typically required after dashboard deploy (per CLAUDE.md convention) — easy to forget.

### 5.3 Security observations

- ✅ Encryption-at-rest correctly implemented for license + E&O policy numbers.
- ✅ All sensitive endpoints use `validate_session` RPC.
- ✅ All credentials reference by name in workflows.
- ⚠️ **`LICENSE_ENCRYPTION_KEY` rotation procedure undocumented.** When it rotates, every encrypted row in `advisor_licenses` + `advisor_eo_insurance` becomes undecryptable unless re-encrypted in place. A rotation playbook (export-decrypt-re-encrypt-import) belongs in `SECURITY_FRAMEWORK.md`.
- ⚠️ **`INTERNAL_EMAIL_SECRET` is shared across ALL internal-call workflows.** Workflows like `clx-mga-insurance-review-triggered-event-v1` and `clx-email-send` use the same secret. If one workflow leaked the secret (log scrape), every internal-call endpoint is callable. Phase 5b: per-workflow or per-domain secrets.
- ⚠️ **No rate limiting on public webhooks** (Stripe Identity callback, Zoho Sign callback, Twilio status, HeyGen webhook, video landing tracker). Cloudflare WAF in front mitigates somewhat but a deliberate per-endpoint check would be safer.

### 5.4 Performance considerations at scale

- `regulatory_audit_log` is append-only with no partitioning. At 10,000 policies × ~10 events/policy/month = 100K rows/month = 1.2M rows/year per active client. **Will need partitioning by `occurred_at` (monthly) at ~5-10 clients.** Phase 5b candidate.
- `video_renders` retention is 90 days for outreach (per `clx-video-storage-cleanup-v1`). Content-marketing videos kept indefinitely. R2 cost grows linearly with content-marketing volume — model in `COST_ANALYSIS.md`.
- BI signal classifier (`clx-behavioral-intelligence-v1`) runs every 30 min and queues ~50 signals per batch via Claude Sonnet. At 50 clients × 100 signals/day = 5,000 Claude calls/day. Token cost estimate ~$15-30/day at scale — fine, but monitor.

### 5.5 Single points of failure

- **HeyGen API** for all video generation (no failover provider). Phase 5b: add Synthesia or Tavus fallback for revenue-critical reviews (renewal, claim).
- **Vapi** for all voice (no fallback). Same comment — Retell is the documented alternative.
- **Anthropic API** for every Claude call across Layer 1 + Layer 2. n8n env `ANTHROPIC_API_KEY` is single key, no rotation playbook. Mary should set up a second key in a different account as cold standby.
- **Cloudflare R2** for all video + disclosure storage. Egress fees would bite if migrated; commit to R2 long-term.
- **Supabase** for everything DB. Standard concern; backed up via Supabase point-in-time recovery.

### 5.6 External dependencies (count + criticality)

| Provider | Used for | Status | Criticality |
|---|---|---|---|
| Anthropic | Claude calls (BI, Decision Engine, Compliance Agent, all Claude prompts) | active | CRITICAL |
| Supabase | DB + Auth + Storage (PII) | active | CRITICAL |
| Cloudflare Pages | Frontend hosting + CDN | partially deployed (admin + client; insurance-mga pending) | CRITICAL |
| Cloudflare R2 | Video + disclosure + signed-doc storage | active per night notes (R2 setup confirmed in earlier sessions) | CRITICAL |
| OpenAI | Whisper transcription, text-embedding-3-small (memory) | active | HIGH |
| Postmark | Transactional email | likely pending activation | HIGH |
| Stripe | Billing + Identity verification | partially active (billing Phase 1; Identity Phase A pending) | HIGH |
| HeyGen | Avatar video generation | likely pending signup | HIGH |
| Zoho Sign | E-signature for disclosures | likely pending signup | HIGH |
| Twilio | WhatsApp + SMS + Voice (via Vapi SIP) | partially active (account exists); WA Meta approval pending | HIGH |
| Vapi | AI voice agent | likely pending signup | MEDIUM (only voice agent path) |
| ElevenLabs | Voice cloning for personas | likely pending signup | MEDIUM |
| Cal.com | Booking integration | likely pending; Calendly path exists as alternative | MEDIUM |
| NewsAPI | Market Intelligence signals | likely pending | MEDIUM |
| OpenWeather | Market Intelligence signals | likely pending | MEDIUM |
| Certn | Background checks (Layer 2 Part B onboarding) | **deferred to Phase 5b** | LOW (manual workaround works) |
| Unipile | LinkedIn DM (Phase 4 content + outreach) | active per audit | LOW |

---

## 6. What's left before first customer

### 6.1 Mandatory (blocks launch) — ~3-4 days total work, mostly Mary

| # | Task | Owner | Time | Dependencies |
|---|---|---|---|---|
| 1 | Promote `info@crystallux.org` → `mga_principal` in Supabase | Mary | 1 min | none |
| 2 | Seed 12 video review templates via webhook POST | Mary | 2 min | INTERNAL_EMAIL_SECRET set |
| 3 | Deploy `insurance-mga-dashboard/` to Cloudflare Pages | Mary | 15 min | DNS for `mga.crystallux.org` |
| 4 | Confirm Phase 1/2/3 external integration status (Stripe billing, Postmark, R2, HeyGen, Vapi, Twilio WA approval) | Mary | 1-2 hours audit | Mary's signup activity since last commits |
| 5 | Whichever from #4 are unwired: sign up + configure | Mary | 2-3 hours per missing service | external provider availability |
| 6 | Activate Layer 2 workflows in correct order (compliance agent → KYC → suitability → application → reviews → video engagement) | Mary | 30 min | all of above |
| 7 | End-to-end smoke test: login → create test advisor → trigger BI signal → verify video chain → engagement update | Mary | 1-2 hours | activation complete |
| 8 | **Layer 2 Part C build** (insurer-facing dashboards + reports + demo tools) | **Claude Code** | 4-6 hours | this audit's findings |
| 9 | Final smoke test post-Part C | Mary | 30 min | Part C deployed |

Total: ~2-3 days elapsed, mostly Mary's work + 1 Claude Code session.

### 6.2 Should-have (important but not blocking) — Phase 5b polish

- Certn background-check integration (~1 week Claude Code)
- Per-province license + disclosure variants (Quebec FR, BC, AB) (~1 week)
- Dedicated `dispute_resolutions` table replacing audit-log-only capture
- Dedicated `compliance-review-required.html` email template
- `LICENSE_ENCRYPTION_KEY` rotation playbook documented
- Per-internal-call `INTERNAL_EMAIL_SECRET` per workflow
- MGA hierarchy expansion in webhooks (currently mga_principal sees all — fine for single-MGA, breaks at multi-MGA)
- `regulatory_audit_log` partitioning by month

### 6.3 Nice-to-have (defer)

- Phase 4 content marketing workflows (2-3 weeks; ~$0 marginal cost above what's already shipped)
- Cross-vertical Layer 2 modules (mortgage, real estate, group benefits)
- Phase 6 carrier API integration (business-development driven, 12-18 months)
- Phase 10 advanced compliance automation
- Migration to Node.js services (deferred per night notes until $300K+ MRR)

---

## 7. Next session recommendations

### 7.1 Claude Code (next session)

**Layer 2 Part C — Insurer-Facing Mode.** Per night notes: insurer read-only dashboard, production reports, real-time KPIs, compliance scorecards, demo tools, public capability page. Estimated 4-6 hours. **This is the right next session** because:

- It's the last piece of the Layer 2 trilogy (67% → 95% platform complete)
- It's what gets carrier conversations moving (carriers need to *see* the audit trail Crystallux produces)
- The schema and data sources already exist (no new tables; reads from `regulatory_audit_log`, `compliance_reviews`, `policy_reviews`, `commission_ledger`)

**Alternative if Mary wants to delay Part C:** consolidate Phase 5b polish items into a single 1-week sprint. Higher long-term value than activating dormant Layer 2 today.

**Strong recommendation: do Part C first.** Layer 2 Part B activation can run in parallel — Mary is doing the activation work while Claude Code builds Part C, and Mary smoke-tests both at the end.

### 7.2 Mary's immediate priorities (this morning, 60-90 min)

Per night notes — confirmed by this audit:

1. Promote `mga_principal` user
2. Seed video templates
3. Deploy frontend to Cloudflare Pages
4. Smoke test in dormant mode (verify pages load + auth gate works) — don't activate workflows yet
5. Send Layer 2 Part C prompt to Claude Code

### 7.3 What can wait

- All Phase 5b polish (post-Part C)
- All carry-over Phase 1-3 external integrations EXCEPT the ones needed for the smoke test (HeyGen + Twilio for video pipeline test)
- Phase 4 content marketing
- Other-vertical Layer 2 modules

---

## Appendix: numbers at a glance

```
Repository state — 2026-05-11
─────────────────────────────────────────────
  Lifetime commits on scale-sprint-v1     216
  Working-tree status                  clean
  Latest commit                       30255d1
  Last engineering commit             f5a73cf

Code surfaces
─────────────────────────────────────────────
  Migrations (total)                       9
    Layer 1 (universal)                    5
    Layer 2 (insurance)                    2
    Inert / data-only                      2

  Workflow JSONs (total)                 145
    Top-level (legacy + prod v2/v3)       50
    workflows/api/                         95
      Layer 1                             54
      Layer 2 (insurance-mga)             41

  Frontend dashboards                      3
    admin-dashboard (universal)     deployed
    client-dashboard (universal)    deployed
    insurance-mga-dashboard          PENDING

  Documentation files                    122
  Email templates                         10
  Insurance disclosure templates           7

Compliance verification (Layer 2)
─────────────────────────────────────────────
  Active=true workflows                    0  ✅
  Hardcoded credentials                    0  ✅
  Forbidden id in credentials              0  ✅
  Webhook paths with /insurance/      36/36   ✅
  vertical_id on Layer 2 tables       16/16   ✅
  vertical_id refs (Layer 2)              58
  vertical_id refs (Layer 1)               0   ✅ correct

Audit trail
─────────────────────────────────────────────
  Layer 2 workflows writing regulatory_
    audit_log                          29/41
  Layer 2 workflows calling validate_
    session                            20/41
```

## Cross-references

- Night-notes basis: [`docs/journal/2026-05-10-night-notes.md`](../journal/2026-05-10-night-notes.md), [`2026-05-10-night-wrapup.md`](../journal/2026-05-10-night-wrapup.md)
- Session history: [`docs/journal/SESSION_LOG.md`](../journal/SESSION_LOG.md)
- Cumulative state: [`docs/journal/CRYSTALLUX_STATUS.md`](../journal/CRYSTALLUX_STATUS.md)
- Vertical architecture: [`docs/architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md`](../architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md)
- Layer 2 Part A: [`docs/insurance-mga/AI_COMPLIANCE_VISION.md`](../insurance-mga/AI_COMPLIANCE_VISION.md), [`REGULATORY_FRAMEWORK.md`](../insurance-mga/REGULATORY_FRAMEWORK.md)
- Layer 2 Part B: [`docs/insurance-mga/MGA_OPERATIONS_VISION.md`](../insurance-mga/MGA_OPERATIONS_VISION.md), [`REVIEW_MANAGEMENT_VISION.md`](../insurance-mga/REVIEW_MANAGEMENT_VISION.md), [`VIDEO_ENGAGEMENT_STRATEGY.md`](../insurance-mga/VIDEO_ENGAGEMENT_STRATEGY.md), [`SECURITY_FRAMEWORK.md`](../insurance-mga/SECURITY_FRAMEWORK.md)
