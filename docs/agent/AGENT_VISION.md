# AI Sales Agent — vision

> **The thesis:** every Crystallux tenant gets one autonomous AI Sales Agent that runs the entire sales operation 24/7 across every channel — voice (in/out), WhatsApp, SMS, email, social. Replaces the need for a human VA or SDR team. Universal across every Crystallux vertical.

## What the agent does

The agent is the **system actor** that bridges Crystallux's intelligence layers (§27 Market Intel, §28 Closing Intel, §32 Productivity, §33 Listening Intel, §34 Real-time Scripts, §35 Behavioral Intel) and **executes** on them across channels — without a human in the loop unless escalation rules fire.

### Autonomous worker philosophy

The agent operates like a tireless junior SDR with infinite context:

- **Thinks first, acts second.** Every action is preceded by an `agent_decisions` row with reasoning + context_used + confidence_score. The full chain of thought is auditable.
- **Channel-native.** A WhatsApp reply is composed differently than an email follow-up, which is different from a voice script. The agent uses the right register for each.
- **Patient.** Quiet hours, weekly per-lead caps, weekend rules, holiday rules — all configurable per client. The agent never bombards.
- **Deferential to humans.** Humans always have priority. The moment a human takes over a conversation (`agent_conversations.agent_active = false`), the agent stops sending and just listens. It can resume later if the human releases control.
- **Cost-aware.** Every action writes to `agent_costs` so the platform tracks margin per client per channel. The agent will pause if monthly cost exceeds a per-client cap.

## Channels it operates on

Universal channel set — every channel a B2B service-vertical seller might touch:

| Channel | Direction | Vendor today | Phase |
|---------|-----------|--------------|-------|
| Voice (calls) | inbound + outbound | Vapi or Retell | 3a |
| WhatsApp | inbound + outbound | Twilio + Meta WA Business | 3b |
| SMS | inbound + outbound | Twilio | 3b |
| Email | inbound + outbound | Postmark out, IMAP in | 3c |
| Instagram (DM + comments) | inbound + outbound | Meta Graph API | 3d |
| Facebook (DM + comments) | inbound + outbound | Meta Graph API | 3d |
| LinkedIn (DM) | inbound + outbound | Unipile | 3d |
| X / Twitter (DM + replies) | inbound + outbound | X API | 3d |
| Calendar | book / reschedule / cancel | Cal.com (or Calendly) | 3a |

Per-client per-channel toggles live in `agent_channels_enabled`. A tenant who only does email + LinkedIn enables only those two; the agent ignores the rest.

## Decision-making capabilities

Every event the agent observes (signal detected, message received, scheduled time elapsed) routes through a decision pipeline:

1. **Gather context** — pull `lead`, `behavioral_signals`, `agent_memory` (semantic search via pgvector), recent `agent_conversations` for this lead, `client.niche_overlay` rules, `agent_personalities` tone tuning, `agent_schedules` time rules.
2. **Choose action** — Claude Sonnet decides one of: `send_message` (with channel + composed text), `place_call`, `reschedule`, `escalate`, `wait`, `mark_unresponsive`, `request_human_review`.
3. **Sanity-check** — apply hard rules: quiet hours? Weekly cap reached? CASL footer present? DNCL clean? Sensitivity gating (no auto-send on high-sensitivity behavioral triggers)?
4. **Execute** — write `agent_decisions` row, then `agent_actions` row, then call the channel-specific workflow (Twilio / Vapi / Postmark / Unipile / etc.).
5. **Observe outcome** — when the channel returns a delivery receipt or a reply lands, update `agent_actions.status` + `agent_actions.outcome` + downstream `agent_decisions.outcome`.
6. **Learn** — when the lead's `lead_status` changes to `Booked` or `Closed Lost`, write a `agent_memory` row of type `successful_close_pattern` or `objection_history` capturing what worked / didn't.

## Memory + learning

`agent_memory` is the long-term semantic memory layer:

- **Type `conversation_summary`** — every N exchanges or every conversation end, the agent summarises and embeds the conversation.
- **Type `behavioral_pattern`** — "this lead replies fastest at 9am, prefers WhatsApp over email."
- **Type `preference`** — "this lead asked us to call instead of email."
- **Type `objection_history`** — what objections came up + how they were handled.
- **Type `successful_close_pattern`** — for closed-won leads, what worked. Feeds Phase 3e learning loop.

