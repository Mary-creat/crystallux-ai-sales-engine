# Phase 2a — Persona + Distribution Schema

Five new tables and a small set of additive `ALTER TABLE` columns on
existing ones. The full DDL is in
`docs/architecture/migrations/2026-05-02-phase-2a-foundation.sql` —
this doc explains the *why* of each.

> **Read first:** [`99-open-questions.md`](./99-open-questions.md). Schema
> assumes the recommended path on Q3 (niche × persona two axes), Q6
> (one replica many personas), and Q7 (Tavus minutes per persona = bill
> unit).

## Tables

### 1. `personas`
Canonical persona registry. One row per (physical-person × audience-framing) pair.

```sql
personas (
  id                       uuid PK
  persona_key              text  UNIQUE NOT NULL    -- 'mary_broker' | 'mary_builder' | 'client_acme_founder'
  display_name             text  NOT NULL           -- 'Mary the Broker'
  client_id                uuid  NULL → clients(id) -- NULL for internal Crystallux personas; set for client-owned personas
  persona_type             text  NOT NULL           -- 'internal_broker' | 'internal_builder' | 'client_owned'
  tavus_replica_id         text  NULL               -- Tavus replica reference; multiple personas may share one
  default_voice_id         text  NULL               -- ElevenLabs / Tavus voice ref if separate
  niche_overlay_default    text  NULL               -- Default niche framing key, references niche_overlays.niche_name
  prompt_framing           text  NULL               -- Anthropic system-prompt fragment that defines persona voice/POV
  audience_description     text  NULL               -- Free-text "who this persona speaks to"
  monthly_tavus_minute_cap integer DEFAULT 60       -- Soft cap for billing/cutoff
  active                   boolean DEFAULT true
  created_at, updated_at
)
```

**Why `client_id` is nullable:** Mary the Broker and Mary the Builder
are internal personas with no client. Client-owned personas have it
set. RLS policies use this to scope client visibility.

**Why `tavus_replica_id` not FK to a replicas table:** Tavus owns
replica IDs server-side, no local replicas table needed.

**Why `niche_overlay_default` is text, not FK:** matches existing
pattern — `niche_overlays.niche_name` is already used as a lookup key
in `clx-video-outreach-v1`. Avoiding a hard FK keeps niche taxonomy
extensible.

**Seed data added by migration:**
- `mary_broker` (persona_type=internal_broker)
- `mary_builder` (persona_type=internal_builder)

### 2. `content_pieces`
Canonical content. Platform-agnostic. One row = one piece of source
content (a video + script + caption + metadata) that may be
distributed to many platforms.

```sql
content_pieces (
  id                     uuid PK
  persona_id             uuid NOT NULL → personas(id)
  topic                  text NOT NULL                   -- 'why-cash-value-life-insurance-matters'
  brief                  text NULL                       -- Optional human-written brief
  script                 text NULL                       -- Generated script (Anthropic output)
  script_model           text NULL                       -- 'claude-opus-4-7' etc. for traceability
  niche                  text NULL                       -- Niche overlay override (else persona default)
  source_lead_id         uuid NULL → leads(id)           -- Set ONLY for broker-track personalized content
  -- Tavus job state
  tavus_request_id       text NULL                       -- Tavus job id once submitted
  tavus_replica_id       text NULL                       -- Captured from persona at job submit
  tavus_video_url        text NULL                       -- Final video URL once 'ready'
  tavus_thumbnail_url    text NULL
  tavus_duration_seconds integer NULL
  -- Lifecycle
  status                 text NOT NULL DEFAULT 'draft'   -- draft|generating|ready|failed|archived
  status_detail          text NULL                       -- Free-form detail for failed
  -- Track
  track                  text NOT NULL DEFAULT 'broker'  -- 'broker' | 'builder' | 'client'
  -- Metadata
  created_at, updated_at, generated_at, ready_at
)
```

**Why `source_lead_id`:** broker-track personalized videos are tied to
one lead. Builder-track and client-track videos have it NULL.
Distinction lets us answer "show me all content pieces for this lead"
and "show me all generic content for this persona."

**Why `track` is denormalized text:** queryable without joining; matches
the existing pattern in `leads.lead_status`, `campaigns.status`, etc.

