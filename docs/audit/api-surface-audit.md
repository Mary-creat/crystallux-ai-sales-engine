# API surface audit — what we have vs. what the handbook specs

**Generated:** 2026-05-05
**Branch:** `scale-sprint-v1`
**Sources:** every JSON in `workflows/`, OPERATIONS_HANDBOOK.md §§22-§35, [`docs/audit/insurance-features-extracted.md`](insurance-features-extracted.md), [`docs/architecture/CLIENT_COPILOT_SPEC.md`](../architecture/CLIENT_COPILOT_SPEC.md), [`docs/STRIPE_PRODUCTS_SPEC.md`](../STRIPE_PRODUCTS_SPEC.md).
**Inventory tool:** [`tests/audit/inventory-webhooks.js`](../../tests/audit/inventory-webhooks.js).

This is the scoping reference for "what's left to build." Mary uses it to send focused build prompts for each phase. **Documentation only — no code changes.**

---

## How to read this document

- **Bucket 1** — endpoints currently live on `automation.crystallux.org` and verified working. Source-of-truth is the prior audit (`docs/audit/admin-audit-report.md` + `client-audit-report.md`) plus the handbook's "live" callouts.
- **Bucket 2** — workflow JSON exists in repo but the `active` flag is `false` in source AND the endpoint is not exercised by any deployed dashboard. Activation is per-client + per-tier per the dormant-by-default policy.
- **Bucket 3** — handbook references the capability, no JSON file exists yet. Net-new build.
- **Bucket 4** — phase-specific roadmap items grouped by next major build phase (monetisation / video pipeline / advisor dashboard / MGA infra).

> **Note on the `active` flag.** Every workflow JSON in this repo ships `active: false` per the [dormant-by-default doctrine](../architecture/OPERATIONS_HANDBOOK.md). The "deployed" status in Bucket 1 means *Mary has imported the JSON to n8n and flipped active=true in the n8n UI on the VPS*. The source-of-truth for production state is the live n8n instance, not the JSON `active` field. Bucket 1 is what the audit harness has confirmed responds with HTTP 200 + real data.

---

## Common conventions

All non-auth endpoints follow these conventions unless noted:

- **Method:** POST (every webhook except `crystallux-tools` GET).
- **Auth header:** `Authorization: Bearer <session_token>` for client + admin webhooks. Copilot workflows use `body.token` validated against `MARY_MASTER_TOKEN`. Public webhooks (form intake, Stripe, Vapi, Calendly) use HMAC or no auth.
- **Body:** JSON. `{filters: {...}, limit?: int}` is the typical client/admin shape.
- **Response shape:** `{ok: true, <key>: [...]}` on success or `{ok: false, error: "..."}` on failure. HTTP status 401/403 on auth failure, 4xx on validation failure, 200 on success.
- **Tenant scope:** client + team_member sessions are scoped server-side via the `validate_session` RPC — `client_id` is read from the session row, never trusted from the request body.

---

## Bucket 1 — Built and deployed (verified live)

### Auth (login, sessions, tokens)

| Endpoint | File | Purpose | Auth | Tenant scope | Input | Output |
|----------|------|---------|------|--------------|-------|--------|
| `POST /webhook/auth/login` | `api/auth/clx-auth-login.json` | Email + password login → session token | none (public) | public | `{email, password}` | `{ok, session_token, user:{email, role, client_id?}}` |
| `POST /webhook/auth/logout` | `api/auth/clx-auth-logout.json` | Invalidate current session | session token | session-owner | `{}` (token in header) | `{ok}` |
| `POST /webhook/auth/validate-session` | `api/auth/clx-auth-validate-session.json` | Check + extend session | session token | session-owner | `{}` | `{ok, user}` |
| `POST /webhook/auth/magic-link` | `api/auth/clx-auth-magic-link.json` | Send passwordless login email | none | public | `{email}` | `{ok}` |
| `POST /webhook/auth/magic-link-verify` | `api/auth/clx-auth-magic-link-verify.json` | Exchange magic-link token for session | magic token | public | `{token}` | `{ok, session_token, user}` |
| `POST /webhook/auth/password-reset-request` | `api/auth/clx-auth-password-reset-request.json` | Send reset email | none | public | `{email}` | `{ok}` |
| `POST /webhook/auth/password-reset-complete` | `api/auth/clx-auth-password-reset-complete.json` | Set new password from reset token | reset token | public | `{token, new_password}` | `{ok}` |

