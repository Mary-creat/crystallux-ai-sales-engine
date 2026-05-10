# Content Marketing Vision (Phase 4)

> **Phase 4 prep — schema only at this commit.** Workflows below are deferred until LinkedIn / Instagram / YouTube / Facebook / TikTok APIs are approved per client. Schema lives in `db/migrations/content-marketing-schema.sql`.

## Dual-purpose persona strategy

The same 4 HeyGen personas (James, Sarah, Marcus, Maria) and their look variants serve **two distinct purposes**:

1. **1-to-1 outreach** (Phase 2 — built in this commit). Per-lead personalised script → HeyGen render → R2 storage → landing page → channel delivery. Tracked in `video_renders` with `content_type='outreach'`. Retention: 90 days, then auto-archive via `clx-video-storage-cleanup-v1` (B7).

2. **1-to-many content marketing** (Phase 4 — workflows TBD). Topic-driven evergreen content posted to social platforms. Tracked in `content_videos` (separate table). Retention: indefinite — content is an asset, not a one-shot.

The personas are reusable infrastructure. Each `agent_personalities.vertical_context` value implies a default persona/look pairing (insurance → james_suit, real estate → james_casual, construction → marcus_uniform, dental → maria_warm, etc.). Per-client overrides via `clients.preferred_persona_id` + `clients.preferred_look_id`.

## Phase 4 build plan

### Workflows (all DORMANT at build time, activated per-client + per-platform)

| Workflow | Purpose | Trigger | Estimated effort |
|---|---|---|---|
| `clx-content-topic-generator-v1` | Mines `market_signals` + `behavioral_signals` patterns to propose 5-10 topics/week per active vertical → `content_topics` (status=proposed) | weekly schedule | ~6h |
| `clx-content-script-generator-v1` | Per `content_topic` (status=approved): generates 60-second script via Claude tuned for vertical + persona | webhook on topic approval | ~4h |
| `clx-content-video-render-v1` | Calls HeyGen with persona/look/voice → `content_videos` (status=rendering) | webhook | ~3h (mirror of B2) |
| `clx-content-heygen-callback-v1` | HeyGen callback handler — same R2 upload pattern as B3, marks `content_videos.status=ready` | webhook | ~3h (mirror of B3, no engagement tracking) |
| `clx-content-publisher-linkedin-v1` | Posts to LinkedIn via Unipile (already integrated for outreach). Inserts to `content_publications` | webhook | ~4h |
| `clx-content-publisher-instagram-v1` | Posts to Instagram via Meta Graph API | webhook | ~6h (auth complex) |
| `clx-content-publisher-youtube-v1` | Posts to YouTube via Data API v3 | webhook | ~6h |
| `clx-content-publisher-facebook-v1` | Posts to Facebook Page via Meta Graph API | webhook | ~4h (similar to Instagram) |
| `clx-content-publisher-tiktok-v1` | Posts to TikTok via Content Posting API | webhook | ~6h |
| `clx-content-publisher-x-v1` | Posts to X (Twitter) via API v2 | webhook | ~4h |
| `clx-content-engagement-poller-v1` | Daily poll per published item → `content_engagement` (views, likes, comments, shares) | schedule daily | ~6h |
| `clx-content-attribution-v1` | Joins `content_engagement.bookings_attributed` to `bookings.created_at` close to publication time + click-through tracking | weekly | ~4h |

**Total Phase 4 build estimate: 2–3 weeks** of senior-engineer Claude Code work. Most of the time is API approval + auth wiring — workflow architecture is well-understood from Phase 2.

### API requirements (per platform)

| Platform | Required | Approval lead time | Cost |
|---|---|---|---|
| LinkedIn | Unipile (already wired for outreach DM) — extend to org page posting | Days (per org auth) | Existing |
| Instagram | Meta Graph API + Instagram Business account + Page connection + App review | 1-2 weeks | Free |
| YouTube | YouTube Data API v3 + per-channel OAuth | Hours | Free (10K req/day) |
| Facebook | Meta Graph API + Page Access Token + App review | 1-2 weeks | Free |
| TikTok | TikTok for Developers + Content Posting API + business verification | 2-4 weeks | Free |
| X (Twitter) | X API v2 + Pro tier ($200/mo) for posting | Days | $200/mo per platform login |

### Per-vertical content library strategy

Topic generation seeds vary per vertical. Same engine, different inputs:

| Vertical | Primary topic sources |
|---|---|
| Insurance | FSRA bulletins, Bank of Canada rate changes, weather events, carrier rate filings |
| Mortgage | Bank of Canada rate, OFSI announcements, regional housing stats |
| Real estate | CREA monthly stats, regional MLS data, mortgage rate moves |
| Dental | RCDSO updates, dental insurance reimbursement changes, oral health awareness months |
| Construction | OBC/code changes, supply chain news, weather (winter prep, storm windows) |
| Consulting | Industry-specific trade publications by sub-niche |

Per-vertical seed lists live in `signal_archetypes` (already seeded for insurance via `clx-archetype-seed-insurance-v1` — Part A4 of this commit). Phase 4 expansion: add seed workflows for each new vertical as it's launched.

### Content performance learning loop

Mirrors `clx-behavioral-archetype-learner-v1` (A5):

- Weekly: per `content_videos.persona_id + look_id + vertical`, compute average `content_engagement.views / likes / bookings_attributed`.
- Surface top performers in a per-vertical dashboard panel.
- Disable underperforming persona/look combos (engagement floor: avg views < 50 after 5+ posts).
- Feed the winning combos back as defaults for new clients in that vertical.

### What's NOT in Phase 4

- Live streaming (LinkedIn Live, YouTube Live) — manual operator control, not AI.
- Generative editing (re-cuts, captions) — Phase 5 if needed.
- AI-generated thumbnails — manual upload via per-client portal first.

## Why this matters

Content marketing is the asymmetric upside on the same infrastructure investment:

- Same HeyGen account, same persona library, same R2 bucket, same Claude prompt patterns.
- Same `agent_personalities` per-client tuning.
- Marginal cost per video: ~$0.30 (HeyGen credit) + ~$0.005 (Claude script).
- Retention is indefinite — every video is a long-tail asset.
- Per-vertical content libraries become a moat over time as the conversion-rate learning loop tunes them.

This is a Phase 4 build. Schema is ready now so Phase 4 work doesn't require risky retrofits to production data.

## Cross-references

- Schema: [`db/migrations/content-marketing-schema.sql`](../../db/migrations/content-marketing-schema.sql)
- Persona infrastructure: [`docs/agent/AGENT_VISION.md`](AGENT_VISION.md), [`docs/agent/build-phases.md`](build-phases.md)
- Outreach video pipeline (the parallel 1:1 system): `workflows/api/video/clx-video-*-v1.json` (B1–B7 in this commit)
