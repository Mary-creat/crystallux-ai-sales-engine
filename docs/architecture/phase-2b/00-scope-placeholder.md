# Phase 2b — Scope Placeholder

**Status:** NOT STARTED. Scope captured for future planning.
**Prerequisite:** Phase 2a must be live with real usage data before Phase 2b kicks off.
**Created:** 2026-05-02

---

## What Phase 2b Is

Phase 2b extends the Phase 2a video clone platform from Mary's two personas (Broker + Builder) into a **multi-character AI content engine**.

Where Phase 2a is "one human (Mary), two framings (Broker / Builder), one platform (Crystallux)," Phase 2b is "any number of fictional or distinct AI characters, each with their own niche / voice / personality / content type, distributed across multiple short-form platforms."

## Why Phase 2b Is Separate from Phase 2a

Three reasons it's a separate phase, not an extension of 2a:

1. **Different audience and economics.** Phase 2a serves Mary's insurance broker work and Crystallux's own marketing. Phase 2b serves a content services product — Crystallux clients who pay for AI character content as a productized service.

2. **Different risk profile.** Phase 2a uses Mary's real likeness (Tavus replica of her). Phase 2b uses fictional characters that must be clearly disclosed as AI-generated (TOS compliance on TikTok/Reels/Shorts, no real-person impersonation). Distinct compliance considerations.

3. **Phase 2a has to ship first.** Building 2b before 2a is in production means designing for usage patterns that don't exist yet. Phase 2a usage data informs Phase 2b architecture.

## What Phase 2b Adds (High-Level)

- **Character layer:** schema for fictional AI characters with name / niche / tone / personality / content type
- **Multi-platform short-form distribution:** TikTok, Instagram Reels, YouTube Shorts (Phase 2a's distribution layer extends to these via the existing `distribution_platforms` registry)
- **Content services product:** Crystallux clients can spin up characters for their business and Crystallux generates short-form content on their behalf
- **Mode separation:** Mary Mode (Phase 2a personas, real Mary) vs Character Mode (Phase 2b fictional characters). Same pipeline, different inputs, mutually exclusive at workflow run time.

## Architectural Reuse from Phase 2a

Phase 2b reuses without modification:

- `personas` table — Phase 2b characters are persona rows with a `persona_type` flag distinguishing 'real_person' (Phase 2a) from 'fictional_character' (Phase 2b)
- `content_pieces` table — character-generated content stored identically to persona-generated content
- `platform_variants` + `distribution_platforms` registry — adds rows for TikTok, Reels, Shorts; doesn't refactor anything
- `distribution_log` table — same tracking
- Existing Anthropic credential — script generation
- Existing Tavus integration — multi-character requires per-character replicas (cost implication, design decision in 2b)

## What Phase 2b Does NOT Include

- Adult content, intimacy products, or any TOS-violating use of fictional personas
- Real-person impersonation
- Any modification to Phase 2a workflows or schema (additive only, same principle as 2a)

## Open Questions for Phase 2b Kickoff (Future)

These get answered when 2b actually starts, not now:

1. Per-character Tavus replicas (cost) vs single replica with prompt-shifted character framing (quality risk)
2. Manual character design vs Claude-generated character profiles
3. Self-serve character creation for Crystallux clients vs Mary-curated character roster
4. Pricing model for character content services (per-video / per-month / per-character)
5. Content moderation review pipeline (who reviews fictional character output before it posts)
6. Mode-switching guardrails (preventing Mary Mode and Character Mode from cross-contaminating output)

## When Phase 2b Starts

Trigger conditions, in order:

1. Phase 2a is live and running for at least 2 weeks with real content
2. Mary the Broker track has generated revenue
3. Mary the Builder track has produced at least 5 published pieces
4. At least one Crystallux SaaS client is onboarded and paying
5. Mary explicitly decides to expand into character-based content services

If those conditions aren't met, Phase 2b waits.

---

**Owner:** Mary Akintunde
**Branch when started:** TBD (likely `phase-2b-character-engine` off main)