### Admin operations

| Endpoint | File | Purpose | Auth | Tenant scope | Input | Output |
|----------|------|---------|------|--------------|-------|--------|
| `POST /webhook/admin/system-health` | `api/admin/clx-admin-system-health.json` | Platform-wide KPI strip | session (admin) | admin-only | `{}` | `{ok, total_leads, active_clients, booked_this_week, errors_24h, mrr_cad}` |
| `POST /webhook/admin/list-clients` | `api/admin/clx-admin-list-clients.json` | Client roster + status | session (admin) | admin-only | `{filters?}` | `{ok, clients:[]}` |
| `POST /webhook/admin/client-detail` | `api/admin/clx-admin-client-detail.json` | One client + stats + recent leads | session (admin) | admin-only | `{filters:{client_id}}` | `{ok, client, stats, recent_leads}` |
| `POST /webhook/admin/list-leads` | `api/admin/clx-admin-list-leads.json` | All leads, filterable | session (admin) | admin-only | `{filters:{status?, client_id?}, limit?}` | `{ok, leads:[]}` |
| `POST /webhook/admin/workflow-status` | `api/admin/clx-admin-workflow-status.json` | n8n run / error rollup | session (admin) | admin-only | `{}` | `{ok, runs_24h, errors_24h, avg_ms, active_count, workflows:[]}` |
| `POST /webhook/admin/billing-summary` | `api/admin/clx-admin-billing-summary.json` | MRR + per-client billing | session (admin) | admin-only | `{}` | `{ok, mrr_cad, active_count, trialing_count, past_due_count, canceled_count, clients:[]}` |
| `POST /webhook/admin/onboarding-pipeline` | `api/admin/clx-admin-onboarding-pipeline.json` | 5-stage onboarding rollup | session (admin) | admin-only | `{}` | `{ok, stage_counts, clients:[]}` |
| `POST /webhook/admin/market-intelligence` | `api/admin/clx-admin-market-intelligence.json` | Active signals + tier rollup | session (admin) | admin-only | `{}` | `{ok, raw_24h, processed_24h, active_signals, intel_subs, tokens_mtd, signals:[]}` |
| `POST /webhook/admin/audit-log` | `api/admin/clx-admin-audit-log.json` | Sessions + admin action log | session (admin) | admin-only | `{}` | `{ok, sessions:[], actions:[]}` |

### Client operations

| Endpoint | File | Purpose | Auth | Tenant scope | Input | Output |
|----------|------|---------|------|--------------|-------|--------|
| `POST /webhook/client/overview` | `api/client/clx-client-overview.json` | Client KPI strip + funnel | session (client) | session client_id | `{}` | `{ok, client, stats:{total_leads, new_7d, contacted_30d, replies_30d, booked_30d}}` |
| `POST /webhook/client/leads` | `api/client/clx-client-leads.json` | Tenant's own leads | session (client) | session client_id | `{filters?, limit?}` | `{ok, leads:[]}` |
| `POST /webhook/client/campaigns` | `api/client/clx-client-campaigns.json` | Tenant campaigns + reply rate | session (client) | session client_id | `{}` | `{ok, campaigns:[], active_count, sent_7d, replies_7d, reply_rate}` |
| `POST /webhook/client/bookings` | `api/client/clx-client-bookings.json` | Upcoming bookings | session (client) | session client_id | `{upcoming?, limit?}` | `{ok, bookings:[]}` |
| `POST /webhook/client/replies` | `api/client/clx-client-replies.json` | Recent replies | session (client) | session client_id | `{limit?}` | `{ok, replies:[]}` |
| `POST /webhook/client/activity` | `api/client/clx-client-activity.json` | Activity feed | session (client) | session client_id | `{limit?}` | `{ok, activity:[]}` |
| `POST /webhook/client/billing` | `api/client/clx-client-billing.json` | Tenant billing + portal link | session (client) | session client_id | `{}` | `{ok, billing, portal_url}` |
| `POST /webhook/client/settings` | `api/client/clx-client-settings.json` | Read + write client prefs | session (client) | session client_id | `{notification_email?, daily_digest_opt_in?, booking_alerts_opt_in?}` (POST writes; GET reads) | `{ok, client}` |
| `POST /webhook/client/performance` | `api/client/clx-client-performance.json` | 30-day funnel + rates | session (client) | session client_id | `{}` | `{ok, funnel, totals, rates}` |

