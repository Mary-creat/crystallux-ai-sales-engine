# Phase 2a — 2A Engine Overview

**Friction AI = remove friction between Attention and Appointments.**

Crystallux's job is to compress the gap between a prospect first
noticing you and a calendar booking landing on your screen. The 2A
Engine is the runtime that does this end-to-end. Phase 2a adds the
**first** component — Content Generator — and a persona layer that
threads through every existing component without modifying any of
them.

> **Read first:** [`99-open-questions.md`](./99-open-questions.md). Tonight's
> scaffolding makes seven recommended-path assumptions that need
> Mary's explicit confirmation before any of this lands in n8n.

## The five components

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                    Friction AI / 2A Engine                       │
  │                                                                  │
  │  ATTENTION ─────────────────────────────────────► APPOINTMENT    │
  │                                                                  │
  │  ┌──────────┐  ┌────────┐  ┌──────────┐  ┌─────────┐  ┌───────┐  │
  │  │ 1.       │  │ 2.     │  │ 3.       │  │ 4.      │  │ 5.    │  │
  │  │ Content  │  │ Lead   │  │ Outreach │  │Follow-Up│  │Booking│  │
  │  │ Gen      │  │ Finder │  │ Engine   │  │ Engine  │  │       │  │
  │  │ (NEW)    │  │ (existing) │ (existing)│(existing)│  │(exist)│  │
  │  └──────────┘  └────────┘  └──────────┘  └─────────┘  └───────┘  │
  │                                                                  │
  │  ──────────────── persona_id flows through all ────────────────  │
  └──────────────────────────────────────────────────────────────────┘
```

Only Component 1 is new in Phase 2a. Everything else already exists in
the repo and is being **extended additively** via:
- `persona_id` columns added to existing tables (nullable, never replacing
  any existing field)
- A registry pattern (`distribution_platforms`) so new content-distribution
  platforms are config rows, not new code paths

---

## Component map (existing → file)

### Component 2: Lead Finder
Finds new leads, scores them, signals worth pursuing.

| Workflow | Status | Trigger | Role |
|---|---|---|---|
| `clx-b2c-discovery-v2.1` | **active** (PROTECTED) | schedule | B2C lead discovery |
| `clx-lead-research-v2` | **active** (PROTECTED) | schedule | Per-lead research/enrichment |
| `clx-lead-scoring-v2` | **active** (PROTECTED) | schedule | Score leads for prioritization |
| `clx-business-signal-detection-v2` | **active** (PROTECTED) | schedule | Detect buying signals |
| `clx-city-scan-discovery` | dormant | schedule | City-level lead scan |
| `clx-apollo-enrichment-v1` | dormant | webhook (`clx-apollo-enrichment-v1`) | Apollo data enrichment |

### Component 3: Outreach Engine
Sends initial outreach across channels.

| Workflow | Status | Trigger | Role |
|---|---|---|---|
| `clx-outreach-generation-v2` | dormant | schedule (15 min) | Compose outreach copy |
| `clx-outreach-sender-v2` | dormant | schedule (60 min) | Send composed outreach |
| `clx-campaign-router-v2` | **active** (PROTECTED) | schedule | Route lead → campaign |
| `clx-linkedin-outreach-v1` | dormant | webhook | LinkedIn channel |
| `clx-whatsapp-outreach-v1` | dormant | webhook | WhatsApp channel |
| `clx-voice-outreach-v1` | dormant | webhook | Voice/Vapi channel |
| `clx-video-outreach-v1` | dormant | schedule + webhook | **Personalized video** outreach (Tavus) |
| `clx-video-ready-v1` | dormant | webhook (Tavus callback) | Tavus video-ready receiver |
| `clx-pipeline-update-v2` | **active** (PROTECTED) | schedule | Update lead pipeline state |

> **Important:** `clx-video-outreach-v1` already exists as a complete
> Tavus pipeline for **personalized 1-to-1 outreach video**. Phase 2a's
> Content Generator (Component 1) is for **shareable 1-to-many content
> marketing video**. Both use the same Tavus credential and Anthropic
> credential but write to different tables. See Q1 in
> `99-open-questions.md`.

### Component 4: Follow-Up Engine
Re-engagement after initial outreach.

| Workflow | Status | Trigger | Role |
|---|---|---|---|
| `clx-follow-up-v2` | dormant | schedule | Multi-touch follow-up cadence |
| `clx-reply-ingestion-v1` | dormant | webhook / schedule | Inbound reply handler |

### Component 5: Calendar Booking
Convert engaged lead → calendar appointment.

| Workflow | Status | Trigger | Role |
|---|---|---|---|
| `clx-booking-v2` | dormant | schedule + webhook | Booking orchestration; 48h-no-booking fallback into `clx-video-outreach-v1` |
| `clx-appointment-geocoder-v1` | dormant | webhook (`clx-appointment-geocoder`) | Geocode appointment location |
| `clx-no-show-detector-v1` | dormant | webhook (`clx-no-show-detector`) | Detect/handle no-shows |
| `clx-no-show-sms-recovery-v1` | dormant | webhook | SMS no-show recovery |

### Component 1: Content Generator (NEW — Phase 2a)
**This is what Phase 2a adds.** Multi-platform content marketing video,
not personalized outreach video.

| Workflow (stub, dormant) | Path | Role |
|---|---|---|
| `api/video/clx-video-content-generate.json` | `content/generate` | Topic + persona_id → script (Anthropic) → Tavus job → `content_pieces` row |
| `api/video/clx-video-tavus-status-poll.json` | `content/tavus-status-poll` | Poll Tavus, update `content_pieces.status` when ready |
| `api/video/clx-video-platform-adapt.json` | `content/platform-adapt` | Transform `content_pieces` → `platform_variants` per target platform |
| `api/video/clx-video-distribute-linkedin.json` | `content/distribute/linkedin` | Publish a `platform_variant` to LinkedIn |
| `api/video/clx-video-distribute-youtube.json` | `content/distribute/youtube` | Publish to YouTube |
| `api/video/clx-video-distribute-twitter.json` | `content/distribute/twitter` | Publish to Twitter |

Adding a new platform later = one row in `distribution_platforms` + one
new `clx-video-distribute-{platform}.json` workflow file. Component 1
core does not change.

---

## Coordination model — how Component 1 hands off to Components 2-5

The codebase's existing convention is **state-driven coordination via
Supabase**: workflows write to the database, downstream
schedule-triggered workflows pick up the new state on their next tick.
Direct `Execute Workflow` calls (e.g. `clx-booking-v2` → `clx-video-outreach-v1`
for the 48h fallback) are the exception, not the rule. See Q2 in
`99-open-questions.md`.

Phase 2a's Content Generator follows the same pattern:

**Broker-track flow** (Mary's own insurance prospects):
```
Lead Finder (existing, schedule) → leads row created
       ↓
