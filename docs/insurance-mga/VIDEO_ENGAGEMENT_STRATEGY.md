# Video Engagement Strategy (Insurance MGA — Layer 2 Part B)

> **Audience:** anyone reviewing how Crystallux turns regulatory checkpoints into emotional client touchpoints via personalized AI persona video.

## The thesis

A traditional insurance MGA touches a client a few times per year via:
- Renewal notice (transactional, easy to ignore)
- Birthday card (impersonal, easy to ignore)
- "Annual review reminder" email (regulatory checkbox, easy to ignore)

Crystallux replaces those forgettable touchpoints with a **60-second personalized AI persona video** for every meaningful life event. The video says the client's name, references the actual signal that triggered it (their new baby, their new job, their renewal date), and ends with a clear single-action CTA.

Every annual review feels like a gift, not a chore. Every life event becomes a meaningful client touchpoint. Engagement rates that traditional email blasts can't touch.

## How it connects to existing infrastructure

This is **net-additive** on top of two existing systems shipped in commit 25c0886:

1. **Behavioral Intelligence pipeline** (`workflows/api/intelligence/`) — already detects life-event signals (birthday, new job, marriage, etc.) and writes to `behavioral_signals`.
2. **Video pipeline** (`workflows/api/video/`) — already generates HeyGen avatar videos with personalized scripts, stores in R2, hosts mobile-responsive landing pages, tracks engagement.

Layer 2 Part B adds the **review system** in between, which:

- Listens to BI signals via `/webhook/mga/insurance/review-triggered-event`
- Decides which signals warrant a video review (filters: lead has in-force policy, hasn't been reviewed recently, signal_type is one we have a template for)
- Looks up the right `video_review_templates` row by trigger_event
- Asks Claude to personalize the script template with concrete client facts
- Chains into the existing video pipeline to render + deliver
- Tracks engagement back to `policy_reviews.video_engagement_status`
- Schedules AI follow-ups when engagement stalls

**No duplication.** The HeyGen render workflow, R2 upload, landing page renderer, and engagement tracker are all reused as-is from commit 25c0886.

## The 12 templates (insurance vertical)

Seeded once by `clx-mga-insurance-video-review-templates-seed-v1`. Each is tone-tuned per trigger:

| Trigger event | Tone | Default duration | Persona × Look |
|---|---|---|---|
| `birthday` | celebratory | 60s | sarah / blazer |
| `new_job` | congratulatory | 70s | james / suit |
| `marriage` | celebratory | 70s | sarah / blazer |
| `baby` | celebratory | 75s | maria / warm |
| `home_purchase` | congratulatory | 70s | james / suit |
| `business_expansion` | congratulatory | 75s | james / suit |
| `job_loss` | supportive | 70s | maria / warm |
| `annual_review_due` | informative | 60s | sarah / blazer |
| `renewal_due` | informative | 65s | james / suit |
| `claim_filed` | supportive | 70s | maria / warm |
| `retirement_planning_age` | informative | 70s | james / suit |
| `child_milestone` | celebratory | 70s | maria / warm |

Persona/look choices match the emotional register: warm/empathetic moments use Maria, professional/financial moments use James or Sarah. Per-client overrides via `clients.preferred_persona_id` (Layer 1 commit 25c0886) take precedence.

## Engagement lifecycle

`policy_reviews.video_engagement_status` is a strict-monotonic ratchet — only upgrades, never downgrades:

```
not_sent → sent → viewed → replied → meeting_booked
```

State transitions:

| Event from landing page | Status update |
|---|---|
| `page_view`, `video_play`, `video_25/50/75/complete` | → `viewed` |
| `cta_click`, `reply_received` | → `replied` |
| `booking_completed` | → `meeting_booked` |

Stale-engagement follow-ups (`clx-mga-insurance-review-followup-v1`, daily 09:00 ET):

| Current status | Threshold | Action |
|---|---|---|
| `sent` | 3+ days, no upgrade | AI WhatsApp nudge ("did you have a chance to watch?") |
| `viewed` | 7+ days, no upgrade | AI personal follow-up ("any questions?") |
| `replied` | 7+ days, no booking | Notify advisor for personal outreach |

## Cost envelope

Per video review:

| Component | Cost |
|---|---|
| HeyGen render (60-75s) | ~$0.30 |
| Claude personalization (1 call, ~3K tokens) | ~$0.01 |
| R2 storage (per video, lifetime) | <$0.001 |
| WhatsApp/SMS delivery (Twilio) | ~$0.005 |
| Landing page hosting | ~$0 (n8n) |
| **Total per review touchpoint** | **~$0.32** |

For Mary's projected book at scale (1,000 in-force policies × ~6 review touchpoints/year average) = ~6,000 videos/year × $0.32 = **~$1,900/year platform cost** for the entire video engagement program. The marginal CAC equivalent of a single new policy via this engagement loop ($1.5K-3K commission) covers it 1,000×.

## Why this is the moat

Carriers, traditional MGAs, and emerging insurtech competitors don't do this:

- **Carriers** can't — they don't have the relationship layer; their renewal notices come from billing systems, not a person.
- **Traditional MGAs** can't — the per-review marginal cost is too high (advisor time × volume).
- **Other insurtech competitors** could in theory but don't — most are stuck on chatbot flows, not personalized video.

The combination of (a) behavioral signal detection + (b) per-event tone library + (c) HeyGen avatar persona + (d) Crystallux's AI agent driving the daily SLA = a unique engagement model. The fact that Layer 1 + Layer 2 Part A + Layer 2 Part B all sit on the same vertical-tagged schema means **this exact pattern extends to mortgage MGA, real estate brokerage, group benefits, etc.** with new template libraries — same engine.

## Implementation map

The 5 video-engagement workflows in this commit:

| ID | File | Trigger | Purpose |
|---|---|---|---|
| B7.0 | `clx-mga-insurance-video-review-templates-seed-v1.json` | one-time webhook (admin) | Seeds the 12 templates into `video_review_templates` |
| B7.1 | `clx-mga-insurance-review-video-generator-v1.json` | called by review-scheduler + review-triggered-event | Personalizes template via Claude → chains into existing video pipeline |
| B7.2 | `clx-mga-insurance-review-video-deliver-v1.json` | called when video render is ready | Picks channel (WA > SMS > email) + sends personal intro + landing URL |
| B7.3 | `clx-mga-insurance-review-video-engagement-tracker-v1.json` | called by landing page tracking JS | Ratchets `video_engagement_status` |
| B7.4 | `clx-mga-insurance-review-followup-v1.json` | daily 09:00 ET schedule | AI nudges or escalates per stale-engagement rules |

## Phase 5b polish (deferred from this commit)

- **Per-vertical persona tuning** — match HeyGen persona to vertical default (insurance defaults differ from mortgage defaults). Currently uses one global default per template; per-vertical override via `vertical_id` lookup is a small enhancement.
- **A/B testing of templates** — which CTA text converts best per vertical? Track via `video_engagement_status` rollups.
- **Per-client opt-out** — `clients.video_review_opt_out=true` flag to suppress for clients who explicitly request no video.
- **Localization** — currently English; QC-province templates need French variants.

## Cross-references

- Review system architecture: [`REVIEW_MANAGEMENT_VISION.md`](REVIEW_MANAGEMENT_VISION.md)
- BI pipeline (signal source): `workflows/api/intelligence/` (commit 25c0886)
- Video pipeline (rendering + delivery): `workflows/api/video/` (commit 25c0886)
- HeyGen + persona setup: `docs/agent/build-phases.md`
- Schema: [`db/migrations/insurance-mga-operations-schema.sql`](../../db/migrations/insurance-mga-operations-schema.sql) (`video_review_templates` + `policy_reviews.video_render_id` + `video_engagement_status`)
