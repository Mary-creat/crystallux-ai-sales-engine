# Crystallux Build Status — 2026-05-11

> **Audience:** Mary. Keep this open while wiring credentials. **Status: Layer 2 Part B (MGA Operations + Reviews + Video Engagement) complete. Layer 2 is 67% complete. Layer 2 Part C (insurer-facing) is the final session.**
> Latest commit on `scale-sprint-v1`: `475ef01` (feature audit). Most recent engineering commit: `f5a73cf` (Layer 2 Part B).

> **📘 NEW (2026-05-11): Comprehensive Founder's Operations Handbook published.**
> Single source of truth for operating, understanding, and making decisions about the Crystallux platform: [`docs/handbook/FOUNDER_OPERATIONS_HANDBOOK.md`](../handbook/FOUNDER_OPERATIONS_HANDBOOK.md). Read this if you're new to the codebase or stuck on operations. Status doc + handbook are complementary: this doc is **what's currently shipped**, the handbook is **how the whole thing works**.

## LATEST: Layer 2 Part B — MGA Operations + Reviews + Video Engagement

| Metric | Value |
|---|---|
| New workflows this commit | **29** (`workflows/api/insurance-mga/clx-mga-insurance-*-v1.json`) — all DORMANT |
| New schema migration | **1** (`db/migrations/insurance-mga-operations-schema.sql` — 9 tables + 5 ALTERs) |
| New frontend pages | **9** (`insurance-mga-dashboard/`) |
| New shared frontend files | **8** (`auth.js`, `api.js`, `components-mga.js`, `layout.css`, `nav.html`, `_headers`, `_redirects`, `index.html`) |
| New docs | **4** (MGA Operations Vision, Review Management Vision, Video Engagement Strategy, Security Framework) |
| Total files added in this commit | **~50 net-new** |

This commit ships the **operational backbone of insurance MGA + the unique behavioral-signal-triggered video engagement system**. Mary's 10 LLQP-licensed advisors get purpose-built tooling on top of the AI compliance brain from Part A. Every life event becomes a meaningful client touchpoint via personalized HeyGen avatar videos. See `docs/insurance-mga/MGA_OPERATIONS_VISION.md` + `REVIEW_MANAGEMENT_VISION.md` + `VIDEO_ENGAGEMENT_STRATEGY.md` + `SECURITY_FRAMEWORK.md`.

**Layer 2 trilogy progress:**
- ✅ Part A — AI Compliance Engine (commit `b4f5ec0`)
- ✅ Part B — MGA Operations + Reviews + Video Engagement (this commit)
- 🔴 Part C — Insurer-Facing Mode + Production Reports (next session)

---

## LATEST: Layer 2 Part A — AI Compliance Engine (Insurance MGA)

| Metric | Value |
|---|---|
| New workflows this commit | **12** (`workflows/api/insurance-mga/clx-mga-insurance-*-v1.json`) — all DORMANT |
| New schema migration | **1** (`db/migrations/insurance-mga-schema.sql` — 7 tables, every one `vertical_id`-tagged) |
| New disclosure templates | **7** (`documents/templates/insurance/*.html`) |
| New docs | **3** (AI compliance vision, regulatory framework, multi-vertical Layer 2 architecture) |
| External services Mary activates | Stripe Identity + Zoho Sign |
| Cost per fully-processed client | **~$1.85** (vs $80-200 traditional MGA per-client compliance overhead) |

This commit ships the **AI brain of insurance MGA operations**. Manual compliance work (KYC verification 1-3 days → ~5 min, suitability 2-5 days → ~10 min of client time, application data entry hours → instant, compliance review 3-7 days → instant) replaced by AI workflows with `compliance_officer` human-in-the-loop override authority retained on every decision. See `docs/insurance-mga/AI_COMPLIANCE_VISION.md` + `docs/insurance-mga/REGULATORY_FRAMEWORK.md`.

