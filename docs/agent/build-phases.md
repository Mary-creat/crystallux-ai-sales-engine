# AI Sales Agent — build phases

> **Estimated total:** 30-45 days of focused engineering across 6 sub-phases.
> **Dependency map:** Phase 3 sub-phases run roughly in parallel after the foundation (this session); each can ship independently.
> **Universal:** every phase delivers across all Crystallux verticals — no vertical-specific code unless required by regulatory primitives.

## Foundation (this session — DONE)

- ✓ Schema: [`db/migrations/ai-agent-schema.sql`](../../db/migrations/ai-agent-schema.sql) — 10 tables + pgvector + RLS
- ✓ Vision doc: [`AGENT_VISION.md`](AGENT_VISION.md)
- ✓ Role enum expansion: `agent` role added in [`db/migrations/role-enum-update.sql`](../../db/migrations/role-enum-update.sql)
- ✓ Privacy + cost + escalation patterns documented

## Phase 3a — Voice agent (5-7 days)

**Goal:** outbound + inbound voice calls. Replaces a human SDR for cold-call follow-up + reschedules + first-touch qualification.

### Vendor recommendation: Vapi

**Vapi (vapi.ai)** vs Retell — choosing Vapi for these reasons:

| Dimension | Vapi | Retell |
|---|---|---|
| Per-minute cost | ~$0.05-0.07 | ~$0.07-0.09 |
| n8n integration ease | HTTP webhooks (clean) | HTTP webhooks (clean) |
| Latency | sub-second turn-taking | sub-second turn-taking |
| Voice quality | ElevenLabs + Cartesia + OpenAI options | OpenAI + ElevenLabs |
| Custom voice clone | yes | yes |
| Inbound + outbound | yes | yes |
| Existing wiring | `clx-vapi-transcript-streamer-v1` already coded for §33 Listening Intel | nothing |

The deciding factor is the existing `clx-vapi-transcript-streamer-v1` workflow — listening intel is already wired for Vapi, so reusing the same vendor for the agent's voice halves the integration surface.

### Workflows to build

1. `workflows/api/agent/clx-agent-voice-place-call-v1.json` — webhook to start an outbound call. Reads `agent_personalities` for tone + voice id, builds the system prompt with tenant facts + the `agent_decisions.reasoning`, hands off to Vapi.
2. `workflows/api/agent/clx-agent-voice-inbound-v1.json` — Vapi inbound webhook. Looks up the lead by phone number, loads memory, hands off to Vapi assistant config.
3. `workflows/api/agent/clx-agent-voice-finalized-v1.json` — Vapi end-of-call webhook. Writes `agent_actions` (status complete / failed) + `agent_costs` row + memory summary.

Reuses existing §33 transcript streaming + post-call analyzer.

### Deliverables

- 3 workflow JSONs
- Updated `agent_personalities.custom_voice_id` populated per tenant once Mary records voice clone (optional — defaults to Vapi stock voice tuned by tone setting)
- Cal.com integration for "book a meeting at the end of the call" (depends on Phase 3a Calendar sub-task below)
- Smoke test: place a test outbound call to a sandbox number, confirm transcript + outcome lands in DB

## Phase 3b — WhatsApp + SMS conversation agent (5-7 days)

**Goal:** Twilio-powered two-way conversations on WhatsApp + SMS. The agent receives an inbound, decides if/how to respond, sends, and continues the thread until escalation or close.

### Workflows to build

1. `workflows/api/agent/clx-agent-whatsapp-inbound-v1.json` — Twilio inbound webhook (HMAC-verified). Looks up lead by phone, loads conversation thread, calls Claude, decides action, sends.
2. `workflows/api/agent/clx-agent-sms-inbound-v1.json` — same pattern for SMS.
3. `workflows/api/agent/clx-agent-whatsapp-send-v1.json` — outbound, called by the trigger workflow when behavioral intel fires or a scheduled action runs.
4. `workflows/api/agent/clx-agent-sms-send-v1.json` — outbound SMS.

The two send workflows are mostly thin wrappers over Twilio. The two inbound workflows do the heavy lift — they're the conversation-engine entry points.

### Dependencies

- Twilio account + WA Business approval (1-2 weeks external; see external-dependencies-checklist).
- Reuses existing `clx-whatsapp-outreach-v1` + `clx-no-show-sms-recovery-v1` as send-path examples (those are dormant in source but production-ready).

## Phase 3c — Email conversation agent (3-5 days)

**Goal:** the agent reads inbound email replies, threads them, decides next action, sends back through Postmark.

### Workflows to build

1. `workflows/api/agent/clx-agent-email-inbound-v1.json` — IMAP polling or Postmark inbound parsing webhook. Threads the reply against the existing `agent_conversations` row (matched by Postmark message id or in-reply-to header).
2. `workflows/api/agent/clx-agent-email-send-v1.json` — outbound through `clx-email-send` from this session.

Most outbound email is already sent via the Outreach Sender v2 production workflow — the agent layer adds **per-message decisioning** (vs the current schedule-driven outbound).