Search is via cosine similarity (`vector(1536)` ivfflat index on `embedding`). At decision time the agent asks "what's similar to this situation?" and pulls the top-K memories as context.

Embeddings: OpenAI `text-embedding-3-small` (1536-dim, $0.02 per 1M tokens) — we don't ship a custom embedding model. Cost is negligible at our scale.

## Human escalation logic

The agent escalates when:

- **Sensitivity gate fired** — high-sensitivity behavioral triggers (bereavement, illness, divorce, new baby) never auto-send.
- **Confidence too low** — Claude returns `confidence_score < 0.6` on a decision.
- **Repeated failure** — 3 consecutive `agent_actions.status = failed` for the same lead/channel.
- **Compliance flag** — anything that touches FSRA / RIBO / regulated topics in regulated verticals.
- **Customer asked for a human** — any inbound message containing escalation language ("speak to someone", "human", "manager", "stop").
- **Cost cap approaching** — within 10% of the monthly per-client cost cap.

`agent_escalations` rows route to the right `target_role` (advisor / supervisor / mga_principal / admin / compliance_officer per `agent_personalities.escalation_rules`), surface in the dashboard "Pending your attention" panel, and email the assigned user via the daily summary template.

## Per-client customization

Every tenant gets:

- **`agent_personalities`** — voice tone, formality, language, signature, intro template, prohibited topics, custom voice id (ElevenLabs / Vapi clone if Mary records).
- **`agent_channels_enabled`** — which channels are on, with channel-specific config (Twilio number, social handle, oauth token id).
- **`agent_schedules`** — quiet hours, daily cap, per-lead weekly cap, weekend, holidays.
- **`niche_overlay.outreach_voice`** — already-existing per-vertical Claude prompt scaffolding the agent uses.

Admins can fine-tune any of these via the existing settings pages. New: an `Agent` page in the admin dashboard for live monitoring + override.

## Privacy and consent

The agent inherits the platform's compliance primitives:

- **CASL** — every email send + SMS send carries the unsubscribe footer + sender identification.
- **DNCL** — voice calls short-circuit if the lead has `do_not_contact = true`.
- **PIPEDA** — `agent_memory` retention is 18 months active + archived; per-lead delete request results in cascade delete.
- **Two-party consent** — voice recording requires explicit consent (CRTC). The agent reads the disclosure script verbatim before any recording starts.
- **Sensitivity gating** — see escalation logic above. Lives in code, not just policy.

## Observability — what the human sees

Two surfaces:

**Live monitoring dashboard** (Phase 3f):
- Active conversations (per client) with channel + lead + last message preview + agent_active toggle
- Escalations pending acknowledgement
- Today's actions feed (every send + call + decision in real time)
- Cost meter (today / this week / this month) with vendor breakdown
- Agent decision log (the reasoning trail)

**Daily summary email** (template `agent-daily-summary` already shipped this session):
- Messages sent / replies received / meetings booked / new leads
- Coaching flag (e.g., "low reply rate this week — consider adjusting tone")
- Pending-attention list with deep links

## What this is NOT

- Not a generic LLM agent. Every decision is grounded in pre-computed tenant facts (signals, history, schedule rules) — no free-form web browsing.
- Not a human replacement for closers. The agent qualifies + nurtures + books; the licensed human closes.
- Not opt-in by default. Every channel + every category is OFF until the tenant enables it. Senior call: bias the system toward inaction; humans must explicitly authorize autonomy.
- Not vertical-specific. Same engine serves every Crystallux vertical. Tone and prohibited topics adjust via `agent_personalities.vertical_context`.

## Cross-references

- Schema: [`db/migrations/ai-agent-schema.sql`](../../db/migrations/ai-agent-schema.sql)
- Build phases: [`docs/agent/build-phases.md`](build-phases.md)
- Roles: [`docs/architecture/ROLES.md`](../architecture/ROLES.md) — see `agent` role
- Behavioral intel: [`OPERATIONS_HANDBOOK.md`](../architecture/OPERATIONS_HANDBOOK.md) §35
- Listening intel: §33
- Real-time scripts: §34