**Multi-vertical architecture committed:** every Layer 2 table carries `vertical_id text NOT NULL DEFAULT 'insurance'` so future verticals (mortgage MGA Phase 7, real estate Phase 8, group benefits Phase 10, commercial insurance Phase 11) plug in without schema migration. See `docs/architecture/MULTI_VERTICAL_LAYER2_ARCHITECTURE.md` for the strategy + plug-in pattern.

---

## CUMULATIVE EXECUTIVE SUMMARY

| Metric | Value | Notes |
|---|---|---|
| Workflow JSONs in repo (active path) | **87** = 50 top-level + 25 from commit 25c0886 + 12 from this commit | excludes legacy admin/client/auth/email webhooks |
| Currently ACTIVE in production | **9 protected v2/v3 + 18 admin/client webhooks** | per `docs/audit/api-surface-audit.md` Bucket 1 (note: doc is stale — see live n8n audit drift report from prior session) |
| BUILT-DORMANT awaiting wiring | **34 (pre 25c0886) + 25 (commit 25c0886) + 12 (this commit) = 71** | every new workflow ships `active: false` |
| Specced not yet built | Layer 2 Parts B + C + Phase 4 content workflows + Phase 5+ vertical dashboards | foundations ready |
| Database tables — agent + BI + delivery + content + MGA | **31 net-new** across 6 migrations | 6 migrations Mary applies in order (see below) |
| Active paying clients | _Mary fills in after deploy_ | `SELECT count(*) FROM clients WHERE status = 'active'` |
| Total leads in production | _Mary fills in after deploy_ | `SELECT count(*) FROM leads;` |

**One-line reality:** The platform has every workflow needed for autonomous AI Sales Agent (voice + WA + SMS + email + video) PLUS the AI Compliance Engine for insurance MGA operations (KYC, suitability, recommendation, disclosure, application). Layer 2 Parts B + C and Phase 4 content marketing are deferred.

---

## ✅ DEPLOYED + LIVE (production)

### Database
**To verify post-deploy** (run in Supabase SQL editor):
```sql
SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;
SELECT count(*) AS leads FROM leads;
SELECT count(*) AS clients_active FROM clients WHERE status = 'active';
SELECT count(*) AS leads_new_30d FROM leads WHERE date_created > now() - interval '30 days';
SELECT count(*) AS auth_admin FROM auth_users WHERE user_role = 'admin';
SELECT count(*) AS market_signals FROM market_signals_processed;
SELECT count(*) AS behavioral_signals FROM behavioral_signals;
SELECT count(*) AS bookings FROM bookings;
SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pgcrypto');
```

### Active workflows (per `docs/audit/api-surface-audit.md` Bucket 1)
- 9 auth webhooks (login / logout / validate-session / magic-link / magic-link-verify / password-reset-request / password-reset-complete / welcome / [TODO Postmark wire])
- 9 admin webhooks (system-health / list-clients / client-detail / list-leads / workflow-status / billing-summary / onboarding-pipeline / market-intelligence / audit-log)
- 9 client webhooks (overview / leads / campaigns / bookings / replies / activity / billing / settings / performance)
- 9 protected v2/v3 orchestration workflows (lead-import / lead-research-v2 / lead-scoring-v2 / campaign-router-v2 / outreach-generation-v2 / outreach-sender-v2 / reply-ingestion-v1 / pipeline-update-v2 / booking-v2)

