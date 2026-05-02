-- ════════════════════════════════════════════════════════════════════
-- Crystallux Phase 2a — persona + distribution foundation
--   File:    2026-05-02-phase-2a-foundation.sql
--   Purpose: scaffold the schema for the 2A Engine's Content Generator
--            (Component 1) and the multi-platform distribution layer.
--            Adds persona_id capability to a small set of existing
--            tables additively (ADD COLUMN IF NOT EXISTS, never DROP,
--            never type-modify).
--   Status:  drafted; awaiting Mary's review of
--            docs/architecture/phase-2a/99-open-questions.md before
--            apply. NOT YET APPLIED.
--   Idempotent — safe to re-run.
--
--   Apply BEFORE activating any workflow under workflows/api/video/.
--   No protected v2/v3 active workflow depends on this migration —
--   the new columns on existing tables are nullable and ignored by
--   existing workflows.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. personas
-- ─────────────────────────────────────────────────────────────────────
-- Canonical persona registry. One row per (physical-person × audience-
-- framing) pair. client_id is NULL for internal Crystallux personas
-- (mary_broker, mary_builder); set for client-owned personas.
-- See docs/architecture/phase-2a/01-personas-and-distribution-schema.md
CREATE TABLE IF NOT EXISTS personas (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_key              text NOT NULL UNIQUE,
  display_name             text NOT NULL,
  client_id                uuid NULL REFERENCES clients(id) ON DELETE CASCADE,
  persona_type             text NOT NULL CHECK (persona_type IN ('internal_broker','internal_builder','client_owned')),
  tavus_replica_id         text NULL,
  default_voice_id         text NULL,
  niche_overlay_default    text NULL,
  prompt_framing           text NULL,
  audience_description     text NULL,
  monthly_tavus_minute_cap integer NOT NULL DEFAULT 60,
  active                   boolean NOT NULL DEFAULT true,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN personas.persona_key           IS 'Stable lookup key, e.g. mary_broker, mary_builder, client_acme_founder.';
COMMENT ON COLUMN personas.client_id             IS 'NULL for internal Crystallux personas; set for client-owned personas (RLS isolation anchor).';
COMMENT ON COLUMN personas.tavus_replica_id      IS 'Tavus replica reference. Multiple personas may share one replica via prompt_framing differentiation (per Q6).';
COMMENT ON COLUMN personas.niche_overlay_default IS 'Default niche framing key, references niche_overlays.niche_name (no FK to keep niche taxonomy extensible).';
COMMENT ON COLUMN personas.prompt_framing        IS 'Anthropic system-prompt fragment that defines persona voice/POV. The differentiator when one Tavus replica serves multiple personas.';

CREATE INDEX IF NOT EXISTS personas_client_idx ON personas (client_id) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS personas_active_idx ON personas (persona_type) WHERE active = true;

ALTER TABLE personas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "personas service_role" ON personas;
CREATE POLICY "personas service_role"
  ON personas FOR ALL TO service_role USING (true) WITH CHECK (true);

-- updated_at trigger (matches existing campaigns_set_updated_at pattern)
CREATE OR REPLACE FUNCTION personas_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS personas_updated_at ON personas;
CREATE TRIGGER personas_updated_at
  BEFORE UPDATE ON personas
  FOR EACH ROW EXECUTE FUNCTION personas_set_updated_at();

-- Seed: Mary the Broker + Mary the Builder
INSERT INTO personas (persona_key, display_name, persona_type, audience_description)
VALUES
  ('mary_broker',  'Mary the Broker',  'internal_broker',  'Insurance prospects (life, RIBO, group benefits) — Mary''s personal book.'),
  ('mary_builder', 'Mary the Builder', 'internal_builder', 'Founders / SMB owners who would buy Crystallux to automate their own outreach.')
ON CONFLICT (persona_key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 2. distribution_platforms (registry — the multi-platform buffer)
-- ─────────────────────────────────────────────────────────────────────
-- Adding a new distribution platform = INSERT a row here + write one
-- workflow file. Component 1's core does not change.
CREATE TABLE IF NOT EXISTS distribution_platforms (
  platform_key       text PRIMARY KEY,
  display_name       text NOT NULL,
  adapter_workflow   text NOT NULL,
  publish_workflow   text NOT NULL,
  max_video_seconds  integer NULL,
  max_caption_chars  integer NULL,
  supports_hashtags  boolean NOT NULL DEFAULT true,
  supports_thumbnail boolean NOT NULL DEFAULT true,
  active             boolean NOT NULL DEFAULT false,
  notes              text NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  distribution_platforms IS 'Registry of supported content-distribution platforms. The buffer for multi-platform automation: adding a platform is a row INSERT plus one workflow file.';
COMMENT ON COLUMN distribution_platforms.adapter_workflow IS 'Workflow that transforms a content_pieces row into a platform_variants row. Currently single shared adapter (clx-video-platform-adapt).';
COMMENT ON COLUMN distribution_platforms.publish_workflow IS 'Workflow that publishes the adapted variant to the platform.';

DROP TRIGGER IF EXISTS distribution_platforms_updated_at ON distribution_platforms;
CREATE OR REPLACE FUNCTION distribution_platforms_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
CREATE TRIGGER distribution_platforms_updated_at
  BEFORE UPDATE ON distribution_platforms
  FOR EACH ROW EXECUTE FUNCTION distribution_platforms_set_updated_at();

ALTER TABLE distribution_platforms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "distribution_platforms service_role" ON distribution_platforms;
CREATE POLICY "distribution_platforms service_role"
  ON distribution_platforms FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Seed registry rows. active=false for platforms not in Phase 2a scope.
INSERT INTO distribution_platforms
  (platform_key, display_name, adapter_workflow, publish_workflow, max_video_seconds, max_caption_chars, active, notes)
VALUES
  ('linkedin', 'LinkedIn',           'clx-video-platform-adapt', 'clx-video-distribute-linkedin', 600,   3000, true,  'Phase 2a primary'),
  ('youtube',  'YouTube',            'clx-video-platform-adapt', 'clx-video-distribute-youtube',  43200, 5000, true,  'Phase 2a primary'),
  ('twitter',  'Twitter',            'clx-video-platform-adapt', 'clx-video-distribute-twitter',  140,   280,  true,  'Phase 2a primary'),
  ('devto',    'Dev.to',             'clx-video-platform-adapt', 'clx-video-distribute-devto',    NULL,  NULL, false, 'Phase 2c — workflow not scaffolded yet'),
  ('blog',     'crystallux.org/blog','clx-video-platform-adapt', 'clx-video-distribute-blog',     NULL,  NULL, false, 'Phase 2c'),
  ('tiktok',   'TikTok',             'clx-video-platform-adapt', 'clx-video-distribute-tiktok',   600,   2200, false, 'Phase 2d'),
  ('reels',    'Instagram Reels',    'clx-video-platform-adapt', 'clx-video-distribute-reels',    90,    2200, false, 'Phase 2d'),
  ('shorts',   'YouTube Shorts',     'clx-video-platform-adapt', 'clx-video-distribute-shorts',   60,    5000, false, 'Phase 2d')
ON CONFLICT (platform_key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 3. content_pieces
-- ─────────────────────────────────────────────────────────────────────
-- Canonical content. Platform-agnostic. One row = one piece of source
-- content (script + video + metadata) that may be distributed to many
-- platforms via platform_variants. Component 1 ENDS at writing this
-- row; distribution is a separate workflow chain.
CREATE TABLE IF NOT EXISTS content_pieces (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id             uuid NOT NULL REFERENCES personas(id) ON DELETE RESTRICT,
  topic                  text NOT NULL,
  brief                  text NULL,
  script                 text NULL,
  script_model           text NULL,
  niche                  text NULL,
  source_lead_id         uuid NULL REFERENCES leads(id) ON DELETE SET NULL,
  -- Tavus job state
  tavus_request_id       text NULL,
  tavus_replica_id       text NULL,
  tavus_video_url        text NULL,
  tavus_thumbnail_url    text NULL,
  tavus_duration_seconds integer NULL,
  -- Lifecycle
  status                 text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','generating','ready','failed','archived')),
  status_detail          text NULL,
  track                  text NOT NULL DEFAULT 'broker' CHECK (track IN ('broker','builder','client')),
  -- Timestamps
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  generated_at           timestamptz NULL,
  ready_at               timestamptz NULL
);

COMMENT ON COLUMN content_pieces.source_lead_id IS 'Set ONLY for broker-track personalized content. NULL for builder-track and generic client-track.';
COMMENT ON COLUMN content_pieces.track          IS 'broker=Mary the Broker outreach; builder=Crystallux marketing; client=tenant client persona content.';
COMMENT ON COLUMN content_pieces.status         IS 'draft → generating → ready | failed. archived hides from default queries.';

CREATE INDEX IF NOT EXISTS content_pieces_persona_idx ON content_pieces (persona_id, created_at DESC);
CREATE INDEX IF NOT EXISTS content_pieces_status_idx  ON content_pieces (status) WHERE status IN ('draft','generating','failed');
CREATE INDEX IF NOT EXISTS content_pieces_track_idx   ON content_pieces (track, created_at DESC);
CREATE INDEX IF NOT EXISTS content_pieces_lead_idx    ON content_pieces (source_lead_id) WHERE source_lead_id IS NOT NULL;

ALTER TABLE content_pieces ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "content_pieces service_role" ON content_pieces;
CREATE POLICY "content_pieces service_role"
  ON content_pieces FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION content_pieces_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS content_pieces_updated_at ON content_pieces;
CREATE TRIGGER content_pieces_updated_at
  BEFORE UPDATE ON content_pieces
  FOR EACH ROW EXECUTE FUNCTION content_pieces_set_updated_at();

-- ─────────────────────────────────────────────────────────────────────
-- 4. platform_variants
-- ─────────────────────────────────────────────────────────────────────
-- Per-platform transformations of a content_pieces row. Generated
-- lazily when a distribution request lands. UNIQUE (content_piece_id,
-- platform_key) ensures one variant per platform per piece.
CREATE TABLE IF NOT EXISTS platform_variants (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_piece_id uuid NOT NULL REFERENCES content_pieces(id) ON DELETE CASCADE,
  platform_key     text NOT NULL REFERENCES distribution_platforms(platform_key) ON DELETE RESTRICT,
  caption          text NULL,
  title            text NULL,
  hashtags         text[] NULL,
  thumbnail_url    text NULL,
  video_url        text NULL,
  duration_seconds integer NULL,
  adapter_version  text NOT NULL DEFAULT 'v1-hybrid',
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','adapted','published','failed')),
  adapted_at       timestamptz NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (content_piece_id, platform_key)
);

COMMENT ON COLUMN platform_variants.adapter_version IS 'Identifies which adapter produced this row. v1-hybrid = deterministic template + Anthropic hook (per Q4 recommended path).';

CREATE INDEX IF NOT EXISTS platform_variants_content_idx ON platform_variants (content_piece_id);
CREATE INDEX IF NOT EXISTS platform_variants_status_idx  ON platform_variants (status, updated_at DESC) WHERE status IN ('pending','failed');

ALTER TABLE platform_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "platform_variants service_role" ON platform_variants;
CREATE POLICY "platform_variants service_role"
  ON platform_variants FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION platform_variants_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS platform_variants_updated_at ON platform_variants;
CREATE TRIGGER platform_variants_updated_at
  BEFORE UPDATE ON platform_variants
  FOR EACH ROW EXECUTE FUNCTION platform_variants_set_updated_at();

-- ─────────────────────────────────────────────────────────────────────
-- 5. distribution_log
-- ─────────────────────────────────────────────────────────────────────
-- One row per publish attempt. Persists outcome regardless of success.
-- Engagement counters are best-effort, polled by a future workflow.
CREATE TABLE IF NOT EXISTS distribution_log (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_variant_id uuid NOT NULL REFERENCES platform_variants(id) ON DELETE CASCADE,
  content_piece_id    uuid NOT NULL REFERENCES content_pieces(id) ON DELETE CASCADE,
  persona_id          uuid NOT NULL REFERENCES personas(id) ON DELETE RESTRICT,
  platform_key        text NOT NULL,
  status              text NOT NULL CHECK (status IN ('queued','published','failed')),
  external_post_id    text NULL,
  external_post_url   text NULL,
  error_detail        text NULL,
  impressions         integer NOT NULL DEFAULT 0,
  engagements         integer NOT NULL DEFAULT 0,
  click_throughs      integer NOT NULL DEFAULT 0,
  attempted_at        timestamptz NOT NULL DEFAULT now(),
  published_at        timestamptz NULL,
  metrics_polled_at   timestamptz NULL
);

CREATE INDEX IF NOT EXISTS distribution_log_persona_idx ON distribution_log (persona_id, attempted_at DESC);
CREATE INDEX IF NOT EXISTS distribution_log_status_idx  ON distribution_log (status, attempted_at DESC);
CREATE INDEX IF NOT EXISTS distribution_log_platform_idx ON distribution_log (platform_key, attempted_at DESC);

ALTER TABLE distribution_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "distribution_log service_role" ON distribution_log;
CREATE POLICY "distribution_log service_role"
  ON distribution_log FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────
-- 6. persona_usage_log (Tavus minute consumption — billing/caps)
-- ─────────────────────────────────────────────────────────────────────
-- Per-persona Tavus minute consumption. Stripe metering hook will
-- emit usage events keyed by persona.client_id → Stripe customer_id
-- (implementation deferred to Phase 2c).
CREATE TABLE IF NOT EXISTS persona_usage_log (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id          uuid NOT NULL REFERENCES personas(id) ON DELETE RESTRICT,
  client_id           uuid NULL REFERENCES clients(id) ON DELETE CASCADE,
  content_piece_id    uuid NULL REFERENCES content_pieces(id) ON DELETE SET NULL,
  tavus_minutes_used  numeric(10,2) NOT NULL,
  unit_cost_usd_cents integer NULL,
  occurred_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS persona_usage_log_persona_idx ON persona_usage_log (persona_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS persona_usage_log_client_idx  ON persona_usage_log (client_id, occurred_at DESC) WHERE client_id IS NOT NULL;

ALTER TABLE persona_usage_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "persona_usage_log service_role" ON persona_usage_log;
CREATE POLICY "persona_usage_log service_role"
  ON persona_usage_log FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────
-- 7. Additive ALTER TABLE columns on existing tables
-- ─────────────────────────────────────────────────────────────────────
-- ADD COLUMN IF NOT EXISTS ONLY. No DROP, no type modification.
-- Existing workflows ignore these columns; Phase 2b+ retrofits opt in.

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS persona_context_id uuid NULL,
  ADD COLUMN IF NOT EXISTS content_piece_id   uuid NULL;

COMMENT ON COLUMN leads.persona_context_id IS 'Phase 2a: which persona owns this lead''s outreach. NULL = legacy/unassigned.';
COMMENT ON COLUMN leads.content_piece_id   IS 'Phase 2a: optional broker-track linkage to a canonical content_pieces row (e.g., personalized video used in this lead''s outreach).';

-- FKs added separately so re-runs against partial schema don't fail
DO $fk1$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
     WHERE table_schema='public' AND table_name='leads'
       AND constraint_name='leads_persona_context_id_fkey'
  ) THEN
    ALTER TABLE leads
      ADD CONSTRAINT leads_persona_context_id_fkey
      FOREIGN KEY (persona_context_id) REFERENCES personas(id) ON DELETE SET NULL;
  END IF;
END $fk1$;

DO $fk2$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
     WHERE table_schema='public' AND table_name='leads'
       AND constraint_name='leads_content_piece_id_fkey'
  ) THEN
    ALTER TABLE leads
      ADD CONSTRAINT leads_content_piece_id_fkey
      FOREIGN KEY (content_piece_id) REFERENCES content_pieces(id) ON DELETE SET NULL;
  END IF;
END $fk2$;

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS default_persona_id uuid NULL;

COMMENT ON COLUMN clients.default_persona_id IS 'Phase 2a: the client''s primary persona for content generation. NULL = no persona assigned yet.';

DO $fk3$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
     WHERE table_schema='public' AND table_name='clients'
       AND constraint_name='clients_default_persona_id_fkey'
  ) THEN
    ALTER TABLE clients
      ADD CONSTRAINT clients_default_persona_id_fkey
      FOREIGN KEY (default_persona_id) REFERENCES personas(id) ON DELETE SET NULL;
  END IF;
END $fk3$;

-- campaigns is a young table created by 2026-05-01-audit-fixes — guard
-- the ALTER too in case the migration is run before that one (it
-- shouldn't be, but defensive).
DO $cmp$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='campaigns') THEN
    ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS persona_id uuid NULL;
    COMMENT ON COLUMN campaigns.persona_id IS 'Phase 2a: which persona this campaign is run on behalf of. NULL = pre-Phase-2a or unscoped.';

    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints
       WHERE table_schema='public' AND table_name='campaigns'
         AND constraint_name='campaigns_persona_id_fkey'
    ) THEN
      ALTER TABLE campaigns
        ADD CONSTRAINT campaigns_persona_id_fkey
        FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE SET NULL;
    END IF;
  ELSE
    RAISE NOTICE 'campaigns table not present yet — apply 2026-05-01-audit-fixes.sql first or re-run this migration after.';
  END IF;
END $cmp$;

COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- Rollback (manual, single transaction):
--   BEGIN;
--   ALTER TABLE leads
--     DROP CONSTRAINT IF EXISTS leads_content_piece_id_fkey,
--     DROP CONSTRAINT IF EXISTS leads_persona_context_id_fkey,
--     DROP COLUMN IF EXISTS content_piece_id,
--     DROP COLUMN IF EXISTS persona_context_id;
--   ALTER TABLE clients
--     DROP CONSTRAINT IF EXISTS clients_default_persona_id_fkey,
--     DROP COLUMN IF EXISTS default_persona_id;
--   ALTER TABLE campaigns
--     DROP CONSTRAINT IF EXISTS campaigns_persona_id_fkey,
--     DROP COLUMN IF EXISTS persona_id;
--   DROP TABLE IF EXISTS persona_usage_log;
--   DROP TABLE IF EXISTS distribution_log;
--   DROP TABLE IF EXISTS platform_variants;
--   DROP TABLE IF EXISTS content_pieces;
--   DROP TABLE IF EXISTS distribution_platforms;
--   DROP TABLE IF EXISTS personas;
--   DROP FUNCTION IF EXISTS personas_set_updated_at();
--   DROP FUNCTION IF EXISTS distribution_platforms_set_updated_at();
--   DROP FUNCTION IF EXISTS content_pieces_set_updated_at();
--   DROP FUNCTION IF EXISTS platform_variants_set_updated_at();
--   COMMIT;
-- ════════════════════════════════════════════════════════════════════