### Lead orchestration (the 7 protected v2/v3 production workflows)

These are scheduled, not webhook-triggered (most). They power the core sales engine.

| Workflow | File | Purpose | Trigger |
|----------|------|---------|---------|
| Lead Import | `clx-lead-import.json` | Pull from Google Maps + intake | **ACTIVE** schedule |
| Lead Research v2 | `clx-lead-research-v2.json` | Per-lead Claude research | schedule (production-active) |
| Lead Scoring v2 | `clx-lead-scoring-v2.json` | Score lead 0-100 | schedule (production-active) |
| Campaign Router v2 | `clx-campaign-router-v2.json` | Assign to outreach campaign | schedule (production-active) |
| Outreach Generation v2 | `clx-outreach-generation-v2.json` | Compose personalised email/DM | schedule (production-active) |
| Outreach Sender v2 | `clx-outreach-sender-v2.json` | Send via SMTP/LinkedIn/etc | schedule (production-active) |
| Reply Ingestion v1 | `clx-reply-ingestion-v1.json` | Read reply mailboxes → status | schedule (production-active) |
| Booking v2 | `clx-booking-v2.json` | Calendly webhook → booking row | webhook (production-active) |
| Pipeline Update v2 | `clx-pipeline-update-v2.json` | Stale-lead detection + stats | schedule (production-active) |

> **Don't touch any of these without explicit instruction** ([CLAUDE.md](../../CLAUDE.md) convention).

### Bucket 1 totals

- **9 auth** + **9 admin** + **9 client** + **9 orchestration** = **36 endpoints / workflows live in production**.

---

## Bucket 2 — Built but dormant (JSON exists, not yet activated per-client)

These workflows have full JSON in the repo. Activation is per-client by Mary (set the relevant `_enabled` column on `clients` + flip `active=true` in n8n). The dashboard frontend already has the panel slots reserved per the §-references below.

### Calendar + Daily Plan + Route (§29-§31)

| Endpoint | File | Purpose | Why dormant |
|----------|------|---------|-------------|
| `POST /webhook/clx-no-show-detector` | `clx-no-show-detector-v1.json` | 30-min scan for missed appointments | Twilio SMS credential not bound; per-client `agent_calendar_prefs.no_show_sms_enabled` defaults false |
| `POST /webhook/clx-no-show-sms-recovery` | `clx-no-show-sms-recovery-v1.json` | Compose + send rebook SMS | Same — pending Twilio creds + TESTING_PHONE override removal per client |
| `POST /webhook/clx-reshuffle` | `clx-reshuffle-suggester-v1.json` | Replacement-lead suggestion when slot vacates | Webhook-only; activate when dashboard "Suggest replacement" button wired |
| `POST /webhook/clx-daily-plan` | `clx-daily-plan-generator-v1.json` | Morning task ranking via Claude Haiku | 07:00 schedule disabled; `agent_calendar_prefs` rows must be seeded per agent |
| `POST /webhook/clx-task-classifier` | `clx-task-classifier-v1.json` | Mid-day single-lead reclassification | Ad-hoc only — already works on demand |
| `POST /webhook/clx-appointment-geocoder` | `clx-appointment-geocoder-v1.json` | Nominatim geocode of appointment addresses | 6h schedule disabled; activate per travelling-vertical client |
| `POST /webhook/clx-route-optimizer` | `clx-route-optimizer-v1.json` | Haversine nearest-neighbour route ordering | Per-client `clients.travel_optimization_enabled = false` by default |

### Productivity Tier (§32)

| Endpoint | File | Purpose | Why dormant |
|----------|------|---------|-------------|
| `POST /webhook/activity/record` | `clx-activity-tracker-v1.json` | Log agent activity event (consent-gated) | Tier B per-client price not flipped (`enable_productivity_tier`); per-agent `team_members.productivity_tracking_consent` defaults false |
| `POST /webhook/activity/classifier/run` | `clx-activity-classifier-v1.json` | Batch-classify unclassified events via Claude Haiku | Anthropic credential not bound (heuristic fallback works without it) |
| `POST /webhook/productivity/summary/run` | `clx-daily-summary-generator-v1.json` | 23:00 per-agent daily summary email | TESTING MODE redirect hardcoded to founder email until go-live |

