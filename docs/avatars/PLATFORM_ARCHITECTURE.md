# Avatar platform — architecture

How the avatar registry plugs into Crystallux's existing video / content / agent pipeline. Paired with [`AUDIT_REPORT.md`](AUDIT_REPORT.md) (what's there) and [`EXTENSION_PLAN.md`](EXTENSION_PLAN.md) (what to build).

Schema landed in commit `54b256d` — `db/migrations/avatars-platform-schema.sql`.

## One-paragraph statement

**An avatar is a row in `avatars` that ties together a personality / voice / visual / schedule / compliance configuration with the existing render → publish → engage pipeline.** Workflows that today resolve persona+voice from a hard-coded vertical lookup learn to resolve them from `avatars` instead, keyed by `avatar_id`. Existing rows without `avatar_id` continue to use the vertical fallback — no regression, additive only.

## The read path

```
                       ┌──────────────────────────────────────┐
                       │ Trigger: lead, scheduled topic, etc. │
                       └──────────────┬───────────────────────┘
                                      │  (intent + lead_id OR topic_id)
                                      ▼
                       ┌──────────────────────────────────────┐
                       │ clx-avatar-router-v1   ◄── NEW T1 wf │
                       │  - resolve avatar_id by (vertical,   │
                       │    schedule window, A/B bucket)      │
                       │  - load avatars row + compliance     │
                       └──────────────┬───────────────────────┘
                                      │  $avatar.* available downstream
                                      ▼
                       ┌──────────────────────────────────────┐
                       │ clx-video-script-generator-v1        │
                       │  (EXTENDED — reads $avatar.personality│
                       │   instead of vertical defaults)      │
                       └──────────────┬───────────────────────┘
                                      ▼
                       ┌──────────────────────────────────────┐
                       │ clx-video-heygen-render-v1           │
                       │  (EXTENDED — reads $avatar.heygen_*  │
                       │   + $avatar.elevenlabs_voice_id;     │
                       │   falls back to existing defaults if │
                       │   null)                              │
                       └──────────────┬───────────────────────┘
                                      ▼
                       ┌──────────────────────────────────────┐
                       │ clx-heygen-webhook-v1                │
                       │  (UNCHANGED — same R2 + token logic) │
                       └──────────────┬───────────────────────┘
                                      ▼
                       ┌──────────────────────────────────────┐
                       │ clx-video-delivery-router-v1         │
                       │  (EXTENDED — reads                   │
                       │   $avatar.default_outbound_channel,  │
                       │   falls back to                      │
                       │   agent_personalities.default_channel)│
                       └──────────────────────────────────────┘
```

**Key invariant:** every "EXTENDED" workflow is *additive*. If the input has no `avatar_id`, the existing fallback fires. We never silently change behaviour for legacy rows.

## What an avatar row holds

From `db/migrations/avatars-platform-schema.sql`:

| Column | What it carries |
|---|---|
| `avatar_name` | Stable identifier (`'AVA'`, `'LUXI'`, `'MAXI'`, `'LUMI'`, `'LUMA'`, `'LETY'`, `'EAZA'`). |
| `business_vertical` | Drives the vertical-fallback when external IDs are null. |
| `heygen_avatar_id`, `elevenlabs_voice_id` | The actual rendering identity. Nullable — until populated, the workflow uses vertical defaults. |
| `personality_profile` jsonb | tone, formality, pace, humor, archetype. Consumed by the script-generator's Claude prompt. |
| `visual_profile` jsonb | look, environment, wardrobe palette, lighting. Used in HeyGen request params + content-library photo prompts. |
| `branding` jsonb | primary/accent colors, logo strapline. Used by landing pages + content overlays. |
| `content_schedule` jsonb | timezone, broadcast windows, days-of-week, channel allowlist. Read by the topic scheduler + the avatar router. |
| `compliance_rules` jsonb | regulatory framework, required disclaimers, prohibited topics, escalation triggers. Read by the compliance agent. |
| `default_outbound_channel` | whatsapp / sms / email / voice. Override for the delivery router. |
| `active` boolean | Dormant-by-default. Mary flips on per avatar at launch time. |

