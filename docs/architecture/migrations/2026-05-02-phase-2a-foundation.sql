-- ====================================================================
-- Crystallux Phase 2a -- persona + distribution foundation
-- File:   2026-05-02-phase-2a-foundation.sql (strict-additive variant)
-- Status: Applied to Supabase 2026-05-02 (phase-2a-scaffolding branch).
--         Sections 1-6 unchanged from original draft. Section 7 uses
--         junction tables so leads / clients / campaigns are bit-for-bit
--         untouched (per Mary's strict-additive constraint after Q-review).
-- Idempotent. Safe to re-run.
-- ====================================================================

BEGIN;

-- --------------------------------------------------------------------
-- 1. personas
-- --------------------------------------------------------------------
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
CREATE POLICY "personas service_role" ON personas FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION personas_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS personas_updated_at ON personas;
CREATE TRIGGER personas_updated_at BEFORE UPDATE ON personas FOR EACH ROW EXECUTE FUNCTION personas_set_updated_at();

INSERT INTO personas (persona_key, display_name, persona_type, audience_description) VALUES
  ('mary_broker',  'Mary the Broker',  'internal_broker',  'Insurance prospects (life, RIBO, group benefits) - Mary''s personal book.'),
  ('mary_builder', 'Mary the Builder', 'internal_builder', 'Founders / SMB owners who would buy Crystallux to automate their own outreach.')
ON CONFLICT (persona_key) DO NOTHING;

-- --------------------------------------------------------------------
-- 2. distribution_platforms
-- --------------------------------------------------------------------
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
COMMENT ON TABLE  distribution_platforms IS 'Registry of supported content-distribution platforms. Adding a platform is a row INSERT plus one workflow file.';
COMMENT ON COLUMN distribution_platforms.adapter_workflow IS 'Workflow that transforms a content_pieces row into a platform_variants row.';
COMMENT ON COLUMN distribution_platforms.publish_workflow IS 'Workflow that publishes the adapted variant to the platform.';

CREATE OR REPLACE FUNCTION distribution_platforms_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS distribution_platforms_updated_at ON distribution_platforms;
CREATE TRIGGER distribution_platforms_updated_at BEFORE UPDATE ON distribution_platforms FOR EACH ROW EXECUTE FUNCTION distribution_platforms_set_updated_at();

ALTER TABLE distribution_platforms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "distribution_platforms service_role" ON distribution_platforms;
CREATE POLICY "distribution_platforms service_role" ON distribution_platforms FOR ALL TO service_role USING (true) WITH CHECK (true);

INSERT INTO distribution_platforms
  (platform_key, display_name, adapter_workflow, publish_workflow, max_video_seconds, max_caption_chars, active, notes)
VALUES
  ('linkedin', 'LinkedIn',           'clx-video-platform-adapt', 'clx-video-distribute-linkedin', 600,   3000, true,  'Phase 2a primary'),
  ('youtube',  'YouTube',            'clx-video-platform-adapt', 'clx-video-distribute-youtube',  43200, 5000, true,  'Phase 2a primary'),
  ('twitter',  'Twitter',            'clx-video-platform-adapt', 'clx-video-distribute-twitter',  140,   280,  true,  'Phase 2a primary'),
  ('devto',    'Dev.to',             'clx-video-platform-adapt', 'clx-video-distribute-devto',    NULL,  NULL, false, 'Phase 2c - workflow not scaffolded yet'),
  ('blog',     'crystallux.org/blog','clx-video-platform-adapt', 'clx-video-distribute-blog',     NULL,  NULL, false, 'Phase 2c'),
  ('tiktok',   'TikTok',             'clx-video-platform-adapt', 'clx-video-distribute-tiktok',   600,   2200, false, 'Phase 2d'),
  ('reels',    'Instagram Reels',    'clx-video-platform-adapt', 'clx-video-distribute-reels',    90,    2200, false, 'Phase 2d'),
  ('shorts',   'YouTube Shorts',     'clx-video-platform-adapt', 'clx-video-distribute-shorts',   60,    5000, false, 'Phase 2d')
ON CONFLICT (platform_key) DO NOTHING;

-- --------------------------------------------------------------------
-- 3. content_pieces
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS content_pieces (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  persona_id             uuid NOT NULL REFERENCES personas(id) ON DELETE RESTRICT,
  topic                  text NOT NULL,
  brief                  text NULL,
  script                 text NULL,
  script_model           text NULL,
  niche                  text NULL,
  source_lead_id         uuid NULL REFERENCES leads(id) ON DELETE SET NULL,
  tavus_request_id       text NULL,
  tavus_replica_id       text NULL,
  tavus_video_url        text NULL,
  tavus_thumbnail_url    text NULL,
  tavus_duration_seconds integer NULL,
  status                 text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','generating','ready','failed','archived')),
  status_detail          text NULL,
  track                  text NOT NULL DEFAULT 'broker' CHECK (track IN ('broker','builder','client')),
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  generated_at           timestamptz NULL,
  ready_at               timestamptz NULL
);
COMMENT ON COLUMN content_pieces.source_lead_id IS 'Set ONLY for broker-track personalized content. Outbound FK only - leads table is not modified.';
COMMENT ON COLUMN content_pieces.track          IS 'broker=Mary the Broker outreach; builder=Crystallux marketing; client=tenant client persona content.';
COMMENT ON COLUMN content_pieces.status         IS 'draft -> generating -> ready | failed. archived hides from default queries.';

CREATE INDEX IF NOT EXISTS content_pieces_persona_idx ON content_pieces (persona_id, created_at DESC);
CREATE INDEX IF NOT EXISTS content_pieces_status_idx  ON content_pieces (status) WHERE status IN ('draft','generating','failed');
CREATE INDEX IF NOT EXISTS content_pieces_track_idx   ON content_pieces (track, created_at DESC);
CREATE INDEX IF NOT EXISTS content_pieces_lead_idx    ON content_pieces (source_lead_id) WHERE source_lead_id IS NOT NULL;

ALTER TABLE content_pieces ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "content_pieces service_role" ON content_pieces;
CREATE POLICY "content_pieces service_role" ON content_pieces FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION content_pieces_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS content_pieces_updated_at ON content_pieces;
CREATE TRIGGER content_pieces_updated_at BEFORE UPDATE ON content_pieces FOR EACH ROW EXECUTE FUNCTION content_pieces_set_updated_at();

-- --------------------------------------------------------------------
-- 4. platform_variants
-- --------------------------------------------------------------------
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
COMMENT ON COLUMN platform_variants.adapter_version IS 'Identifies which adapter produced this row. v1-hybrid = deterministic template + Anthropic hook (per Q4).';

CREATE INDEX IF NOT EXISTS platform_variants_content_idx ON platform_variants (content_piece_id);
CREATE INDEX IF NOT EXISTS platform_variants_status_idx  ON platform_variants (status, updated_at DESC) WHERE status IN ('pending','failed');

ALTER TABLE platform_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "platform_variants service_role" ON platform_variants;
CREATE POLICY "platform_variants service_role" ON platform_variants FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION platform_variants_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS platform_variants_updated_at ON platform_variants;
CREATE TRIGGER platform_variants_updated_at BEFORE UPDATE ON platform_variants FOR EACH ROW EXECUTE FUNCTION platform_variants_set_updated_at();

-- --------------------------------------------------------------------
-- 5. distribution_log
-- --------------------------------------------------------------------
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
CREATE INDEX IF NOT EXISTS distribution_log_persona_idx  ON distribution_log (persona_id, attempted_at DESC);
CREATE INDEX IF NOT EXISTS distribution_log_status_idx   ON distribution_log (status, attempted_at DESC);
CREATE INDEX IF NOT EXISTS distribution_log_platform_idx ON distribution_log (platform_key, attempted_at DESC);

ALTER TABLE distribution_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "distribution_log service_role" ON distribution_log;
CREATE POLICY "distribution_log service_role" ON distribution_log FOR ALL TO service_role USING (true) WITH CHECK (true);

-- --------------------------------------------------------------------
-- 6. persona_usage_log
-- --------------------------------------------------------------------
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
CREATE POLICY "persona_usage_log service_role" ON persona_usage_log FOR ALL TO service_role USING (true) WITH CHECK (true);

-- --------------------------------------------------------------------
-- 7. Junction tables (replaces ALTER TABLE on existing tables).
-- Strict additive: leads, clients, campaigns are NOT modified.
-- Inbound FKs are owned by these new junction tables.
-- --------------------------------------------------------------------

-- 7a. lead_persona_links
-- Replaces the previously-proposed leads.persona_context_id and
-- leads.content_piece_id columns. One row per lead at most.
CREATE TABLE IF NOT EXISTS lead_persona_links (
  lead_id          uuid PRIMARY KEY REFERENCES leads(id) ON DELETE CASCADE,
  persona_id       uuid NULL REFERENCES personas(id) ON DELETE SET NULL,
  content_piece_id uuid NULL REFERENCES content_pieces(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE lead_persona_links IS 'Phase 2a junction. Associates a lead with a persona and/or content_piece without modifying the leads table. Existing pipeline ignores this table entirely.';

CREATE INDEX IF NOT EXISTS lead_persona_links_persona_idx ON lead_persona_links (persona_id) WHERE persona_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS lead_persona_links_content_idx ON lead_persona_links (content_piece_id) WHERE content_piece_id IS NOT NULL;

ALTER TABLE lead_persona_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "lead_persona_links service_role" ON lead_persona_links;
CREATE POLICY "lead_persona_links service_role" ON lead_persona_links FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION lead_persona_links_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS lead_persona_links_updated_at ON lead_persona_links;
CREATE TRIGGER lead_persona_links_updated_at BEFORE UPDATE ON lead_persona_links FOR EACH ROW EXECUTE FUNCTION lead_persona_links_set_updated_at();

-- 7b. client_default_personas
-- Replaces the previously-proposed clients.default_persona_id column.
CREATE TABLE IF NOT EXISTS client_default_personas (
  client_id  uuid PRIMARY KEY REFERENCES clients(id) ON DELETE CASCADE,
  persona_id uuid NOT NULL REFERENCES personas(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE client_default_personas IS 'Phase 2a junction. Maps a client to their default persona without modifying the clients table. Existing pipeline ignores this table entirely.';

CREATE INDEX IF NOT EXISTS client_default_personas_persona_idx ON client_default_personas (persona_id);

ALTER TABLE client_default_personas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "client_default_personas service_role" ON client_default_personas;
CREATE POLICY "client_default_personas service_role" ON client_default_personas FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION client_default_personas_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $fn$;
DROP TRIGGER IF EXISTS client_default_personas_updated_at ON client_default_personas;
CREATE TRIGGER client_default_personas_updated_at BEFORE UPDATE ON client_default_personas FOR EACH ROW EXECUTE FUNCTION client_default_personas_set_updated_at();

-- 7c. campaign_persona_links
-- Replaces the previously-proposed campaigns.persona_id column.
-- Guarded for the case where campaigns table does not exist yet.
DO $cmp$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='campaigns') THEN
    CREATE TABLE IF NOT EXISTS campaign_persona_links (
      campaign_id uuid PRIMARY KEY REFERENCES campaigns(id) ON DELETE CASCADE,
      persona_id  uuid NOT NULL REFERENCES personas(id) ON DELETE RESTRICT,
      created_at  timestamptz NOT NULL DEFAULT now()
    );
    COMMENT ON TABLE campaign_persona_links IS 'Phase 2a junction. Maps a campaign to a persona without modifying the campaigns table. Existing pipeline ignores this table entirely.';
    CREATE INDEX IF NOT EXISTS campaign_persona_links_persona_idx ON campaign_persona_links (persona_id);

    ALTER TABLE campaign_persona_links ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "campaign_persona_links service_role" ON campaign_persona_links;
    CREATE POLICY "campaign_persona_links service_role" ON campaign_persona_links FOR ALL TO service_role USING (true) WITH CHECK (true);
  ELSE
    RAISE NOTICE 'campaigns table not present yet. Apply 2026-05-01-audit-fixes.sql first then re-run this migration.';
  END IF;
END $cmp$;

COMMIT;

-- --------------------------------------------------------------------
-- Verification (each must succeed; LIMIT 0 returns no rows by design)
-- --------------------------------------------------------------------
-- SELECT * FROM personas LIMIT 0;
-- SELECT * FROM distribution_platforms LIMIT 0;
-- SELECT * FROM content_pieces LIMIT 0;
-- SELECT * FROM platform_variants LIMIT 0;
-- SELECT * FROM distribution_log LIMIT 0;
-- SELECT * FROM persona_usage_log LIMIT 0;
-- SELECT * FROM lead_persona_links LIMIT 0;
-- SELECT * FROM client_default_personas LIMIT 0;
-- SELECT * FROM campaign_persona_links LIMIT 0;
-- SELECT count(*) AS personas_seeded  FROM personas WHERE persona_key IN ('mary_broker','mary_builder');
-- SELECT count(*) AS platforms_seeded FROM distribution_platforms;

-- --------------------------------------------------------------------
-- Rollback (manual, single transaction):
--   BEGIN;
--   DROP TABLE IF EXISTS campaign_persona_links;
--   DROP TABLE IF EXISTS client_default_personas;
--   DROP TABLE IF EXISTS lead_persona_links;
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
--   DROP FUNCTION IF EXISTS lead_persona_links_set_updated_at();
--   DROP FUNCTION IF EXISTS client_default_personas_set_updated_at();
--   COMMIT;
-- leads, clients, campaigns are bit-for-bit identical to pre-migration.
-- --------------------------------------------------------------------