### Listening Intelligence (§33)

| Endpoint | File | Purpose | Why dormant |
|----------|------|---------|-------------|
| `POST /webhook/vapi/transcript-stream` | `clx-vapi-transcript-streamer-v1.json` | Receive Vapi transcript chunks (HMAC-verified) | `VAPI_WEBHOOK_SECRET` env not set; `clients.listening_intelligence_enabled = false` |
| `POST /webhook/transcript/classify` | `clx-transcript-classifier-realtime-v1.json` | Claude Haiku classify intent / sentiment / topics | Anthropic credential not bound |
| `POST /webhook/call/finalized` | `clx-post-call-analyzer-v1.json` | Per-call rollup + Claude Sonnet coaching analysis | Same as above |

### Real-time Closing Script Pop-Ups (§34)

| Endpoint | File | Purpose | Why dormant |
|----------|------|---------|-------------|
| `POST /webhook/script/suggest` | `clx-realtime-script-suggester-v1.json` | Match call state → ranked script suggestions | `clients.realtime_script_suggestions_enabled = false` |
| `POST /webhook/script/learning/run` | `clx-script-learning-loop-v1.json` | 02:00 schedule — recompute `conversion_rate` over 90d | Schedule disabled until ≥ 50 acted-on rows exist |
| `POST /webhook/clx-script-matcher` | `clx-script-matcher-v1.json` | Async dashboard-facing script matcher | Anthropic credential optional (RPC fallback works) |

### Admin Copilot (§22)

| Endpoint | File | Purpose | Why dormant |
|----------|------|---------|-------------|
| `POST /webhook/copilot/query` | `clx-copilot-query-v1.json` | NL → safe SELECT → result | `MARY_MASTER_TOKEN` env must be set; Anthropic credential bound |
| `POST /webhook/copilot/troubleshoot` | `clx-copilot-troubleshoot-v1.json` | NL diagnose error from `scan_errors` | Same |
| `POST /webhook/copilot/platform` | `clx-copilot-platform-v1.json` | Platform Q&A grounded in handbook | Same |
| `POST /webhook/copilot/transcribe` | `clx-copilot-whisper-v1.json` | MediaRecorder audio → Whisper transcript | OpenAI credential must be bound |
| `POST /webhook/crystallux-mcp` | `clx-mcp-tool-gateway.json` | MCP tool dispatch (research_lead, score_lead, scan_city, list_leads, update_lead_status, get_pipeline_stats, check_pipeline_health, etc.) | Backend-only; no UI consumer wired yet |
| `GET /webhook/crystallux-tools` | `clx-mcp-tool-gateway.json` | MCP tool descriptor list | Same |

### Multi-channel outreach (§14)

| Endpoint | File | Purpose | Why dormant |
|----------|------|---------|-------------|
| `POST /webhook/clx-linkedin-outreach-v1` | `clx-linkedin-outreach-v1.json` | Send LinkedIn DM via Unipile | Unipile credential not bound for new clients |
| `POST /webhook/clx-whatsapp-outreach-v1` | `clx-whatsapp-outreach-v1.json` | WhatsApp via Twilio | Twilio WA credential not bound for new clients |
| `POST /webhook/clx-voice-outreach-v1` | `clx-voice-outreach-v1.json` | Voice call via Vapi (DNCL-gated) | Vapi credential not bound for new clients |
| `POST /webhook/clx-voice-result-v1` | `clx-voice-result-webhook-v1.json` | Vapi callback → outcome | Same |
| `POST /webhook/clx-video-outreach-v1` | `clx-video-outreach-v1.json` | Generate Tavus video | Tavus credential not bound for new clients |
| `POST /webhook/clx-video-ready-v1` | `clx-video-ready-v1.json` | Tavus callback → mark video ready | Same |

### Other dormant background workflows