## How resolution works (the router workflow)

`clx-avatar-router-v1` (Tranche 1 commit 3 — not yet shipped) is a thin n8n workflow that:

1. **Inputs:** `intent` (`outreach` | `content_post` | `live_broadcast` | `comment_reply`), optional `lead_id`, optional `vertical_hint`, optional `target_avatar` (force-pick).
2. **Resolves avatar:**
   - If `target_avatar` set → load that row.
   - Else: look up active avatars whose `business_vertical` matches `vertical_hint` AND whose `content_schedule` matches current time.
   - If multiple match, pick by least-recent-render (round-robin) or by A/B-bucket hash on `lead_id`.
   - If none match, fall through to vertical default (no avatar_id passed downstream).
3. **Outputs:** the resolved `avatar_id` + the loaded `avatars` row + a downstream-ready payload.
4. **Dispatches** to the next workflow in the pipeline (script-generator, content-library, live-stream-orchestrator).

The router is the ONE place we hard-code avatar resolution rules. Every other workflow stays generic.

## Where each avatar diverges from the common path

### AVA — insurance growth
- **Compliance path:** every outbound action passes through `clx-mga-insurance-compliance-agent-v1` (existing). AVA's `compliance_rules.regulatory_framework` is read by that agent to gate FSRA / RIBO claims.
- **Channels:** email default; SMS / WhatsApp only for opted-in leads.
- **Revenue product gates:** AdvisorAssist subscription ($49-149/mo), RIBO Study Coach ($29-79/mo) — these need their own checkout workflows (NOT in T1 — see T1 follow-ups in EXTENSION_PLAN).

### LUXI — live commerce
- **Bidding state machine:** `auctions` + `auction_bids` + `bidder_trust_scores` + `auction_payment_holds`. Schema is in commit `54b256d`. Workflow that consumes the state machine: `clx-luxi-auction-tick-v1` (NOT shipped — T1 follow-up).
- **Anti-fraud gates:** 4 trust tiers, enforced at `auction_bids.status='pending_verification'`. Bidder cannot place a bid above `bidder_trust_scores.max_bid_cents` until tier is upgraded.
- **Anti-snipe:** `auctions.anti_snipe_window_seconds` + `anti_snipe_extend_seconds` (defaults 30 + 30) + `anti_snipe_max_extensions` (10). Enforced by `clx-luxi-auction-tick-v1` on each new bid.
- **Live streaming:** NOT yet decided. `avatar_streaming_sessions` table is the persistence layer; the runtime (HeyGen Interactive vs. Restream.io vs. self-hosted RTMP) is the **LIVE_STREAMING_RFC** open question.
- **Phase-2 commerce** (seller consignment, product inventory, comment-driven checkout, Stripe Connect for sellers) is its own multi-tranche workstream per EXTENSION_PLAN.

### MAXI — SMB growth
- **Multi-industry layer:** `maxi_industries` (21 rows seeded) × `maxi_industry_value_props` (8 capabilities → 160 rows seeded with generic labels; copy filled per industry over time).
- **Per-industry content:** the existing `clx-content-topic-generator-v1` extends to accept `industry_slug` in its input + scope the topic universe.
- **Landing surface:** new admin/marketing pages `pages/maxi/<industry>` — driven entirely by the industries + value_props tables.
- **No regulatory wrapper** like AVA — CASL + general consumer-protection only.

### LUMI, LUMA, LETY, EAZA — placeholder rows (Tranches 2–4)
- Rows exist in `avatars` with `active=false` and empty config jsonb. Future tranches fill in details; no new INSERTs needed.
- EAZA is gated on Eazer API spec — see EXTENSION_PLAN T4.

## What's intentionally still legacy

These keep using the hard-coded vertical→persona lookup until proven they need the registry:

- `clx-content-comment-monitor-v1`, `clx-content-comment-response-v1` (the comment-handling pair) — they work the same regardless of which avatar rendered the video.
- `clx-content-engagement-poller-v1` — needs `avatar_id` grouping eventually, but the metrics it pulls are platform-side, not avatar-aware. Extension is one `GROUP BY avatar_id` away when needed.
- `clx-content-publisher-*` (six per-platform workflows) — receive a finished video URL + caption; no avatar logic needed inside them.
- All insurance-MGA video workflows — they're AVA-shaped already via the vertical default.

## Next concrete commits (so the next session can pick up cleanly)

### T1 commit 3 — `clx-avatar-router-v1` workflow
- File: `workflows/api/avatars/clx-avatar-router-v1.json`
- Pattern: copy structure from `workflows/api/admin/clx-admin-overview-v1.json` (Webhook → Extract → Validate Session → Load Avatar → Shape Response). NOT a write endpoint; pure read + dispatch.
- Webhook: `avatars/route` (POST).
- Body: `{ intent, vertical_hint?, target_avatar?, lead_id? }`.
- Output: `{ avatar_id, avatar: {…full row…}, dispatch_target }`.

### T1 commit 4 — `clx-video-script-generator-v1` extension
- File: same path, edit existing.
- Add: optional `avatar_id` input. If present, load avatar row from Supabase, override persona/voice/tone in the Claude prompt. If absent, current vertical lookup stays the path.
- This is the RISKIEST commit (modifies a working workflow). Extra care: keep the legacy code path completely untouched; add the avatar path as a parallel branch with an IF guard on `$json.avatar_id`.

### T1 commit 5 — admin pages
- `admin-dashboard/pages/avatars.html` — list view; rows from `GET /webhook/avatars/list`.
- `admin-dashboard/pages/avatars/detail.html` — single-row CRUD; HeyGen + ElevenLabs ID fields wired but accept blank.
- Both pages use `clxAuth.require(['admin'])` (array form, post-`1c41a4b` canonical pattern).
- Backing webhooks: `clx-avatar-list-v1` + `clx-avatar-upsert-v1` (NEW workflow JSONs).

### T1 commit 6 — AVA content seeds
- File: `db/seeds/ava-content-topics.sql`
- ~50 insurance-education topics linked to AVA via `avatar_knowledge_topics`. Covers life / auto / home / travel / CI / disability, plus advisor recruitment + AdvisorAssist + RIBO Study Coach copy.

### T1 commit 7 — LUXI auction tick + bidding workflow
- File: `workflows/api/avatars/clx-luxi-auction-tick-v1.json`
- Cron every 5s during open auctions; closes expired auctions, advances anti-snipe, promotes runner-up on forfeit, captures Stripe holds on `won`.
- Backed entirely by the schema in commit `54b256d`; no schema changes needed.

### T1 commit 8 — MAXI industry pages
- `admin-dashboard/pages/maxi/index.html` — 21-industry grid.
- `admin-dashboard/pages/maxi/<industry>.html` — per-industry detail with the 8 capabilities.
- Driven by `clx-maxi-industries-v1` + `clx-maxi-industry-detail-v1` (NEW workflow JSONs).

### T1 docs follow-up
- `docs/avatars/LIVE_STREAMING_RFC.md` — the deferred architecture decision for live broadcasting.
- `docs/avatars/AVA_REVENUE_PRODUCTS.md` — how AVA's AdvisorAssist / RIBO Coach checkout actually works (Stripe subscription wiring).
- `docs/avatars/LUXI_PHASE_2_SCOPE.md` — when the time comes, what the e-commerce subsystem looks like.

## Critical things to keep correct

- **Never set `avatars.active = true` from code.** Mary activates per launch — same rule as workflows.
- **HeyGen + ElevenLabs IDs are nullable.** Workflows must gracefully fall back to vertical defaults until Mary fills them in.
- **The router is the only resolver.** Other workflows take `avatar_id` and trust it; they don't re-resolve.
- **Compliance rules are advisory-style strings, not enforced predicates.** The compliance agent applies them via prompt; this is a Claude-side guardrail, not an RLS policy.
- **Bidder identity is hashed.** `bidder_trust_scores.bidder_identity_hash` is the PK key — never store raw platform handles as identity; that's PII leakage and complicates GDPR-style deletion.