### External integrations
| Service | Status | Notes |
|---|---|---|
| Stripe | Built dormant — Mary activates per `docs/setup/stripe-activation.md` | `clx-stripe-provision-v1` + `clx-stripe-webhook-v1` ready, env vars + Live products needed |
| Postmark | Built dormant — Mary activates per `docs/setup/postmark-activation.md` | `clx-email-send` + 10 templates ready |
| Twilio | Account exists, +1 438 number | Per-client WA + SMS sender configuration via `agent_channels_enabled` |
| HeyGen | TBD signup ($29/mo Creator) | persona setup ~90 min once account exists — see Mary's checklist below |
| ElevenLabs | TBD signup ($5/mo) | clone 4 voices for the personas |
| Vapi | TBD signup | recommended over Retell per `docs/agent/build-phases.md` |
| Cal.com | TBD signup OR existing Calendly | `clx-booking-create-v1` calls Cal.com; Calendly path exists via `clx-booking-v2` (production) |
| Cloudflare R2 | TBD bucket setup `crystallux-videos` | ~15 min setup + custom domain `videos.crystallux.org` |
| Anthropic API | Active credential bound (Copilot, BI, Decision Engine all reference `ANTHROPIC_API_KEY`) | |
| OpenAI API | Active credential bound (Whisper + embeddings) | |
| Hunter.io | Active per audit | for email enrichment in lead-research-v2 |
| Apollo.io | Active per audit | for company enrichment in lead-research-v2 |
| NewsAPI | TBD signup (free tier 100/day) | required to activate `clx-signal-ingestion-v1` |
| OpenWeather | TBD signup (free tier 1000/day) | same |

### Frontend
- Admin dashboard: 10 pages + Copilot ✦ (commit 6bd51c7 fix landed)
- Client dashboard: 7 pages + Assistant ✦ + onboarding wizard (commit 6bd51c7)
- Marketing site: live at crystallux.org

---

## 🟡 BUILT-DORMANT (this commit + prior)

### Market Intelligence (5 — pre-existing, awaiting NewsAPI + OpenWeather creds)
- `clx-signal-ingestion-v1` (top-level)
- `clx-signal-intelligence-v1` (top-level)
- `clx-business-signal-detection-v2` (top-level)
- `clx-intelligence-upsell-detector-v1` (top-level)
- `clx-campaign-router-v2` (top-level — protected production, dormant on activation flag)

### Behavioral Intelligence (5 — **this commit, Part A**)
- `workflows/api/intelligence/clx-behavioral-signal-ingestion-v1.json` (6h schedule)
- `workflows/api/intelligence/clx-behavioral-intelligence-v1.json` (30 min Claude classifier)
- `workflows/api/intelligence/clx-behavioral-trigger-engine-v1.json` (hourly archetype matcher)
- `workflows/api/intelligence/clx-archetype-seed-insurance-v1.json` (one-time webhook seed)
- `workflows/api/intelligence/clx-behavioral-archetype-learner-v1.json` (Sunday 02:00 conversion-rate updater)

### Video Pipeline + Multichannel Delivery (11 — **this commit, Part B**)
- `workflows/api/video/clx-video-script-generator-v1.json`
- `workflows/api/video/clx-video-heygen-render-v1.json`
- `workflows/api/video/clx-heygen-webhook-v1.json` (with R2 automation)
- `workflows/api/video/clx-video-delivery-router-v1.json`
- `workflows/api/video/clx-video-landing-page-v1.json`
- `workflows/api/video/clx-video-engagement-tracker-v1.json`
- `workflows/api/video/clx-video-storage-cleanup-v1.json` (daily 03:00)
- `workflows/api/messaging/clx-whatsapp-send-v1.json` (gates on Meta WA approval)
- `workflows/api/messaging/clx-sms-send-v1.json` (ready as soon as Twilio configured)
- `workflows/api/messaging/clx-twilio-status-callback-v1.json`
- `workflows/api/booking/clx-booking-create-v1.json`

### AI Sales Agent (8 — **this commit, Part C**)
- `workflows/api/agent/clx-agent-decision-engine-v1.json` (15 min — the brain)
- `workflows/api/agent/clx-agent-action-executor-v1.json` (router)
- `workflows/api/agent/clx-agent-voice-outbound-v1.json` (Vapi)
- `workflows/api/agent/clx-agent-voice-inbound-v1.json` (Twilio voice → Vapi SIP)
- `workflows/api/agent/clx-agent-conversation-handler-v1.json` (replies via Claude)
- `workflows/api/agent/clx-agent-memory-update-v1.json` (OpenAI embed → pgvector)
- `workflows/api/agent/clx-agent-escalation-v1.json` (human handoff)
- `workflows/api/agent/clx-agent-daily-summary-v1.json` (07:00 per-client rollup)