| Workflow | File | Trigger | Why dormant |
|----------|------|---------|-------------|
| Apollo Enrichment | `clx-apollo-enrichment-v1.json` | webhook + 6h schedule | Apollo credential not bound for new clients |
| B2C Discovery v2.1 | `clx-b2c-discovery-v2.1.json` | schedule | Per-client B2C-allowlist row needed |
| Business Signal Detection v2 | `clx-business-signal-detection-v2.json` | schedule | Per-client signal scope |
| City Scan Discovery | `clx-city-scan-discovery.json` | schedule | Webhook trigger via Copilot tool gateway |
| Email Scraper v3 | `clx-email-scraper-v3.json` | schedule | Mailbox creds per client |
| Error Monitor | `clx-error-monitor-v1.json` | schedule | Notification destination per env |
| Follow-Up v2 | `clx-follow-up-v2.json` | schedule | Per-client cadence config |
| Form Intake v1 | `clx-form-intake-v1.json` | webhook `/form-intake` | Per-form-source allowlist |
| Intelligence Upsell Detector | `clx-intelligence-upsell-detector-v1.json` | schedule | Tier-aware; depends on Market Intelligence (§27) |
| Signal Ingestion | `clx-signal-ingestion-v1.json` | schedule | §27 Market Intel, dormant |
| Signal Intelligence | `clx-signal-intelligence-v1.json` | schedule | §27 Market Intel, dormant |
| Stripe Provision v1 | `clx-stripe-provision-v1.json` | webhook `/clx-stripe-provision` | Stripe live creds + Live mode products required |
| Stripe Webhook v1 | `clx-stripe-webhook-v1.json` | webhook `/stripe` | Stripe webhook secret required |
| Verify Dashboard Access | `clx-verify-dashboard-access-v1.json` | webhook `/verify-access` | Pre-Phase-3 server-side role check; superseded by `clxAuth` flow |

### Bucket 2 totals

- **34 dormant endpoints + workflows** with full JSON. Activation is gated on credentials, env vars, or per-client tier flips — not on net-new build.

---

## Bucket 3 — Specced but no workflow JSON exists (net-new build needed)

Each row links the canonical spec source. These are the next-up build items.

### Client Assistant (CLIENT_COPILOT_SPEC)

| Endpoint | Spec source | Purpose | Estimated effort |
|----------|-------------|---------|------------------|
| `POST /webhook/client/copilot/ask` | [CLIENT_COPILOT_SPEC.md](../architecture/CLIENT_COPILOT_SPEC.md) | Tenant-scoped Q&A — session-token auth, parallel context queries (lead stats + bookings + campaigns) → Merge → Claude Sonnet → 1-3 sentence answer | ~200 lines workflow JSON, ~2-4h work |
| `POST /webhook/client/copilot/transcribe` | [CLIENT_COPILOT_SPEC.md](../architecture/CLIENT_COPILOT_SPEC.md) | Tenant-scoped Whisper transcription — mirror `clx-copilot-whisper-v1` with session-token auth instead of master-token | ~100 lines, ~1-2h |

### Behavioral Intelligence (§35)

| Endpoint / workflow | Spec source | Purpose | Estimated effort |
|---|---|---|---|
| `clx-behavioral-scanner-v1` (6h schedule) | [§35.5](../architecture/OPERATIONS_HANDBOOK.md) | Multi-source signal ingestion (BoC + News + LinkedIn + Apollo + Crunchbase) → `record_behavioral_signal` RPC | ~600 lines, ~1-2 days |
| `POST /webhook/behavioral/classify` | §35.5 | Claude Haiku batch-score relevance + sensitivity → PATCH `behavioral_signals` | ~300 lines, ~4h |
| `POST /webhook/behavioral/trigger` | §35.5 | Match signal → archetype → compose outreach via §28 library → auto-send or queue | ~400 lines, ~6-8h |
| `POST /webhook/behavioral/learning/run` (02:00 schedule) | §35.5 | Recompute `behavioral_triggers.conversion_rate` over 90d | ~200 lines, ~2h (mirror §34) |
| `POST /webhook/behavioral/consent-collect` | §35.5 | Lead-supplied intake form → `signal_source = 'lead_supplied'` | ~150 lines, ~2h |
| **Pre-req:** `behavioral_signals` + `client_behavioral_prefs` + `behavioral_triggers` migration | §35.4 | Net-new schema | ~1 day |
| **Pre-req:** vertical archetype seed library (insurance + real estate + dental + consulting + construction + mortgage) | §35.13 | 60-90 archetype rows | ~2-3 days |

### Insurance / Advisor Dashboard schema gaps (depends on Bucket 3 above + new tables)

