# Avatar platform — extension plan (2026-05-16)

Paired with `AUDIT_REPORT.md`. Where the audit says "what is", this
file says "what to build, in what order, and what NOT to build yet."

## Guiding principles

1. **Extend, don't rebuild.** Every video render, every social publish, every agent decision already has a working workflow. The new code is mostly a routing + registry layer + per-avatar tone/compliance config.
2. **One avatar end-to-end before all seven.** AVA (insurance) is the only avatar whose vertical already has its own dashboard, compliance agent, and 4-workflow video stack. It's the lowest-risk slice to validate the routing + registry pattern. After AVA works in production, generalising to the other 6 is largely config + a per-avatar compliance-agent clone.
3. **Live streaming is its own track.** It is not 5 workflows on top of existing video. It's a new infrastructure category (RTMP / HLS / multi-platform restream). Don't bundle it into the avatar-registry build; scope and decide separately.
4. **Eazer is a business integration, not an avatar.** EAZA is a brand voice on top of an external operations integration with Eazer (logistics ops). Treat the data-sync + billing as a separate component; the avatar UX is the easy part.
5. **Dormant by default.** Every new workflow ships `active: false`. Mary activates per launch.

---

## Sliced build order (recommended)

### Tranche 1 — Avatar registry + one avatar live (AVA)
**Estimate:** 4–6 hours of focused work + Mary's activation. Ships in 3 commits.

Deliverables:
1. `db/migrations/avatars-registry-schema.sql` — `avatars` table + `avatar_content_library` join + `avatar_knowledge_topics` + indexes. **Idempotent.**
2. Seed row for AVA (no other avatars yet).
3. **One** new workflow: `clx-avatar-router-v1` that, given a `(vertical, lead_id, intent)`, resolves the `avatar_id` and forwards to the existing `clx-video-script-generator-v1` with avatar config attached.
4. Extension of `clx-video-script-generator-v1` to read avatar config (persona, voice, catchphrase) from the new `avatars` row instead of the hard-coded vertical map. Backwards-compatible: if no avatar lookup hits, fall back to the existing vertical defaults.
5. Extension of `clx-video-heygen-render-v1` to use `avatars.heygen_avatar_id` + `avatars.elevenlabs_voice_id` (the spec keeps ElevenLabs even though current voice is via Vapi for live; for HeyGen render, voice is part of the avatar config).
6. One admin page: `admin-dashboard/pages/avatars.html` — list of registered avatars, status, last-render time. Read-only first cut; CRUD comes in T3.

Validates:
- Avatar registry is correct shape (Mary can read a row and see the fields she expects).
- Existing video pipeline picks up avatar config without regressions on tenants that have no avatar configured.
- A single AVA insurance render produces an MGA-branded video without touching the 4 existing MGA video workflows.

Gated on:
- Mary applies the migration.
- Mary activates the router workflow.
- Mary fills in HeyGen avatar ID + ElevenLabs voice ID for AVA (one row).

### Tranche 2 — Per-avatar agent personality + compliance
**Estimate:** 3–4 hours.

Deliverables:
1. Migration adds `avatar_id` FK to `agent_personalities` (nullable; existing rows unaffected).
2. Clone `clx-mga-insurance-compliance-agent-v1` → `clx-ava-compliance-agent-v1`. Same FSRA/RIBO rules, but reads scoped from `avatars.compliance_rules` JSONB. Existing MGA agent stays as the canonical insurance compliance layer; AVA-specific is a thin wrapper.
3. `clx-agent-decision-engine-v1` — extension only: when `lead.avatar_id` is set, load that avatar's personality profile (tone, catchphrase, schedule windows). Default unchanged.

Validates:
- An AVA-tagged lead gets AVA's voice in every outbound action (video / message / call), not the client's default tone.
- AVA's compliance gate fires before any FSRA-sensitive action (recommendation, quote, etc.).

### Tranche 3 — Avatar admin UI
**Estimate:** 4–6 hours.

Deliverables:
- `admin-dashboard/pages/avatars.html` — full CRUD (was read-only in T1).
- `admin-dashboard/pages/avatars/<avatar>.html` — per-avatar detail: schedule, knowledge base, content library, performance metrics.
- New per-avatar webhooks behind the dashboard: `avatar/list`, `avatar/upsert`, `avatar/schedule-update`, `avatar/knowledge-add`.
- Performance: pull from `content_engagement` filtered by `avatar_id`.

### Tranche 4 — Generalise to the other 6 avatars
**Estimate:** 1–2 hours per avatar **once the framework is proven** in T1–T3.

Per avatar:
- One `avatars` row (Mary fills HeyGen + ElevenLabs IDs in the UI from T3).
- One compliance-agent clone (or shared "open" agent for non-regulated avatars like LUMA, MAXI, LETY).
- One row in `avatar_content_library` to seed the knowledge base.
- No new workflow files for the common case.

This is the only tranche that scales by avatar; T1–T3 are one-time.

### Tranche 5 — Live streaming (defer, scope separately)
**Estimate:** unknown — see §7.3 of AUDIT_REPORT.md. Likely 15–30h on its own.

Reasons to defer:
- HeyGen interactive avatar API is beta-only.
- Multi-platform restream (YouTube Live + TikTok Live + FB Live + IG Live) requires either Restream.io / Castr-style middleware OR a self-hosted RTMP fan-out (significant ops surface).
- 24/7 broadcast worker is a new always-on runtime — n8n cron is not the right primitive.
- Comment aggregation across platforms is its own product feature.

