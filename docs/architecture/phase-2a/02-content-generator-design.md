# Phase 2a — Content Generator (Component 1) Design

> **Scope:** This component produces **content-marketing video** —
> shareable, multi-platform, 1-to-many. It is **NOT** the personalized
> 1-to-1 outreach video pipeline. That already exists as
> `clx-video-outreach-v1` (dormant). See Q1 in
> [`99-open-questions.md`](./99-open-questions.md).

## Input contract

```json
POST /content/generate
Authorization: Bearer <session_token>      // session validated, role checked
{
  "persona_key": "mary_broker",            // OR persona_id
  "topic": "why-cash-value-life-insurance-matters",
  "brief": "60-second hook + 30-second body + CTA. Audience = parents 35-50.",
  "track": "broker",                       // 'broker' | 'builder' | 'client'
  "niche_override": null,                  // Optional override of persona.niche_overlay_default
  "source_lead_id": null                   // Optional — set ONLY for broker-track personalized cuts
}
```

**Auth model:** matches existing `api/admin/*` and `api/client/*`
pattern — Bearer token → `validate_session` RPC → role check. Internal
personas (Mary the Broker / Builder) require `admin` role to invoke.
Client-owned personas require `client` role and `client_id` match.

## Output contract

```json
202 Accepted
{
  "ok": true,
  "content_piece_id": "uuid",
  "status": "generating",
  "tavus_request_id": "tvs_...",
  "estimated_ready_at": "2026-05-02T19:42:00Z"
}
```

The webhook returns immediately after the Tavus job is submitted. The
final video URL lands when the polling workflow
(`clx-video-tavus-status-poll`) sees Tavus return `ready`.

Component 1 ENDS at "content piece ready". Distribution is a separate
chain (`clx-video-platform-adapt` + `clx-video-distribute-{platform}`).

## Pipeline (inside `clx-video-content-generate`)

```
1. Webhook (POST /content/generate)
2. Extract Token              → Bearer parse
3. Validate Session           → Supabase rpc/validate_session
4. Check Role                 → admin or matching client_id
5. Resolve Persona            → SELECT * FROM personas WHERE persona_key=… OR id=…
6. Resolve Niche              → COALESCE(req.niche_override, persona.niche_overlay_default)
7. Compose Script             → Anthropic (claude-opus-4-7)
                                  system: persona.prompt_framing
                                          + niche_overlay.video_script_template
                                  user:   topic + brief
8. Insert content_piece       → status='draft', script captured, tavus_request_id=NULL
9. Submit Tavus Job           → POST Tavus /v2/videos with replica_id + script
10. Update content_piece      → status='generating', tavus_request_id=<id>, generated_at=now()
11. Insert persona_usage_log  → estimated minutes (best-effort placeholder; reconciled at ready)
12. Respond 202               → { content_piece_id, status, tavus_request_id }
```

## Polling workflow (`clx-video-tavus-status-poll`)

Schedule-triggered every 90 seconds. Logic:

```
1. Find generating pieces:
     SELECT * FROM content_pieces
      WHERE status='generating' AND tavus_request_id IS NOT NULL
      ORDER BY generated_at ASC
      LIMIT 25

2. For each: GET Tavus /v2/videos/<id>
3. Branch on Tavus status:
     - 'ready'   → UPDATE content_pieces SET
                     status='ready',
                     tavus_video_url=…,
                     tavus_thumbnail_url=…,
                     tavus_duration_seconds=…,
                     ready_at=now()
                   UPDATE persona_usage_log SET tavus_minutes_used=<actual>
     - 'failed'  → UPDATE content_pieces SET status='failed', status_detail=<reason>
     - 'queued' / 'processing' → no-op
```

**Why polling not callbacks:** the existing `clx-video-ready-v1` is the
Tavus callback receiver but it correlates by `request_id` →
`leads.video_request_id`. Reusing it for `content_pieces` would require
modifying that workflow. Polling avoids any change to the existing
callback workflow; both can coexist. See Q1.

If Mary later wants to switch to callback-based status updates (lower
latency, lower API call volume), the polling workflow gets retired and
`clx-video-ready-v1` gets a discriminator branch — but that's a Phase
2b decision.

## Anthropic call shape

```
Model:  claude-opus-4-7
System: persona.prompt_framing
        + "\n\n"
        + niche_overlay.video_script_template
        + "\n\nProduce a video script appropriate for {track} distribution."
User:   { topic, brief, source_lead_id (if broker-track) }
Output: structured JSON {
          script_intro, script_body, script_cta,
          suggested_caption_seed, suggested_thumbnail_concept
        }
```

**Why structured output:** caption seed and thumbnail concept feed
downstream platform adapters without re-prompting Anthropic per
platform — keeps cost predictable.

**Cache headers:** Anthropic prompt caching enabled on
`persona.prompt_framing` (changes rarely) and the niche_overlay
template — both are set as cacheable system blocks.

## Tavus call shape

```
POST https://tavusapi.com/v2/videos
{
  "replica_id":  persona.tavus_replica_id,
  "script":      <composed script>,
  "video_name":  "{persona_key}-{topic-slug}-{utc-stamp}",
  "callback_url": null    // Polling, not callback (see above)
}
```

The callback_url could be set to the (existing) `clx-video-ready-v1`
endpoint *with a content_piece_id query param*, but again, that means
modifying an existing dormant workflow. Defer to Phase 2b.

## What Component 1 does NOT do

| Concern | Where it lives |
|---|---|
| Sending personalized outreach video to one lead | `clx-video-outreach-v1` (existing, dormant) |
| Generating outreach copy (email/LinkedIn body) | `clx-outreach-generation-v2` (existing, dormant) |
| Sending outreach via channel | `clx-outreach-sender-v2` (existing, dormant) |
| Scheduling follow-up cadence | `clx-follow-up-v2` (existing, dormant) |
| Booking the appointment | `clx-booking-v2` (existing, dormant) |
| Adapting content for LinkedIn/YouTube/Twitter | `clx-video-platform-adapt` (Phase 2a, new) |
| Publishing to a platform | `clx-video-distribute-<platform>` (Phase 2a, new) |
| Polling engagement metrics | future Phase 2b workflow, not built tonight |

## "No duplication" verification

| Existing workflow | Could overlap? | Resolution |
|---|---|---|
| `clx-outreach-generation-v2` | No — generates per-lead outreach copy from `leads` table state | Different scope; no overlap |
| `clx-video-outreach-v1` | **Yes — also uses Tavus + Anthropic** | Different table (`leads.video_*` vs `content_pieces`), different distribution target. Coexist. Documented in Q1. |
| `clx-video-ready-v1` | **Yes — Tavus callback** | We poll instead of receiving callbacks. Both workflows can coexist without modification. Documented in Q1. |
| `clx-outreach-sender-v2` | No — sends via outreach channels, not platform-publishes | Different scope |
| niche_overlays | **Yes — already has `video_script_template`** | Reuse. Personas reference niche_overlay rows by name; do not duplicate templates. Documented in Q3. |