| Endpoint / workflow | Spec source | Purpose | Estimated effort |
|---|---|---|---|
| `POST /webhook/advisor/overview` | [§2.1 in extracted](insurance-features-extracted.md) | Advisor-role rollup (own book + team if MGA principal) | ~300 lines, ~4-6h |
| `POST /webhook/advisor/leads` | §2.1 | Advisor's own assigned leads (filter by `team_members.id`) | ~200 lines, ~3h |
| `POST /webhook/advisor/policies` | [§2.4](insurance-features-extracted.md) | Lead's policy book + renewal-window list | depends on `policies` table being built first |
| `clx-renewal-window-scanner-v1` | §2.4 | Daily scan for 60d / 30d / 7d renewal windows → fire `insurance.policy_renewal_*d` behavioral signals | ~200 lines, ~3h |
| `POST /webhook/advisor/cross-sell-suggest` | §2.5 | Given a closed policy, surface next-best policy product | depends on `policies` |
| `POST /webhook/advisor/recycle-cold-lead` | §2.6 | Re-enrol Closed-Lost / Not-Interested into a fresh template after N days | ~250 lines, ~4h |
| `POST /webhook/advisor/carrier-compare` | §2.7 | Given prospect needs analysis, return ranked carrier options | depends on `carriers` table (~1 day net-new) |
| `POST /webhook/advisor/group-quote` | §2.8 | Group-benefits intake → comparison PDF | substantial — ~2-3 days incl PDF gen |
| `POST /webhook/advisor/document/upload` + `/list` + `/get` | §2.3 | Compliance documents (KYC / E&O / contracts / carrier) — Cloudflare R2 backed | ~3 endpoints, ~1-2 days incl R2 wiring |
| `POST /webhook/advisor/ce-log` + `/list` + `/expiring` | §2.2 | Sub-agent continuing-education tracking + renewal reminders | ~2-3 endpoints, ~1 day |
| `POST /webhook/advisor/manager-briefing` (07:00 schedule) | §2.12 | Single morning email to MGA principal: rollup + leaderboard + at-risk callouts | ~300 lines, ~4h (mirrors `clx-daily-summary-generator-v1`) |

### MGA Infrastructure (BUSINESS_PLAN §5)

| Endpoint / workflow | Spec source | Purpose | Estimated effort |
|---|---|---|---|
| `POST /webhook/mga/sub-agent-recruit` | BUSINESS_PLAN §5.5 | Recruitment-funnel intake (4 target archetypes: struggling / mid-tier / newly-licensed / retiring) | ~250 lines, ~3-4h |
| `POST /webhook/mga/override-record` | BUSINESS_PLAN §5.4 | Per-policy override commission ledger | depends on `mga_overrides` schema (~1 day) |
| `POST /webhook/mga/carrier-contract-list` + `/upload` | BUSINESS_PLAN §5.6 | Carrier contract management (FSRA + E&O + sub-agent contracts) | depends on §2.3 document-management |
| `POST /webhook/mga/book-transfer` | BUSINESS_PLAN §3.8 (Bucket 3) | Sub-agent book ownership / transfer tracking when an agent leaves | ~200 lines + new schema, ~1 day |

### Crystallux Coach (BUSINESS_PLAN §4 Service 3)

| Endpoint / workflow | Spec source | Purpose | Estimated effort |
|---|---|---|---|
| `POST /webhook/coach/goal-set` | BUSINESS_PLAN §4 Service 3 | Solo-operator goal + tracking | net-new schema + workflow, ~2-3 days |
| `POST /webhook/coach/checkin-weekly` | Same | AI-generated weekly check-in question + capture response | ~200 lines, ~3h |
| `POST /webhook/coach/playbook-fetch` | Same | Industry-specific solo-operator playbook | depends on `coach_playbooks` table (~1 day) |

### Bucket 3 totals

- **~25-30 net-new endpoints** across Client Copilot (2), Behavioral Intelligence (5), Advisor / Insurance (10-12), MGA Infra (4), Coach (3).
- **~5 net-new schema migrations** load-bearing: `behavioral_signals` + `policies` + `carriers` + `compliance_documents` + `sub_agent_ce_log`. Several others described as additive columns to existing tables.

---

## Bucket 4 — Needed for next major phases

Grouped by phase. These are the "what to build next" reference for focused build prompts. Many are restatements of Bucket 3 lines, anchored to the phase that needs them.

### Phase: Stripe + monetisation go-live

