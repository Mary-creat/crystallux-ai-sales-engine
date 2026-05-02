# Phase 2a — Broker Revenue Track (Mary the Broker)

**Highest priority track.** This is the path to revenue Mary already
has access to — her insurance broker book — using the 2A engine to
compress the time from "lead identified" to "appointment booked".

## End-to-end flow

```
┌──────────────────────────────────────────────────────────────────────┐
│ ATTENTION ────────────────────────────────────► APPOINTMENT          │
│                                                                      │
│ ① Lead Finder              (existing, schedule-triggered)            │
│   clx-b2c-discovery-v2.1                                             │
│   clx-lead-research-v2     ← runs every 15 min, polls leads table    │
│   clx-lead-scoring-v2                                                │
│   clx-business-signal-detection-v2                                   │
│                              │                                       │
│                              ▼ writes leads row                      │
│ ② Content Generator        (NEW — Phase 2a Component 1)              │
│   Mary triggers manually:  POST /content/generate                    │
│     persona_key: mary_broker                                         │
│     track:       broker                                              │
│     source_lead_id: <the lead's uuid>                                │
│     topic:       'cash-value-life-insurance-for-young-parents'       │
│                              │                                       │
│                              ▼ writes content_pieces row             │
│                              │  + Tavus job submitted                │
│                              │  + status=generating                  │
│                              │                                       │
│                              ▼ ~5 min later (polling)                │
│                              │  status=ready, tavus_video_url set    │
│                              │                                       │
│ ③ Bridge into outreach     (state-driven, no new workflow)           │
│   -- Persona/content linkage lives in the new junction table;        │
│   -- leads schema is NOT modified (strict additive).                 │
│   INSERT INTO lead_persona_links (lead_id, persona_id, content_piece_id) │
│   VALUES (<lead_id>,                                                 │
│           (SELECT id FROM personas WHERE persona_key='mary_broker'), │
│           <piece_id>);                                               │
│   -- Only writes to existing leads columns (data, not schema):       │
│   UPDATE leads SET                                                   │
│     video_url   = (SELECT tavus_video_url FROM content_pieces        │
│                     WHERE id = <piece_id>),                          │
│     lead_status = 'Campaign Assigned'                                │
│    WHERE id = <lead_id>                                              │
│                              │                                       │
│                              ▼                                       │
│ ④ Outreach Engine          (existing, schedule-triggered)            │
│   clx-outreach-generation-v2  ← runs every 15 min                    │
│      composes outreach copy referencing video_url                    │
│   clx-outreach-sender-v2      ← runs every 60 min                    │
│      sends via channel (email default; LinkedIn/WhatsApp on overlay) │
│                              │                                       │
│                              ▼                                       │
│ ⑤ Follow-Up Engine         (existing)                                │
│   clx-follow-up-v2           ← multi-touch cadence                   │
│   clx-reply-ingestion-v1     ← captures inbound replies              │
│                              │                                       │
│                              ▼                                       │
│ ⑥ Booking                  (existing)                                │
│   clx-booking-v2             ← Calendly link in CTA                  │
│                              ↳ 48h-no-booking → ALREADY WIRED to     │
│                                clx-video-outreach-v1 fallback        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Why this design (vs. the brief's original framing)

The brief described Component 1 "calling" `clx-outreach-sender-v2`
with a video URL. The codebase reality (see Q2 in
[`99-open-questions.md`](./99-open-questions.md)) is that
`clx-outreach-sender-v2` is **schedule-triggered**, not
webhook-triggered. There's no endpoint to call.

The right pattern — and the pattern the codebase already uses
everywhere else — is **state-driven coordination**: Component 1
updates the `leads` row, and Outreach Sender picks it up on the next
60-minute tick. Total latency added: at most 60 min from "video ready"
to "outreach fires".

A small bridge step (③ above) is needed because Component 1 doesn't
know about Outreach Sender's input contract (`lead_status='Campaign
Assigned'`). For Phase 2a Mary does this manually for the first 5–10
broker leads — it's literally one Supabase SQL query. In Phase 2b a
"link content piece to lead" webhook can automate this, but it's
intentionally manual for the first cohort so Mary can review each
piece before it goes to outreach.

## Persona setup before Week 1

```sql
UPDATE personas SET
  tavus_replica_id      = '<MARY_REPLICA_ID>',
  niche_overlay_default = 'insurance_broker',
  prompt_framing        = $$
You are Mary, a licensed Ontario life insurance broker with 8+ years
of experience. You speak directly to a single prospect, by name, in
60–90 seconds. Your tone is warm, knowledgeable, never salesy. Always
end with a clear call to book a 15-minute discovery call. Avoid
jargon (use "permanent" not "whole-of-life", "tax-free growth" not
"cash value accumulation" until you've earned it).
$$,
  audience_description  = 'Ontario residents 30–55, family-stage,
income $80k+, currently underinsured or with stale group coverage.'
WHERE persona_key = 'mary_broker';
```

## Sample topics — life insurance scenarios

These become `content_pieces.topic` values. Each generates one
60–90s video.

| Topic | Audience | Hook |
|---|---|---|
| `permanent-vs-term-clarified` | Young parents 30–40 | "Most people are quietly choosing wrong, and only realize at age 50." |
| `cash-value-life-insurance-as-tax-shelter` | Self-employed, $150k+ | "Your accountant probably hasn't told you about this — here's why." |
| `group-coverage-myth` | Anyone with employer benefits | "Your group plan disappears the day you change jobs. Yours doesn't have to." |
| `30-year-mortgage-protection` | New homeowners | "Here's what happens if life changes mid-mortgage and your spouse is alone with the payment." |
| `business-owner-key-person-coverage` | SMB founders | "If you got hit by a bus tomorrow, here's what your business owes the bank — and how that gets resolved." |

## Sample topics — RIBO scenarios

| Topic | Audience | Hook |
|---|---|---|
| `ribo-vs-broker-explained` | Confused first-time buyers | "RIBO, broker, agent — three names you've heard, here's why it matters which one is on your policy." |
| `home-insurance-claim-walkthrough` | New homeowners | "Step-by-step what actually happens when you file — most people get this wrong on day one." |
| `commercial-coverage-for-trades` | Construction / trades | "Subcontractor liability claim cost a friend of mine $80k last spring. Here's what nobody tells you about your CGL policy." |

## Per-lead personalization vector

For broker-track personalized cuts, the script composer receives:
- The lead's `full_name`, `city`, `industry`, `job_title` from the
  `leads` row (joined via `source_lead_id`)
- Mary's persona prompt framing
- The niche overlay's `video_script_template`
- The topic + brief from the request

Result: a 60–90s script that addresses the lead by name (when
available), references their city/industry naturally, and frames the
chosen topic from the broker persona's POV.

## Week 1 success criteria

- [ ] Tavus replica trained (Mary)
- [ ] Migration applied (Mary, after morning Q&A review)
- [ ] Persona row updated with replica_id and prompt_framing (Mary)
- [ ] First content_pieces row generated and reaches status='ready'
- [ ] First lead manually bridged (row in `lead_persona_links` + `leads.lead_status='Campaign Assigned'`)
- [ ] Outreach Sender activated and processes the lead on next tick
- [ ] First reply received (or first booking landed)
- [ ] Tavus minutes consumed reconciled against persona_usage_log

## Out of scope for Week 1

- Multi-platform distribution (builder track — Week 2)
- Automated content_piece → lead bridging (Phase 2b)
- Engagement metric polling (Phase 2b)
- Stripe metering for broker track (no client billing — Mary is broker)