### MCP Agent Tools Gateway (1 — commit 25c0886, Part D)
- `workflows/api/mcp/clx-mcp-agent-tools-v1.json` (10 write tools wrapping the action workflows)

### Insurance MGA — AI Compliance Engine (12 — **this commit, Layer 2 Part A**)
- `workflows/api/insurance-mga/clx-mga-insurance-compliance-agent-v1.json` (the AI Compliance Agent)
- `workflows/api/insurance-mga/clx-mga-insurance-kyc-orchestrator-v1.json` (Stripe Identity)
- `workflows/api/insurance-mga/clx-mga-insurance-stripe-identity-callback-v1.json` (HMAC-verified)
- `workflows/api/insurance-mga/clx-mga-insurance-suitability-interview-v1.json` (start)
- `workflows/api/insurance-mga/clx-mga-insurance-suitability-conversation-handler-v1.json`
- `workflows/api/insurance-mga/clx-mga-insurance-needs-analysis-v1.json` (Claude needs gap)
- `workflows/api/insurance-mga/clx-mga-insurance-policy-recommendation-engine-v1.json` (rank carriers)
- `workflows/api/insurance-mga/clx-mga-insurance-disclosure-generator-v1.json` (HTML → R2)
- `workflows/api/insurance-mga/clx-mga-insurance-esignature-orchestrator-v1.json` (Zoho Sign)
- `workflows/api/insurance-mga/clx-mga-insurance-zoho-sign-callback-v1.json` (HMAC-verified)
- `workflows/api/insurance-mga/clx-mga-insurance-application-builder-v1.json` (auto-complete app)
- `workflows/api/insurance-mga/clx-mga-insurance-application-final-review-v1.json` (advisor approve → submit)

### Phase 1 Activations (commit 6bd51c7, pre-this-commit)
- `workflows/api/email/clx-email-send.json` (Postmark gateway)
- `workflows/api/auth/clx-auth-welcome.json` (idempotent welcome)
- `workflows/api/client/clx-client-copilot-ask.json` (Client Assistant chat)
- `workflows/api/client/clx-client-copilot-transcribe.json` (Whisper for Client Assistant)

---

## 🔴 NOT YET BUILT (deferred)

### Phase 4: Content Marketing Workflows (schema ready in this commit, Part E)
- 12 workflows estimated (`docs/agent/content-marketing-vision.md`)
- Gates: LinkedIn / Instagram / YouTube / Facebook / TikTok / X API approvals (1-4 weeks per platform)
- Schema lives in `db/migrations/content-marketing-schema.sql` (this commit)
- **Estimate: 2-3 weeks** Claude Code work after API approvals

### Phase 5: Insurance Vertical Advisor Dashboard
- Insurance-specific UI on top of universal AI Agent + BI engine
- Spec already in `docs/audit/insurance-features-extracted.md`
- Estimate: ~2 weeks

### Phase 6: Reporting Tool Workflows
- Reads agent_performance + agent_decisions for cross-client benchmarks
- Estimate: ~1 week

### Phase 7+: Other vertical-specific dashboards
- Real estate, mortgage, dental, construction (per BUSINESS_PLAN)
- Each: ~1-2 weeks

---

## 📋 MARY'S COMPLETE WIRING CHECKLIST

### TODAY (after this push lands, ~2 hours)

#### Database migrations — apply in this exact order (10 min)
- [ ] `db/migrations/role-enum-update.sql` (commit 6bd51c7)
- [ ] `db/migrations/behavioral-intelligence-schema.sql` (commit 6bd51c7)
- [ ] `db/migrations/ai-agent-schema.sql` (commit 6bd51c7)
- [ ] `db/migrations/delivery-channels-schema.sql` (**this commit**)
- [ ] `db/migrations/content-marketing-schema.sql` (**this commit**)

Verification queries are at the bottom of each migration file (commented).