| Endpoint / workflow | Status | Purpose | Dependencies |
|---|---|---|---|
| `POST /webhook/clx-stripe-provision` | **dormant Bucket 2** | Customer + subscription create | Stripe Live products created per [STRIPE_PRODUCTS_SPEC.md](../STRIPE_PRODUCTS_SPEC.md); webhook secret in env |
| `POST /webhook/stripe` | **dormant Bucket 2** | Subscription + invoice events router | `STRIPE_WEBHOOK_SECRET` env; 6 events configured |
| `POST /webhook/billing/portal-session-create` | 🔴 net-new Bucket 4 | Mint a one-shot Stripe Customer Portal session URL per client | Stripe Customer Portal configured; `clx-stripe-provision-v1` already has the placeholder URL stub to swap out |
| `POST /webhook/billing/invoice-resend` | 🔴 net-new Bucket 4 | Per-client manual resend of last invoice | Stripe API binding |
| `POST /webhook/billing/dunning-soft-cancel` | 🔴 net-new Bucket 4 | After N failed-payment days, soft-cancel + email per [PAYMENT_FOLLOW_UP.md](../operations/PAYMENT_FOLLOW_UP.md) | None (`clx-stripe-webhook-v1` already detects `invoice.payment_failed`) |

### Phase: Email infrastructure (Postmark for transactional)

Currently auth uses SMTP-via-Gmail in `clx-auth-magic-link.json` + `clx-auth-password-reset-request.json`. Production-grade transactional email needs Postmark.

| Endpoint / workflow | Status | Purpose | Dependencies |
|---|---|---|---|
| `clx-email-postmark-send` | 🔴 net-new Bucket 4 | Generic transactional send (welcome, reset, magic, billing alerts, daily digest) | Postmark account + API token; sender domains verified |
| `POST /webhook/email/template-render` | 🔴 net-new Bucket 4 | Render a named template + vars → return HTML + text | Template library schema (`email_templates` table) |
| Refactor 4 auth workflows to use Postmark sender | 🟡 modify existing | Auth emails currently SMTP — switch to Postmark for delivery + bounce tracking | Above two land first |

### Phase: Video pipeline (Tavus is partial; HeyGen / Synthesia future)

| Endpoint / workflow | Status | Purpose | Dependencies |
|---|---|---|---|
| `POST /webhook/clx-video-outreach-v1` | **dormant Bucket 2** | Tavus video generation (already built) | Tavus credential per client |
| `POST /webhook/clx-video-ready-v1` | **dormant Bucket 2** | Tavus callback → mark video ready | Same |
| `POST /webhook/video/heygen-render` | 🔴 net-new Bucket 4 | HeyGen alternative to Tavus (better lip-sync, higher per-render cost) | HeyGen credential; `video_renders.provider` column |
| `POST /webhook/video/heygen-ready` | 🔴 net-new Bucket 4 | HeyGen callback | Same |
| `POST /webhook/video/avatar-train` | 🔴 net-new Bucket 4 | Per-client AI avatar training intake | Provider-specific |

### Phase: WhatsApp / SMS (Twilio is partial)

| Endpoint / workflow | Status | Purpose | Dependencies |
|---|---|---|---|
| `POST /webhook/clx-whatsapp-outreach-v1` | **dormant Bucket 2** | WhatsApp send via Twilio (already built) | Twilio WA credential per client |
| `POST /webhook/clx-no-show-sms-recovery` | **dormant Bucket 2** | SMS rebook (already built) | Twilio SMS credential per client |
| `POST /webhook/twilio/sms-inbound` | 🔴 net-new Bucket 4 | Inbound SMS reply ingestion → lead_status update | Twilio webhook configured per number |
| `POST /webhook/twilio/whatsapp-inbound` | 🔴 net-new Bucket 4 | Inbound WA reply ingestion | Same |

### Phase: Calendar (Cal.com migration from Calendly)

| Endpoint / workflow | Status | Purpose | Dependencies |
|---|---|---|---|
| `POST /webhook/clx-booking-v2` | **production-active** | Calendly webhook → booking row | Per-client Calendly account |
| `POST /webhook/calcom/booking-created` | 🔴 net-new Bucket 4 | Cal.com event → booking row (parity with Calendly) | Cal.com per-client API token |
| `POST /webhook/calcom/booking-cancelled` | 🔴 net-new Bucket 4 | Cancellation → trigger §29 reshuffle | Same |
| `POST /webhook/calcom/booking-rescheduled` | 🔴 net-new Bucket 4 | Reschedule → update appointment_log | Same |

