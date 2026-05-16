# Avatar platform — existing-infrastructure audit (2026-05-16)

This is the audit Mary asked for before any code is added for the
"7-avatar broadcasting platform" (LUXI, AVA, LUMI, LUMA, MAXI, LETY,
EAZA). The point is to surface what already exists, what does NOT
exist, and where the new work attaches so we **extend** the current
pipeline rather than rebuild it.

**TL;DR**
- The repo has a working single-avatar batch-render pipeline (video) + a 6-platform content pipeline + a foundational AI-agent stack. **Total = 31 workflows, all currently `active: false`.**
- There is **no multi-avatar routing layer, no live-streaming infrastructure, no `avatars` table, and zero "Eazer" / "Eaza" references** anywhere in code or docs.
- The 7-avatar vision is **mostly net-new** at the orchestration / data layer; the underlying video render, social publishing, and agent decision plumbing is reusable as-is.

---

## 1. Video workflows (9 total — matches Mary's count)

All under `workflows/api/video/` except the two outreach-entry workflows at the root.

| File | Path | Webhook | Active | Key integrations | Purpose |
|---|---|---|---|---|---|
| `clx-video-outreach-v1.json` | `workflows/` (root) | `clx-video-outreach-v1` | ✗ | Tavus, Anthropic, Supabase | Entry: fetch lead, compose script, dispatch render |
| `clx-video-ready-v1.json` | `workflows/` (root) | `clx-video-ready-v1` | ✗ | Tavus callback, Gmail | Tavus-side completion handler (legacy; HeyGen path replaces this) |
| `clx-video-script-generator-v1.json` | `api/video/` | `video/script-generate` | ✗ | Anthropic (Claude Sonnet 4.5), Supabase | Lead + behavioural-signal-aware script, writes to `video_renders` |
| `clx-video-heygen-render-v1.json` | `api/video/` | `video/heygen-render` | ✗ | HeyGen v2 API | Resolves avatar/voice from vertical-keyed persona table OR `clients.custom_avatar_id`, POSTs to HeyGen |
| `clx-heygen-webhook-v1.json` | `api/video/` | `heygen-video-ready` | ✗ | HeyGen callback, Cloudflare R2 | Validate sig, download MP4, push to R2, mark `ready`, mint 16-char token |
| `clx-video-delivery-router-v1.json` | `api/video/` | `video/delivery-route` | ✗ | Internal RPC chain | Dispatch to WhatsApp / SMS / email per `agent_personalities.default_channel` |
| `clx-video-landing-page-v1.json` | `api/video/` | `v/:token` | ✗ | Supabase | Public GET; renders mobile landing page with autoplay + Calendly |
| `clx-video-engagement-tracker-v1.json` | `api/video/` | (no public hook) | ✗ | Supabase | Records play / mute / unmute / click-book events from landing page |
| `clx-video-storage-cleanup-v1.json` | `api/video/` | (cron) | ✗ | R2, Supabase | 90-day retention housekeeping |

**Plus 4 insurance-MGA video workflows** (chain on top of the above for review-trigger flows): `clx-mga-insurance-review-video-generator-v1`, `*-deliver-v1`, `*-engagement-tracker-v1`, `*-video-review-templates-seed-v1`.

**Persona resolution as it stands today:**

- Vertical-keyed default lookup in code (no DB table): `james/suit` (B2B), `sarah/blazer` (B2B), `marcus/uniform` (field services), `maria/warm` (personal services).
- Per-client override via `clients.custom_avatar_id` (HeyGen avatar ID).
- **One persona per client.** No per-lead, per-campaign, or per-time-slot avatar selection.

---

## 2. Content workflows (14 total — matches Mary's count)

All under `workflows/api/content/`.