### 3. `platform_variants`
Per-platform transformations of a `content_pieces` row. Generated lazily
when a distribution request lands.

```sql
platform_variants (
  id                  uuid PK
  content_piece_id    uuid NOT NULL → content_pieces(id) ON DELETE CASCADE
  platform_key        text NOT NULL → distribution_platforms(platform_key) -- 'linkedin' | 'youtube' | ...
  -- Transformed content
  caption             text NULL                       -- Platform-formatted caption/post text
  title               text NULL                       -- For platforms that need a separate title (YouTube)
  hashtags            text[] NULL                     -- Pre-formatted, platform-appropriate
  thumbnail_url       text NULL                       -- May differ per platform (square vs 16:9 etc.)
  video_url           text NULL                       -- Platform-uploaded video URL once published
  duration_seconds    integer NULL                    -- May be trimmed per platform (Reels = ≤90s)
  adapter_version     text NOT NULL                   -- 'v1-template' | 'v1-anthropic-hook' — see Q4
  -- Lifecycle
  status              text NOT NULL DEFAULT 'pending' -- pending|adapted|published|failed
  adapted_at          timestamptz NULL
  -- Metadata
  created_at, updated_at,
  UNIQUE (content_piece_id, platform_key)
)
```

**Why one variant row per (content × platform):** keeps the canonical
content piece pristine and lets us re-adapt for a new platform without
touching the source.

### 4. `distribution_platforms`
Registry of supported platforms. **This is the buffer** — adding a new
platform = INSERT a row + write one workflow file. Component 1's core
never changes.

```sql
distribution_platforms (
  platform_key        text PK                       -- 'linkedin' | 'youtube' | 'twitter' | 'devto' | 'blog' | 'tiktok' | 'reels' | 'shorts'
  display_name        text NOT NULL                 -- 'LinkedIn'
  adapter_workflow    text NOT NULL                 -- 'clx-video-platform-adapt' (the single shared adapter)
  publish_workflow    text NOT NULL                 -- 'clx-video-distribute-linkedin' (the per-platform publisher)
  max_video_seconds   integer NULL                  -- Platform constraint
  max_caption_chars   integer NULL                  -- Platform constraint
  supports_hashtags   boolean DEFAULT true
  supports_thumbnail  boolean DEFAULT true
  active              boolean DEFAULT true
  notes               text NULL
)
```

**Seed rows added by migration:**

| platform_key | display | max_seconds | max_chars | active |
|---|---|---|---|---|
| linkedin | LinkedIn | 600 | 3000 | true |
| youtube | YouTube | 43200 | 5000 | true |
| twitter | Twitter | 140 | 280 | true |
| devto | Dev.to | NULL | NULL | false (Phase 2c+) |
| blog | crystallux.org/blog | NULL | NULL | false |
| tiktok | TikTok | 600 | 2200 | false |
| reels | Instagram Reels | 90 | 2200 | false |
| shorts | YouTube Shorts | 60 | 5000 | false |

The 5 inactive ones are scaffolded as known future platforms — adding
them later is `UPDATE distribution_platforms SET active=true WHERE
platform_key='reels'` plus the matching workflow file.

### 5. `distribution_log`
One row per publish attempt. Persists outcome regardless of success.

```sql
distribution_log (
  id                  uuid PK
  platform_variant_id uuid NOT NULL → platform_variants(id) ON DELETE CASCADE
  content_piece_id    uuid NOT NULL → content_pieces(id) ON DELETE CASCADE  -- denormalized for query convenience
  persona_id          uuid NOT NULL → personas(id)                          -- denormalized
  platform_key        text NOT NULL                  -- denormalized
  -- Result
  status              text NOT NULL                  -- 'queued' | 'published' | 'failed'
  external_post_id    text NULL                      -- Platform-side post ID (LinkedIn URN, YouTube videoId, etc.)
  external_post_url   text NULL                      -- Public URL of published post
  error_detail        text NULL
  -- Engagement counters (best-effort, polled later)
  impressions         integer DEFAULT 0
  engagements         integer DEFAULT 0
  click_throughs      integer DEFAULT 0
  -- Lifecycle
  attempted_at        timestamptz NOT NULL DEFAULT now()
  published_at        timestamptz NULL
  metrics_polled_at   timestamptz NULL
)
```

