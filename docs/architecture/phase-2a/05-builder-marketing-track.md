# Phase 2a — Builder Marketing Track (Mary the Builder)

**Mary the Builder uses the 2A engine to market Crystallux itself.**
Each piece of content is proof that the platform works. The
distribution layer is the demonstration of the multi-platform buffer
described in `01-personas-and-distribution-schema.md`.

## End-to-end flow

```
Mary triggers:  POST /content/generate
  persona_key: mary_builder
  track:       builder
  topic:       'i-built-an-ai-sales-engine-in-12-weeks'
  source_lead_id: null            ← builder track is 1-to-many

      │
      ▼ content_pieces row created
      │ Tavus generates 60-90s video, status=ready
      │
      ▼ Mary triggers per platform:
      │   POST /content/platform-adapt   { content_piece_id, platform_key: 'linkedin' }
      │   POST /content/platform-adapt   { content_piece_id, platform_key: 'youtube' }
      │   POST /content/platform-adapt   { content_piece_id, platform_key: 'twitter' }
      │
      ▼ One platform_variants row per platform
      │
      ▼ Mary triggers per platform:
      │   POST /content/distribute/linkedin  { platform_variant_id }
      │   POST /content/distribute/youtube   { platform_variant_id }
      │   POST /content/distribute/twitter   { platform_variant_id }
      │
      ▼ distribution_log rows captured
        external_post_url available for each
```

## Persona setup

```sql
UPDATE personas SET
  tavus_replica_id      = '<MARY_REPLICA_ID>',  -- Same replica as broker
  niche_overlay_default = NULL,                  -- Not niche-bound
  prompt_framing        = $$
You are Mary, the founder of Crystallux. You speak as a builder who
built the AI sales engine you wish you'd had as a broker. Your
audience is other founders, SMB owners, and operators who are
considering automating their own outreach but skeptical of "AI
slop". Demonstrate, don't pitch. Show the receipts: real numbers,
real screenshots, real workflow names. Tone: technical, confident,
zero hype words. End with a soft CTA: "If this is useful, the link
in bio shows the actual stack."
$$,
  audience_description  = 'Founders, SMB operators, sales leaders
considering AI automation. Skeptical of vendor pitches; respect
shipped product over promised product.'
WHERE persona_key = 'mary_builder';
```

## Content angles — "I built X" demonstrates platform

Each angle becomes one `content_pieces.topic`. The pattern is
**concrete proof, not abstract pitch**:

| Topic | Angle | Why this lands |
|---|---|---|
| `built-2a-engine-in-12-weeks` | Project velocity proof | Founders care about shipping speed |
| `99-workflows-cleaned-up-overnight` | Operational discipline | Engineers respect the dedup pass |
| `live-edits-vs-repo-divergence` | Real-world ops honesty | Doesn't pretend everything is clean |
| `tavus-anthropic-supabase-stack` | Stack transparency | Builders want to see the cards |
| `from-broker-book-to-saas-platform` | Origin narrative | Story relatability |
| `state-driven-vs-event-driven-pipeline` | Architecture take | Senior engineers click on opinions |
| `cross-tenant-isolation-via-rls` | Security posture | Decision-makers look for this |
| `0-to-1-active-workflow-the-week-we-launched` | Scale honesty | Anti-vanity-metric play |
| `audit-fix-migration-that-failed-in-prod` | Incident-ops openness | Trust signal |
| `cleaning-up-67-duplicate-workflows-without-breaking-prod` | Operational chops | Specifically resonates with people who've been bitten |

## Distribution strategy

**Primary platforms (Phase 2a active):**
- **LinkedIn** — primary audience for the "I built X" narrative.
  Founder/SMB-operator viewers cluster here.
- **YouTube** — long-tail SEO and demo embed source.
- **Twitter** — primary retweet and discovery surface for engineers.

**Secondary (scaffolded, dormant — Phase 2c):**
- **Dev.to** — engineering-deep angles.
- **crystallux.org/blog** — owned-property versions of the same content.

**Future (Phase 2d):**
- TikTok / Reels / YouTube Shorts — short-form repurpose of the same
  Tavus video trimmed to ≤90s.

## Adapter behavior per platform

The adapter (`clx-video-platform-adapt`) reads the canonical
`content_pieces.script` and `suggested_caption_seed`, then generates a
`platform_variants` row tuned to the platform constraints in
`distribution_platforms`:

| Platform | Caption shape | Hashtags | Title | Video clip |
|---|---|---|---|---|
| LinkedIn | First-person hook + 2–3 lines + soft CTA, ≤3000 chars | 3–5 max, end of post | n/a | Embedded video |
| YouTube | Description with timestamps + CTA + hashtags | 5–10, in description | Yes — title field required | Full video |
| Twitter | 280-char hook + first line of CTA | 1–2 inline | n/a | Embedded video, ≤140s |

**Adapter strategy (per Q4 recommended path):** Hybrid —
deterministic templates for caption length / hashtag policy / title
formatting, with **one Anthropic call per platform for the hook
sentence only**. Keeps cost predictable (~$0.01 per platform variant)
while giving each platform a tonally-correct opener.

## "Builder track demonstrates the buffer" — what that means

The reason to scaffold all 8 platforms in `distribution_platforms`
even though only 3 are active in Phase 2a: when Mary or a future
client asks "can we add Reels?", the answer is:

1. `UPDATE distribution_platforms SET active=true WHERE platform_key='reels';`
2. Write `clx-video-distribute-reels.json` (one workflow file)
3. Done. Component 1 doesn't change. The adapter doesn't change. The
   schema doesn't change. The dashboards don't change.

**That property is the buffer.** When Mary writes "I built a
multi-platform content engine", the proof is that adding TikTok
takes a single SQL update + one workflow file, not a refactor.

## Week 2 success criteria

- [ ] First builder-track content_piece generated (1 video)
- [ ] Three platform_variants generated (LinkedIn, YouTube, Twitter)
- [ ] Three distribution_log entries with `status='published'`
- [ ] At least one external_post_url confirmed live and viewable
- [ ] Sanity check: re-running adapter for the same (piece, platform)
      pair updates the existing row (UNIQUE constraint protects)

## Out of scope for Week 2

- Engagement metric polling (Phase 2b)
- Reels/TikTok/Shorts distribution (Phase 2d)
- Per-platform A/B testing of hooks (Phase 2c)
- Cross-platform analytics dashboard (Phase 2c)