#### VPS deploy (15 min)
- [ ] SSH to VPS, `cd /root/crystallux-workflows && git pull`
- [ ] Copy `workflows/api/intelligence/`, `workflows/api/video/`, `workflows/api/messaging/`, `workflows/api/booking/`, `workflows/api/agent/`, `workflows/api/mcp/` to `/root/crystallux-workflows/api/`
- [ ] Update `/tmp/clx-import.sh` to include the 25 new paths (or pass all `api/**/*-v1.json` if your script globs)
- [ ] Run `/tmp/clx-import.sh` and confirm all 25 imported

#### Cloudflare cache purge (5 min)
- [ ] Purge `admin.crystallux.org`, `app.crystallux.org`, `crystallux.org`

#### Quick smoke tests (30 min)
- [ ] Login admin dashboard, Copilot ✦ button styled bottom-right
- [ ] Login as `testclient@crystallux.org`, Assistant works
- [ ] In Supabase: `SELECT tablename FROM pg_tables WHERE tablename IN ('video_renders','video_engagement','messages_sent','bookings','content_topics','behavioral_signals','agent_decisions','agent_memory');` returns 8 rows
- [ ] `SELECT extname FROM pg_extension WHERE extname='vector';` returns 1 row

### THIS WEEK (~3-4 hours active work + waiting)

#### External service signups
- [ ] Sign up NewsAPI at newsapi.org (5 min)
- [ ] Sign up OpenWeather at openweathermap.org (10 min)
- [ ] Sign up HeyGen Creator $29/mo at heygen.com (5 min)
- [ ] Sign up HeyGen API at developers.heygen.com (5 min, $20 starting balance)
- [ ] Sign up ElevenLabs $5/mo at elevenlabs.io (5 min)
- [ ] Sign up Vapi at vapi.ai (15 min)
- [ ] Sign up Cal.com at cal.com (15 min) OR confirm existing Calendly continues to drive `clx-booking-v2`
- [ ] Set up Cloudflare R2 bucket `crystallux-videos` + custom domain `videos.crystallux.org` (15 min)

#### HeyGen persona setup (90 min total)
- [ ] Generate Persona 1 (James — B2B male, suit) via prompt-to-avatar
- [ ] Generate Persona 2 (Sarah — B2B female, blazer) via prompt-to-avatar
- [ ] Generate Persona 3 (Marcus — field male, branded polo) via prompt-to-avatar
- [ ] Generate Persona 4 (Maria — personal services female, warm) via prompt-to-avatar
- [ ] Generate 3 looks per persona (12 look_id values total)
- [ ] Clone 4 voices in ElevenLabs to match personas
- [ ] Save all 4×3 = 12 HeyGen avatar IDs + 4 voice IDs in your credentials notes (used to populate `HEYGEN_AVATAR_*` and `HEYGEN_VOICE_*` env vars)

#### Stripe + Postmark final activation
- [ ] Stripe products + webhook + env vars (60 min, follow `docs/setup/stripe-activation.md`)
- [ ] Postmark CNAME wait + env var + the 1-line auth rewire (30 min, follow `docs/setup/postmark-activation.md`)