| File | Webhook | Active | Key integrations | Purpose |
|---|---|---|---|---|
| `clx-content-topic-generator-v1` | (internal trigger) | ✗ | Anthropic, Supabase | Daily proposal of topics from market + behavioural signals → `content_topics` |
| `clx-content-script-writer-v1` | (internal) | ✗ | Anthropic | Per approved topic: write 60s script → `content_videos` |
| `clx-content-video-render-v1` | `content/heygen-render` | ✗ | HeyGen | Render content videos (same persona lookup as outreach) |
| `clx-content-heygen-callback-v1` | `content/heygen-callback` | ✗ | HeyGen, R2 | Content-specific completion handler |
| `clx-content-publisher-linkedin-v1` | (scheduled) | ✗ | LinkedIn API | Per-platform publisher (one workflow each for LinkedIn, IG, YT, FB, TikTok, X) |
| `clx-content-publisher-instagram-v1` | (scheduled) | ✗ | IG Graph API | |
| `clx-content-publisher-youtube-v1` | (scheduled) | ✗ | YouTube Data API | |
| `clx-content-publisher-facebook-v1` | (scheduled) | ✗ | FB Graph API | |
| `clx-content-publisher-tiktok-v1` | (scheduled) | ✗ | TikTok API | |
| `clx-content-publisher-x-v1` | (scheduled) | ✗ | X/Twitter API | |
| `clx-content-engagement-poller-v1` | (every 2h) | ✗ | All 6 platform APIs | Pull views/likes/comments/shares into `content_engagement` |
| `clx-content-comment-monitor-v1` | (every 2h) | ✗ | Platform APIs | Detect inbound comments needing response |
| `clx-content-comment-response-v1` | `content/comment-respond` | ✗ | Anthropic | Classify + reply (or escalate) to comments |
| `clx-content-attribution-loop-v1` | (daily 02:00) | ✗ | Supabase | Link content posts → bookings → revenue (24h window) |

**Schema is live** (`content_topics`, `content_videos`, `content_publications`, `content_engagement` tables exist in `db/migrations/`). UI stubs at `admin-dashboard/pages/content-library.html` + `content-performance.html` already render against them.

---

## 3. Agent workflows (8 base + insurance variants — matches Mary's count)

All under `workflows/api/agent/`.

| File | Webhook | Active | Integrations | Purpose |
|---|---|---|---|---|
| `clx-agent-decision-engine-v1` | `agent/decide` | ✗ | Anthropic, Supabase, behavioural signals | Per lead + context, Claude picks next action: send / call / reschedule / escalate / wait |
| `clx-agent-action-executor-v1` | `agent/execute` | ✗ | WhatsApp / SMS / email / Vapi / video-script-generator | Dispatch decision to the right channel |
| `clx-agent-conversation-handler-v1` | `agent/message/:channel` | ✗ | All inbound channels, Anthropic | Unified inbound state machine |
| `clx-agent-voice-outbound-v1` | `agent/voice-outbound` | ✗ | Vapi | Outbound calls with DNC checks |
| `clx-agent-voice-inbound-v1` | (Vapi callback) | ✗ | Vapi | Inbound call → transcript → intent → conv state |
| `clx-agent-memory-update-v1` | (fired by decision engine) | ✗ | Anthropic embeddings, pgvector | Semantic memory: objections, preferences, close patterns → `agent_memory` |
| `clx-agent-escalation-v1` | (fired by decision engine) | ✗ | Email + Slack | Human handoff with reason + resolution tracking |
| `clx-agent-daily-summary-v1` | (nightly) | ✗ | Anthropic, Supabase | Daily rollup → `agent_performance`, feeds dashboard + billing |

**Plus** `clx-mga-insurance-compliance-agent-v1` and `clx-mga-insurance-suitability-conversation-handler-v1` for FSRA/RIBO-aware insurance flows.

---

## 4. External integrations matrix

| Service | Used by | Credential | Wired in repo? |
|---|---|---|---|
| HeyGen v2 | video × 5, content × 2, sentinel × 1 | `HEYGEN_API_KEY` env var | Workflow plumbing complete; credential binding incomplete in some nodes |
| Tavus (legacy) | `clx-video-outreach-v1` only | `TAVUS_API_KEY` | Marked as fallback; HeyGen is the forward path |
| Anthropic | video script, content script, agent decision, comment response, MGA compliance agent | `ANTHROPIC_API_KEY` | Bindings present, some "TODO: wire" comments |
| ElevenLabs | referenced in `agent_personalities.custom_voice_id` | none yet | **Not integrated** — voice today is Vapi |
| Vapi | agent voice in/out | n8n credential | Plumbed, deactivated |
| OpenAI | embeddings (alt to Claude embeddings) | env var | Referenced, not actively used |
| LinkedIn / IG / YT / FB / TikTok / X | 6 content publishers | per-platform OAuth in n8n | Framework yes; per-client tokens TBD |
| Supabase | every workflow | `Supabase Crystallux` (HTTP Header Auth) | ✓ Active |
| Cloudflare R2 | `clx-heygen-webhook-v1`, `clx-content-heygen-callback-v1` | AWS S3 node w/ R2 endpoint | Framework yes; `R2_*` env vars required |
| Gmail | `clx-video-ready-v1` | `gmailOAuth2` | ✓ Bound |
| Stripe | provisioning (separate pipeline) | `Stripe` | Outside this audit's scope |