### 6. `persona_usage_log`
Per-persona Tavus minute consumption for billing/caps.

```sql
persona_usage_log (
  id                  uuid PK
  persona_id          uuid NOT NULL → personas(id)
  client_id           uuid NULL → clients(id)               -- denormalized from persona for quick filter
  content_piece_id    uuid NULL → content_pieces(id)
  tavus_minutes_used  numeric(10,2) NOT NULL                -- 0.50 = 30s
  unit_cost_usd_cents integer NULL                          -- Captured at consumption time
  occurred_at         timestamptz NOT NULL DEFAULT now()
)
```

Stripe metering hook (stubbed): on insert, emit a usage record event
keyed by `persona.client_id` → Stripe customer_id. Implementation is
deferred to Phase 2c.

---

## Junction tables (NOT ALTER TABLE on existing tables)

> **Strict additive constraint** (Mary's post-Q-review override): the
> existing `leads`, `clients`, and `campaigns` tables are NOT modified.
> No `ADD COLUMN`, no FK constraints attached to existing tables, no
> COMMENT statements on existing columns. Persona linkage to existing
> tables lives entirely in three new junction tables. Inbound FKs are
> owned by the junction tables; pg_class entries for leads / clients /
> campaigns are unchanged after this migration applies.

### 7a. `lead_persona_links`
Replaces what would have been `leads.persona_context_id` +
`leads.content_piece_id`. One row per lead at most.
```sql
lead_persona_links (
  lead_id          uuid PK → leads(id) ON DELETE CASCADE
  persona_id       uuid NULL → personas(id) ON DELETE SET NULL
  content_piece_id uuid NULL → content_pieces(id) ON DELETE SET NULL
  created_at, updated_at
)
```

### 7b. `client_default_personas`
Replaces what would have been `clients.default_persona_id`.
```sql
client_default_personas (
  client_id  uuid PK → clients(id) ON DELETE CASCADE
  persona_id uuid NOT NULL → personas(id) ON DELETE RESTRICT
  created_at, updated_at
)
```

### 7c. `campaign_persona_links`
Replaces what would have been `campaigns.persona_id`. Guarded for
the case where the `campaigns` table doesn't yet exist (depends on
2026-05-01-audit-fixes).
```sql
campaign_persona_links (
  campaign_id uuid PK → campaigns(id) ON DELETE CASCADE
  persona_id  uuid NOT NULL → personas(id) ON DELETE RESTRICT
  created_at
)
```

Existing workflows ignore these junction tables entirely. Phase 2b+
retrofits opt in by joining when they need persona context.

---

## RLS posture

All five new tables get:
- `ENABLE ROW LEVEL SECURITY`
- `service_role` policy: ALL operations allowed (matches existing pattern; n8n workflows authenticate as service_role)
- Future per-client read policy on `personas` / `content_pieces` /
  `platform_variants` / `distribution_log` (when client dashboard
  surfaces these — Phase 2b)

The internal personas (`mary_broker`, `mary_builder`) have
`client_id IS NULL` and are visible only to admin-role sessions when a
read policy is added.

---

## Indexes

```sql
CREATE INDEX content_pieces_persona_idx       ON content_pieces (persona_id, created_at DESC);
CREATE INDEX content_pieces_status_idx        ON content_pieces (status) WHERE status IN ('draft','generating','failed');
CREATE INDEX content_pieces_track_idx         ON content_pieces (track, created_at DESC);
CREATE INDEX content_pieces_lead_idx          ON content_pieces (source_lead_id) WHERE source_lead_id IS NOT NULL;
CREATE INDEX platform_variants_content_idx    ON platform_variants (content_piece_id);
CREATE INDEX distribution_log_persona_idx     ON distribution_log (persona_id, attempted_at DESC);
CREATE INDEX distribution_log_status_idx      ON distribution_log (status, attempted_at DESC);
CREATE INDEX persona_usage_log_persona_idx    ON persona_usage_log (persona_id, occurred_at DESC);
CREATE INDEX persona_usage_log_client_idx     ON persona_usage_log (client_id, occurred_at DESC) WHERE client_id IS NOT NULL;
```

`updated_at` triggers on `personas`, `content_pieces`, `platform_variants`,
`distribution_platforms` (matches existing pattern from
`campaigns_set_updated_at`).