#### n8n environment variables on VPS — add to `/root/.n8n/.env`
- [ ] `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`
- [ ] `STRIPE_PRICE_STARTER`, `STRIPE_PRICE_GROWTH`, `STRIPE_PRICE_SCALE`
- [ ] `POSTMARK_API_TOKEN`
- [ ] `INTERNAL_EMAIL_SECRET` (any 32-char random — used by 14 workflows for internal-only auth)
- [ ] `NEWSAPI_KEY`, `OPENWEATHER_API_KEY`
- [ ] `HEYGEN_API_KEY`, `HEYGEN_WEBHOOK_SECRET`
- [ ] `HEYGEN_AVATAR_JAMES_SUIT`, `HEYGEN_AVATAR_JAMES_CASUAL`, `HEYGEN_AVATAR_SARAH_SUIT`, `HEYGEN_AVATAR_SARAH_BLAZER`, `HEYGEN_AVATAR_MARCUS_UNIFORM`, `HEYGEN_AVATAR_MARCUS_POLO`, `HEYGEN_AVATAR_MARCUS_BRANDED`, `HEYGEN_AVATAR_MARIA_WARM` (only the 8 you actually generate; defaults to placeholder if missing)
- [ ] `HEYGEN_VOICE_JAMES_VOICE`, `HEYGEN_VOICE_SARAH_VOICE`, `HEYGEN_VOICE_MARCUS_VOICE`, `HEYGEN_VOICE_MARIA_VOICE`
- [ ] `ELEVENLABS_API_KEY`
- [ ] `VAPI_API_KEY`, `VAPI_ASSISTANT_ID`, `VAPI_PHONE_NUMBER_ID`, `VAPI_SIP_URI`
- [ ] `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_BUCKET=crystallux-videos`, `R2_PUBLIC_URL=https://videos.crystallux.org`
- [ ] `CALCOM_API_KEY`, `CALCOM_DEFAULT_EVENT_TYPE_ID`
- [ ] `TWILIO_ACCOUNT_SID`, `TWILIO_SMS_FROM`, `TWILIO_WHATSAPP_FROM`
- [ ] `N8N_INTERNAL_BASE` (default `http://localhost:5678` — workflows call siblings via this)
- [ ] `N8N_PUBLIC_BASE` (default `https://automation.crystallux.org` — used in Twilio status callback URLs)
- [ ] `LANDING_PAGE_BASE` (default `https://crystallux.org/v` — in HeyGen webhook landing_page_url builder)
- [ ] `LANDING_PAGE_TRACKER_BASE` (default `https://automation.crystallux.org/webhook/v/track`)
- [ ] `systemctl restart n8n`

#### n8n credentials (UI-side, can't go in env)
- [ ] **Cloudflare R2** (type: AWS) — Region `auto`, Custom Endpoints enabled, S3 endpoint = `R2_ENDPOINT`, Access Key/Secret from R2
- [ ] **Twilio Crystallux** (type: HTTP Basic Auth) — User = `TWILIO_ACCOUNT_SID`, Password = `TWILIO_AUTH_TOKEN`
- [ ] Existing **Supabase Crystallux** + **Supabase Crystallux Custom** (already configured)

#### Activate workflows in n8n UI (15 min)
- [ ] Activate 5 Market Intelligence workflows (legacy, top-level)
- [ ] Activate 5 Behavioral Intelligence workflows (`workflows/api/intelligence/`)
- [ ] Activate 11 Video / Messaging / Booking workflows (`video/` + `messaging/` + `booking/`)
- [ ] Activate 8 AI Agent workflows (`workflows/api/agent/`)
- [ ] Activate 1 MCP Agent Tools gateway (`workflows/api/mcp/`)
- [ ] Activate the Phase 1 workflows from prior commit if not already on (`email/`, `auth/clx-auth-welcome`, `client/clx-client-copilot-*`)

#### Run insurance archetype seed (5 min)
- [ ] `curl -X POST https://automation.crystallux.org/webhook/intelligence/seed-insurance -H 'Content-Type: application/json' -d '{"internal_secret":"<your INTERNAL_EMAIL_SECRET>"}'`
- [ ] Verify in Supabase: `SELECT count(*) FROM signal_archetypes WHERE niche_name='insurance';` = 14

#### Twilio WhatsApp Sender (15 min, then 1-2 week wait)
- [ ] Resume / submit application at Twilio dashboard for Meta WA approval
- [ ] When approved: populate per-client `agent_channels_enabled.configuration.twilio_whatsapp_from` and flip `enabled = true`

### AFTER 1-2 WEEKS (when external approvals clear)

#### Once Meta approves WhatsApp Sender per client
- [ ] Test send to your own WhatsApp first (call `/webhook/messaging/whatsapp-send` directly)
- [ ] Test full flow: AI agent → script → video → WhatsApp delivery