---

## 5. Schema (already in `db/migrations/`)

**Video-relevant:**
`video_renders`, `content_videos`, `content_topics`, `content_publications`, `content_engagement`.

**Agent-relevant:**
`agent_decisions`, `agent_actions`, `agent_conversations`, `agent_memory`, `agent_escalations`, `agent_performance`, `agent_costs`, `agent_personalities`, `agent_channels_enabled`, `agent_schedules`.

**What does NOT exist:**
- No `avatars` table.
- No `personas` table.
- No `persona_library` table.
- No `broadcaster_sessions` / `live_stream` / `stream_platforms` tables.
- No `eazer_*` tables, no `eazer_billing`, no `eazer_clients`.

The current persona "table" is hard-coded vertical → `(persona_id, look_id, voice_id, heygen_avatar_id)` defaults in workflow code, plus per-client `clients.custom_avatar_id` override.

---

## 6. UI surface

| Page | File | Status |
|---|---|---|
| Content library | `admin-dashboard/pages/content-library.html` | Stub — "populates once topic generator + script writer are activated" |
| Content performance | `admin-dashboard/pages/content-performance.html` | Wired to `content_engagement` |
| Client content calendar | `client-dashboard/pages/content-calendar.html` | Wired |
| Client content engagement | `client-dashboard/pages/content-engagement.html` | Wired |
| Client content preferences | `client-dashboard/pages/content-preferences.html` | Wired |
| Video performance | — | **No dedicated UI** — landing pages serve from `v/:token` |
| Avatar management | — | **None** — persona is code+env, not user-managed |
| Streaming sessions | — | **None** |
| Eazer billing | — | **None** |

---

## 7. Gaps against the 7-avatar vision

### 7.1 Multi-avatar registry
The 7 named avatars (LUXI, AVA, LUMI, LUMA, MAXI, LETY, EAZA) have no representation anywhere in code, DB, or env. Today's pipeline picks an avatar based on **client's vertical** (a tenant decides theirs once); the new vision picks based on **the publisher's brand strategy** (Crystallux runs 7 brand voices in parallel, each addressing a different vertical from the same parent platform). That's an inversion of the resolution model — a real architecture change, not a renaming.

### 7.2 Avatar routing layer
The spec asks for routing on:
- Business vertical (luxury commerce → LUXI, insurance → AVA, wellness → LUMI, etc.)
- Time-of-day schedules (LUMI runs 22:00–06:00, LUMA runs 19:00–23:00, etc.)
- Personality / voice / catchphrase
- Per-avatar knowledge bases + compliance rules

None of these dimensions are routable today; `clx-video-delivery-router-v1` only routes by **channel** (WhatsApp / SMS / email), not avatar.

### 7.3 Live streaming
Everything in `workflows/api/video/` is **batch render-then-deliver**. HeyGen returns an MP4 URL; we hand the user a landing page. There is no:
- WebRTC / HLS / RTMP ingestion
- Continuous broadcast worker
- Per-platform live distribution (YouTube Live, TikTok Live, FB Live, IG Live)
- Comment-aggregation across platforms during a live session

HeyGen has a beta interactive avatar API (avatar-on-stream), but no workflow uses it.

### 7.4 Per-avatar content libraries
Today content topics are vertical-keyed in a single `content_topics` table. The vision wants:
- LUMI's wellness library separate from LUMA's entertainment library
- Per-avatar knowledge bases (FAQ + scripts + compliance constraints)
- Avatar-aware topic generation