Lead Research v2 (existing, schedule) → enriches leads row
       ↓
Content Generator (NEW, webhook) → produces content_pieces row
       ↓
[broker manually links content_piece → lead via
 INSERT INTO lead_persona_links (lead_id, persona_id, content_piece_id),
 then writes leads.video_url from content_pieces.tavus_video_url —
 leads schema is unchanged; lead_persona_links is the new junction table]
       ↓
Outreach Sender v2 (existing, schedule 60min) → picks up the lead, uses video URL
       ↓
Follow-Up v2 (existing, schedule) → re-engagement
       ↓
Booking v2 (existing) → appointment lands
```

**Builder-track flow** (Crystallux marketing content):
```
Content Generator (webhook) → content_pieces row → Tavus job → ready
       ↓
Platform Adapter (webhook, per platform) → platform_variants rows
       ↓
Distribute LinkedIn / YouTube / Twitter / etc. (webhook per platform)
       → distribution_log rows
```

The builder-track is purely Component 1 territory. The broker-track
shows reuse of Components 2-5 via state.

---

## Persona layer — the threading principle

A `persona_id` is threaded through every place the persona matters.
For new tables it's a column (`content_pieces.persona_id`,
`distribution_log.persona_id`, etc.). For existing tables it's a
junction-table FK so the existing schema stays bit-for-bit untouched
(`lead_persona_links.persona_id`, `client_default_personas.persona_id`,
`campaign_persona_links.persona_id`). Existing workflows ignore the
junction tables entirely; Phase 2b+ retrofits opt in by joining.

Personas:
- **Mary the Broker** (`mary_broker`) — insurance broker selling life,
  health, RIBO products. Highest revenue priority.
- **Mary the Builder** (`mary_builder`) — Crystallux founder marketing
  the platform itself. Demonstrates 2A Engine working.
- **Per-Crystallux-client personas** — each onboarded client gets one
  or more persona rows scoped to their `client_id`. RLS-isolated.

One Tavus replica per physical person, multiple personas per replica
via prompt framing. See Q6 in `99-open-questions.md`.

---

## Non-goals for Phase 2a

- **Not** modifying any of the 7 protected active workflows
- **Not** modifying the 25 newly-imported auth/admin/client webhooks
- **Not** activating any new workflow tonight — all stubs land dormant
- **Not** applying the migration tonight — Mary reviews first
- **Not** building Tavus account / replica — Mary creates manually
- **Not** implementing Stripe metering — only stubbed hooks
- **Not** rebuilding `clx-video-outreach-v1` (personalized outreach
  video is its job, content marketing video is Component 1's)

## What ships when

| Week | Track | What lands |
|---|---|---|
| 1 | Broker | Mary's own Tavus replica + 5–10 personalized outreach videos for live prospects |
| 2 | Builder | Crystallux marketing content publishing to LinkedIn/YouTube/Twitter |
| 3 | Multi-tenant readiness | Persona endpoints queryable per `persona_id`, billing stubs |
| 4 | First Crystallux client | One paying client with their own persona row |

See `07-rollout-plan.md`.