## Phase 3d — Social media agent (7-10 days)

**Goal:** Instagram + Facebook + LinkedIn + X DMs and comments.

### Workflows to build

1. Per-platform inbound webhook (Meta Graph webhook for IG/FB; Unipile for LinkedIn; X API for X). 4 workflows.
2. Per-platform send + reply workflows. 4 more.
3. A unifying "platform router" that takes a generic agent decision and dispatches to the right platform send. 1 more.

### Dependencies

- Meta Developer account + per-platform app (1-2 weeks approval each).
- Unipile already integrated for outreach — extend.
- X API access tier (paid since 2023).

This is the longest sub-phase because each platform has its own auth dance and rate limits.

## Phase 3e — Decision engine + memory layer (5-7 days)

**Goal:** the brain. The thing that turns "an event happened" into "agent decides + acts."

### Workflows to build

1. `workflows/api/agent/clx-agent-decide-v1.json` — universal decision endpoint. Triggered on every inbound message (from any channel) or every behavioral signal classification. Loads context, calls Claude Sonnet, writes `agent_decisions` row, dispatches to the right channel send workflow if action is `send_*`.
2. `workflows/api/agent/clx-agent-memory-write-v1.json` — webhook for committing a new `agent_memory` row. Embeds via OpenAI `text-embedding-3-small`, computes importance score, writes.
3. `workflows/api/agent/clx-agent-memory-search-v1.json` — internal query endpoint. Given (lead_id, query_text), returns top-K similar memories. Used inside the decide workflow.
4. `workflows/api/agent/clx-agent-summarize-conversation-v1.json` — at conversation end (or every N messages), summarise + embed → memory.

### Critical infrastructure

- Embedding cost: ~$0.02 per 1M tokens. At 30 clients × 100 leads × 5 conversations × 200 tokens = 300K tokens/mo per client = $0.18/mo per client. Negligible.
- Decision cost: Claude Sonnet ~$0.003 per decision. At 30 clients × 100 messages/day = 3,000 decisions/day = ~$10/day = $300/mo platform-wide. Margin is the headline.

## Phase 3f — Live monitoring dashboard (5-7 days)

**Goal:** humans can see what the agent is doing in real time; humans can take over.

### UI work

- New admin page: `admin-dashboard/pages/agent.html` (system view across all clients).
- New client page: `client-dashboard/pages/agent.html` (own tenant only).
- Real-time stream of `agent_decisions` + `agent_actions` (Supabase Realtime channel).
- Active-conversations panel with "take over" toggle (flips `agent_conversations.agent_active = false`).
- Escalations-pending list with claim + resolve buttons.
- Cost meter (today / week / month) with vendor breakdown.
- Daily summary email already shipped this session (`agent-daily-summary` template) — wire the daily generator workflow.

### Workflows to build

1. `workflows/api/agent/clx-agent-takeover-v1.json` — flip `agent_active = false` on a conversation; agent stops sending.
2. `workflows/api/agent/clx-agent-resume-v1.json` — flip `agent_active = true` again.
3. `workflows/api/agent/clx-agent-daily-summary-generator-v1.json` — 23:00 schedule; computes per-client `agent_performance` row + sends daily email per the template.

## Sequencing recommendation

Run sub-phases in this order for maximum compounding value:

1. **3a (Voice)** first — voice is the single biggest "wow" moment for tenants and proves the architecture end-to-end with one channel.
2. **3e (Decision engine)** in parallel — the brain is needed before scaling channels.
3. **3b (WhatsApp/SMS)** next — high-ROI channel for service verticals.
4. **3c (Email)** next — the existing outreach already handles email *send*; this adds *conversation*.
5. **3f (Monitoring dashboard)** in parallel with 3c — humans need the surface before social rolls out.
6. **3d (Social)** last — most external-dependency overhead, fewest leads come from social initially.

## Cost ceiling at scale

At 30 clients × 100 leads each × moderate activity:

- Voice (Vapi): 5,000 minutes/mo × $0.06 = $300/mo
- WhatsApp + SMS (Twilio): 50K messages × $0.005 = $250/mo
- Email (Postmark): 100K sends × $0.0015 = $150/mo
- Claude Sonnet decisions: ~$300/mo
- Embeddings: ~$5/mo
- pgvector storage: included in Supabase

**~$1,000/mo platform cost to deliver $30K-$60K of MRR if Behavioral Intelligence is the value-prop.** Same margin profile as §35.

## Cross-references

- Vision: [`AGENT_VISION.md`](AGENT_VISION.md)
- Schema: [`db/migrations/ai-agent-schema.sql`](../../db/migrations/ai-agent-schema.sql)
- External deps: [`docs/setup/external-dependencies-checklist.md`](../setup/external-dependencies-checklist.md)
- Behavioral intel feeds the agent: [`OPERATIONS_HANDBOOK.md`](../architecture/OPERATIONS_HANDBOOK.md) §35
- Listening intel powers the voice channel: §33
- Closing intel + real-time scripts feed message composition: §28 + §34