### Phase: Advisor Dashboard (insurance vertical first; universal engine)

See Bucket 3 for the full list. Sequenced phase priorities:

1. `policies` migration + `clx-renewal-window-scanner-v1` (unlocks behavioral intel category #7 for insurance)
2. `POST /webhook/advisor/overview` + `/leads` + `/policies` (3 read endpoints to power the new advisor-role pages)
3. `compliance_documents` migration + 3 document-management endpoints (KYC / E&O / contracts)
4. `sub_agent_ce_log` migration + 3 CE-tracking endpoints
5. MGA principal supervisor rollup (`/webhook/advisor/manager-briefing` daily email + dashboard panel)

### Phase: Behavioral Intelligence (§35)

See Bucket 3. Sequenced phase priorities (per OPERATIONS_HANDBOOK §35.13):

1. Schema migration (`behavioral_signals` + `client_behavioral_prefs` + `behavioral_triggers`)
2. `clx-behavioral-scanner-v1` (Tier 1 sources only, MVP categories 1/2/7/10)
3. `clx-behavioral-classifier-v1` (Claude Haiku scoring)
4. `clx-behavioral-trigger-v1` (compound match + outreach compose, queue mode only — no auto-send for v1)
5. Per-vertical archetype seed (insurance first, then real estate, dental, consulting, mortgage, construction)
6. Auto-send mode toggle + sensitivity gating tests
7. Tier 2 sources (Google News + Crunchbase) → categories 5/6
8. Sensitive personal category (full category 1) with high-sensitivity gating tests
9. Categories 3 / 4 / 8 / 9 (industry / sports / financial / geographic)
10. Learning loop activation (`clx-behavioral-learning-loop-v1`)

---

## Summary stats

| Metric | Count |
|--------|-------|
| **Total workflow JSON files** | 50 |
| **Total webhook + schedule entries** | 76 |
| **Bucket 1 — built and live** (verified production endpoints + the 9 protected orchestration workflows) | **36** |
| **Bucket 2 — built but dormant** (JSON ready, awaiting credentials / per-client activation) | **34** |
| **Bucket 3 — specced but no JSON yet** (across Client Copilot, Behavioral Intel, Advisor, MGA, Coach) | **~28** |
| **Build effort to ship Stripe monetisation phase** | **3-5 net-new endpoints** + Live products + Postmark migration |
| **Build effort to ship Email infrastructure phase** | **2-3 net-new + 4 auth refactors** |
| **Build effort to ship Video pipeline phase** | **3-5 net-new** if expanding beyond Tavus |
| **Build effort to ship Behavioral Intelligence MVP** | **5 workflows + 1 migration + 1 archetype seed library** (~5-7 days) |
| **Build effort to ship Advisor Dashboard MVP** | **10-12 endpoints + 3-5 schema migrations** (~10-15 days) |
| **Build effort to ship MGA Infrastructure** | **4 endpoints + 2 schemas** (~5-7 days), depends on Advisor + Document Management |
| **Build effort to ship Crystallux Coach** | **3 endpoints + 1 schema** (~3-5 days, lowest priority) |

## What's the next thing on the 50 workflows?

Direct answer to your question:

1. **Most urgent: activate the Bucket 2 dormant ones that don't need code.** `clx-stripe-provision-v1` + `clx-stripe-webhook-v1` are ready to go — all that's left is creating the Stripe Live products per [STRIPE_PRODUCTS_SPEC.md](../STRIPE_PRODUCTS_SPEC.md) and dropping the webhook secret into the n8n env. Ship monetisation in a day.
2. **Second most urgent: build the Client Assistant workflows** ([CLIENT_COPILOT_SPEC.md](../architecture/CLIENT_COPILOT_SPEC.md)). The frontend FAB ships in commit `7c9f64e` and currently shows "not yet activated." 2 net-new workflows, ~5h work, unlocks the client-side ✦.
3. **Third: ship Behavioral Intelligence MVP** ([§35](../architecture/OPERATIONS_HANDBOOK.md)). 5 workflows + 1 migration. The differentiator. ~5-7 days.
4. **Fourth: Advisor Dashboard build phase** with `policies` table + renewal-window scanner first ([insurance-features-extracted §2.4](insurance-features-extracted.md)).

Everything else (HeyGen, Cal.com, MGA infra, Coach) is sequenceable behind those four. Mary picks the order.