#### Once HeyGen avatars are trained
- [ ] Test render via direct API call — `curl -X POST .../webhook/video/heygen-render -d '{...}'`
- [ ] Verify R2 download/upload automation works (check the bucket after a HeyGen callback fires)
- [ ] Verify landing page renders at `https://crystallux.org/v/<token>` (where token comes from `video_renders.landing_page_token`)

#### Once Vapi configured
- [ ] Activate `clx-agent-voice-outbound-v1`
- [ ] Test outbound call to a friendly number first
- [ ] Activate `clx-agent-voice-inbound-v1` (point Twilio voice webhook at it)

#### Final smoke test (full pipeline) — pick a friendly test lead
- [ ] AI Agent decision engine fires on a behavioral trigger
- [ ] Generates personalised video script via Claude
- [ ] HeyGen renders + R2 stores
- [ ] Delivered via WhatsApp/SMS
- [ ] Lead clicks landing page (engagement events flow to `video_engagement` + a `video_engagement_high_intent` behavioral signal fires)
- [ ] Books meeting via landing page CTA
- [ ] Booking inserts to `bookings` + sends confirmation email
- [ ] All steps log correctly in `agent_actions`, `agent_decisions`, `messages_sent`, `agent_memory`

### FIRST PAYING CUSTOMER (after full pipeline tested end-to-end)
- [ ] Demo to first prospect (Crystallux Insurance Network internal first)
- [ ] Onboard first paying SaaS customer at Growth tier
- [ ] Monitor `agent_performance` daily for first week
- [ ] Iterate on `agent_personalities` based on what reads well

---

## 📊 NUMBERS (run after deploy)

```sql
SELECT count(*) AS leads FROM leads;
SELECT count(*) AS clients_active FROM clients WHERE status = 'active';
SELECT count(*) AS leads_30d FROM leads WHERE date_created > now() - interval '30 days';
SELECT count(*) AS admins FROM auth_users WHERE user_role = 'admin';
SELECT count(*) AS market_signals FROM market_signals_processed;
SELECT count(*) AS behavioral_signals FROM behavioral_signals;
SELECT count(*) AS video_renders FROM video_renders;
SELECT count(*) AS messages_sent FROM messages_sent;
SELECT count(*) AS bookings FROM bookings;
SELECT count(*) AS agent_decisions FROM agent_decisions;
SELECT count(*) AS agent_memories FROM agent_memory;
SELECT count(*) AS escalations_pending FROM agent_escalations WHERE status = 'pending';
SELECT count(*) AS active_archetypes FROM signal_archetypes WHERE active = true;
```

---

## 🎯 MILESTONES

| When | Milestone |
|---|---|
| **Today** | Phase 1 + Phase 2 + Phase 3 BUILT (this commit + 6bd51c7). Wiring is what's left. |
| **Today + 2-4 hrs** | First wiring done (5 migrations + 25 imports + smoke test) |
| **Today + 1 day** | Stripe live (test mode), Postmark sending real emails |
| **Today + 1 day** | Market Intelligence operational (signals flowing) |
| **Today + 2 days** | Behavioral Intelligence active, archetypes seeded |
| **Today + 1 week** | Twilio WhatsApp approved per first client, voice agent configured |
| **Today + 2 weeks** | Full AI Sales Agent operational across voice + WA + SMS + email |
| **Today + 3 weeks** | First paying SaaS customer onboarded |

---

## Cross-references

- This commit's session entry: [`docs/journal/SESSION_LOG.md`](SESSION_LOG.md) (most recent)
- Prior commit summary: same file, `2026-05-08` entry
- Architecture decisions: [`docs/architecture/OPERATIONS_HANDBOOK.md`](../architecture/OPERATIONS_HANDBOOK.md)
- Dormant-by-default doctrine: [`docs/architecture/ARCHITECTURE_DOCTRINE.md`](../architecture/ARCHITECTURE_DOCTRINE.md)
- Audit posture: [`docs/audit/api-surface-audit.md`](../audit/api-surface-audit.md), [`docs/audit/role-gate-gaps.md`](../audit/role-gate-gaps.md), [`docs/audit/blockers.md`](../audit/blockers.md)