Recommended: write `docs/avatars/LIVE_STREAMING_RFC.md` first to capture the architectural decisions (HeyGen interactive vs. pre-recorded loop, Restream vs. self-host, comment storage model, moderation). Land that BEFORE writing any workflow code.

### Tranche 6 — Eazer integration (defer, scope separately)
**Estimate:** unknown — depends entirely on what Eazer exposes.

Required before any workflow is drafted:
- Eazer API spec or sample payloads.
- Confirmation of the billing model (per-message? per-stream-hour? per-delivery? performance bonuses keyed to what metric?).
- Tier definitions (Bronze / Silver / Gold etc.) and what triggers tier transitions.

Recommended: `docs/business/EAZER_INTEGRATION.md` written from Mary's commercial conversations with Eazer, then a workflow plan derived from it.

---

## What goes in `avatars` (proposed schema)

Aligned with Mary's spec but with three changes flagged:

```sql
CREATE TABLE avatars (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avatar_name          text UNIQUE NOT NULL,
  business_vertical    text NOT NULL,
  heygen_avatar_id     text,
  elevenlabs_voice_id  text,
  personality_profile  jsonb NOT NULL DEFAULT '{}'::jsonb,
  visual_profile       jsonb NOT NULL DEFAULT '{}'::jsonb,
  content_schedule     jsonb NOT NULL DEFAULT '{}'::jsonb,
  compliance_rules     jsonb NOT NULL DEFAULT '{}'::jsonb,
  catchphrase          text,
  branding             jsonb NOT NULL DEFAULT '{}'::jsonb,
  active               boolean NOT NULL DEFAULT false,  -- (1) dormant by default per CLAUDE.md
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
```

Changes from Mary's spec:
1. **`active` defaults to `false`** (CLAUDE.md "dormant by default" policy).
2. **No `knowledge_base_ids text[]`** — replaced by `avatar_knowledge_topics(avatar_id, topic_id)` join table for normalisation + cascade.
3. **No `links_to_video_workflows text[]` / `links_to_content_workflows text[]`** — the workflows that handle avatar data resolve it at runtime via a single column lookup. Listing workflow IDs in the row creates drift (workflow files rename / consolidate); the router workflow does the lookup once and dispatches.

Companion tables (T1 + T2 + T3, not all at once):
- `avatar_knowledge_topics(avatar_id, content_topic_id, weight)` — join
- `avatar_content_library(avatar_id, content_video_id, status)` — owned content (T3)
- `avatar_comment_responses(avatar_id, platform, comment_id, response_text, posted_at)` — moderation log (T3)
- `eazer_billing(...)` — defer to T6 with proper schema

---

## Reuse-vs-build matrix (concise)

| Concern | Reuse | Build |
|---|---|---|
| Script generation | `clx-video-script-generator-v1` (+ minor extension) | — |
| HeyGen render | `clx-video-heygen-render-v1` (+ avatar lookup) | — |
| HeyGen callback / R2 | `clx-heygen-webhook-v1` | — |
| Delivery routing | `clx-video-delivery-router-v1` (+ avatar default-channel) | — |
| Landing pages | `clx-video-landing-page-v1` | — |
| Content topic generation | `clx-content-topic-generator-v1` (+ avatar scoping) | — |
| Social publishing × 6 | `clx-content-publisher-*` | — |
| Engagement metrics | `clx-content-engagement-poller-v1` (+ avatar_id grouping) | — |
| Agent decision engine | `clx-agent-decision-engine-v1` (+ per-avatar personality) | — |
| Compliance gate (insurance) | `clx-mga-insurance-compliance-agent-v1` | Thin wrappers per regulated avatar (AVA, LUMI, LUXI) |
| Avatar registry | — | NEW: `avatars` table + `clx-avatar-router-v1` + admin UI |
| Live streaming | — | NEW track, separate RFC |
| Eazer billing / sync | — | NEW track, separate doc |

---

## Non-goals for THIS plan

- Per-avatar branded landing pages. Today's landing page reads the video URL from `video_renders.storage_url`; per-avatar visual branding can be applied as CSS keyed by `avatars.branding.theme`. Plumbing only, no architecture change. Defer.
- A/B testing per avatar. Useful eventually; depends on metrics, which depend on having more than one avatar live.
- Real-time avatar takeover by Mary. Possible with HeyGen Interactive, but it's a Live Streaming tranche concern.
- "EAZA delivers" actually wired to Eazer's dispatch data. Defer to T6.

---

## What this commit changes

Nothing in code. Two docs:
- `docs/avatars/AUDIT_REPORT.md`
- `docs/avatars/EXTENSION_PLAN.md`

The build starts in the next commit (Tranche 1) once Mary approves the slicing.

---

## Open questions for Mary

These should be answered before Tranche 1 starts:

1. **Slice order OK?** AVA first, then the other six in a follow-up tranche, with live streaming + Eazer scoped separately?
2. **HeyGen avatar IDs:** does Mary already have HeyGen-trained avatars for the 7 names, or do those need to be created in HeyGen first (which is a HeyGen-side workflow, not a code task)?
3. **ElevenLabs:** is there a CL account, and are voice clones already trained for the 7 avatars? If not, voice is HeyGen-default until ElevenLabs IDs are filled in.
4. **Compliance review:** for AVA/FSRA, who signs off on the compliance_rules JSON content? (Mary as principal, or external compliance officer?)

If the answer to 2 or 3 is "not yet," T1 still proceeds — the avatars table holds the IDs as nullable, the render workflow falls back to current hard-coded defaults, and the system stays functional until the real IDs land.