Achievable as a column on `content_topics` (+ a join table) — schema change is small; the harder part is rewriting the topic-generator prompt to be avatar-aware.

### 7.5 Eazer B2B billing
**Zero references in the repo.** No `eazer_*` table, no workflow naming "eazer" or "eaza", no doc mention. The 5 workflows the spec lists (`clx-eaza-billing-calculator-v1`, `clx-eaza-eazer-data-sync-v1`, `clx-eazer-monthly-invoice-v1`, `clx-eazer-bonus-tracker-v1`, `clx-eazer-tier-manager-v1`) are all net-new. This is also the only avatar tied to an **external business** (Eazer's logistics ops), so the spec implies data-sync glue Crystallux doesn't otherwise have.

### 7.6 Performance analytics per avatar
`content_engagement` rolls up by `content_publication_id`. To answer "which avatar got the best engagement on insurance topics this week?" we'd need to add an `avatar_id` foreign key everywhere video + content data is logged.

### 7.7 Compliance rules per avatar
AVA → FSRA / RIBO; LUMI → wellness disclaimers; EAZA → Eazer brand guidelines; LUXI → consumer-protection on live auctions. None of these compliance gates exist today (insurance has `clx-mga-insurance-compliance-agent-v1`, which is the closest precedent and the right pattern to copy).

---

## 8. Reusable foundations (the part of "don't rebuild" we should honour)

| What to keep | Reuse for the 7-avatar platform |
|---|---|
| `clx-video-script-generator-v1` | Script generator — add `avatar_id` input, expand persona-lookup to read from the new `avatars` table |
| `clx-video-heygen-render-v1` | Render — read `heygen_avatar_id` + `elevenlabs_voice_id` from the avatar row |
| `clx-heygen-webhook-v1` | Untouched — works the same regardless of which avatar rendered |
| `clx-video-landing-page-v1` | Untouched — token-based VOD landing serves any avatar |
| `clx-video-delivery-router-v1` | Extend to be avatar-aware (different default channel per avatar) |
| `clx-content-topic-generator-v1` | Extend — accept `avatar_id`, scope topic universe to that avatar's knowledge base |
| `clx-content-script-writer-v1` | Extend — use avatar personality profile + catchphrase |
| All 6 `clx-content-publisher-*` | Untouched — they publish whatever video URL they're handed |
| `clx-content-engagement-poller-v1` | Extend — group metrics by `avatar_id` |
| Agent stack (decision / action / conversation / memory) | Per-avatar agent_personalities row → per-avatar tone + escalation rules |
| `clx-mga-insurance-compliance-agent-v1` | Canonical compliance-agent pattern; clone for AVA (FSRA), LUMI (wellness), EAZA (logistics), LUXI (consumer protection) |
| Existing `content_topics` / `content_videos` schema | Adds an `avatar_id` FK; backfill keeps existing rows working |
| `agent_personalities` table | Becomes per-avatar tone config, foreign-keyed to `avatars` |

---

## 9. What this audit does NOT say

- Does not estimate hours for the build. The spec's "15-25h" assumes the audit looks identical to the spec's mental model; it does not (see § 7.5 Eazer = entirely new line, § 7.3 live streaming = real RTMP work, not just a workflow).
- Does not greenlight `live streaming` as a category. HeyGen interactive avatars + a multi-platform restream layer is non-trivial; the cost / capability shape needs Mary's call before any workflow is drafted.
- Does not decide the build order. See `EXTENSION_PLAN.md` for the recommended slicing.

---

**Sources** — every claim above is grounded in:
- `workflows/api/video/`, `workflows/api/content/`, `workflows/api/agent/`, `workflows/api/insurance-mga/`, `workflows/` root.
- `db/migrations/` (full diff).
- `docs/architecture/PRODUCT_VISION.md`, `docs/architecture/BUSINESS_PLAN.md`, `docs/architecture/ROADMAP_*.md`.
- Grep across `admin-dashboard/`, `client-dashboard/`, `insurance-mga-dashboard/`, `site/`, `dashboard/` for `avatar|persona|stream|broadcast|eazer|eaza`.

If any of these reads as wrong to Mary, please flag the specific line — this report is meant to be re-runnable, not an opinion piece.
