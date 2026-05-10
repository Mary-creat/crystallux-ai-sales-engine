-- ══════════════════════════════════════════════════════════════════
-- Content marketing schema (Phase 4 prep — schema only, no workflows)
-- ══════════════════════════════════════════════════════════════════
-- Spec: Phase 2/3 build brief Part E + docs/agent/content-marketing-vision.md.
-- Universal multi-vertical: same 4 personas + look variants serve
-- BOTH 1:1 outreach (Phase 2 video pipeline) AND 1:N content marketing
-- (Phase 4 — workflows deferred). Tables here are the foundation for
-- Phase 4 build; no production code reads or writes them yet.
--
-- Additive only. Idempotent (IF NOT EXISTS). Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. content_topics — proposed topics per vertical
-- ─────────────────────────────────────────────────────────────────
-- Topics emerge from market_signals + behavioral_signals patterns.
-- AI proposes, human or admin approves, content_videos render.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS content_topics (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical           text NOT NULL,                 -- 'insurance' | 'mortgage' | 'real_estate' | 'dental' | etc.
  topic_title        text NOT NULL,
  topic_description  text,
  source_signal_id   uuid,                          -- soft-FK: may reference market_signals OR behavioral_signals.id
  generated_by       text DEFAULT 'ai',             -- 'ai' | 'human' | 'admin'
  status             text DEFAULT 'proposed',       -- proposed | approved | in_production | published | archived
  priority_score     integer,                       -- 0-100
  created_at         timestamptz DEFAULT now(),
  approved_at        timestamptz,
  approved_by        uuid REFERENCES auth_users(id) ON DELETE SET NULL
);

DO $$ BEGIN
  ALTER TABLE content_topics
    ADD CONSTRAINT ct_status_check
    CHECK (status IN ('proposed','approved','in_production','published','archived'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE content_topics
    ADD CONSTRAINT ct_generated_by_check
    CHECK (generated_by IN ('ai','human','admin'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ct_vertical    ON content_topics(vertical);
CREATE INDEX IF NOT EXISTS idx_ct_status      ON content_topics(status);
CREATE INDEX IF NOT EXISTS idx_ct_priority    ON content_topics(priority_score DESC) WHERE status IN ('proposed','approved');

-- ─────────────────────────────────────────────────────────────────
-- 2. content_videos — rendered content videos (HeyGen)
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS content_videos (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_topic_id   uuid REFERENCES content_topics(id) ON DELETE SET NULL,
  client_id          uuid REFERENCES clients(id) ON DELETE CASCADE,    -- nullable: platform-level content has client_id NULL
  vertical           text,
  persona_id         text,
  look_id            text,
  voice_id           text,
  script             text,
  heygen_video_id    text UNIQUE,
  storage_url        text,                          -- R2 permanent URL
  duration_seconds   integer,
  cost_cents         integer,
  status             text DEFAULT 'draft',          -- draft | rendering | ready | published | archived
  approved_by        uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  approved_at        timestamptz,
  created_at         timestamptz DEFAULT now(),
  rendered_at        timestamptz,
  published_at       timestamptz
);

DO $$ BEGIN
  ALTER TABLE content_videos
    ADD CONSTRAINT cv_status_check
    CHECK (status IN ('draft','rendering','ready','published','archived'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_cv_topic       ON content_videos(content_topic_id);
CREATE INDEX IF NOT EXISTS idx_cv_client      ON content_videos(client_id);
CREATE INDEX IF NOT EXISTS idx_cv_vertical    ON content_videos(vertical);
CREATE INDEX IF NOT EXISTS idx_cv_status      ON content_videos(status);

-- ─────────────────────────────────────────────────────────────────
-- 3. content_publications — per-platform schedule + publish
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS content_publications (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_video_id   uuid REFERENCES content_videos(id) ON DELETE CASCADE,
  client_id          uuid REFERENCES clients(id) ON DELETE CASCADE,
  platform           text NOT NULL,                 -- linkedin | instagram | youtube | facebook | tiktok | x
  external_post_id   text,
  post_url           text,
  scheduled_for      timestamptz,
  published_at       timestamptz,
  status             text DEFAULT 'scheduled',      -- scheduled | published | failed | archived
  error_message      text,
  created_at         timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE content_publications
    ADD CONSTRAINT cp_platform_check
    CHECK (platform IN ('linkedin','instagram','youtube','facebook','tiktok','x'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE content_publications
    ADD CONSTRAINT cp_status_check
    CHECK (status IN ('scheduled','published','failed','archived'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_cp_video       ON content_publications(content_video_id);
CREATE INDEX IF NOT EXISTS idx_cp_client      ON content_publications(client_id, scheduled_for);
CREATE INDEX IF NOT EXISTS idx_cp_platform    ON content_publications(platform);
CREATE INDEX IF NOT EXISTS idx_cp_due         ON content_publications(scheduled_for) WHERE status = 'scheduled';

-- ─────────────────────────────────────────────────────────────────
-- 4. content_engagement — per-publication metrics over time
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS content_engagement (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_publication_id   uuid REFERENCES content_publications(id) ON DELETE CASCADE,
  views                    integer DEFAULT 0,
  likes                    integer DEFAULT 0,
  comments                 integer DEFAULT 0,
  shares                   integer DEFAULT 0,
  click_throughs           integer DEFAULT 0,
  bookings_attributed      integer DEFAULT 0,
  measured_at              timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ce_publication ON content_engagement(content_publication_id, measured_at DESC);

-- ─────────────────────────────────────────────────────────────────
-- 5. client_content_preferences — per-client posting prefs
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS client_content_preferences (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE UNIQUE,
  enabled                     boolean DEFAULT false,
  publishing_frequency        text,                            -- daily | 3x_weekly | weekly | bi_weekly
  preferred_platforms         text[] DEFAULT ARRAY[]::text[],
  preferred_posting_times     jsonb DEFAULT '{}'::jsonb,       -- { mon: ['09:00','17:00'], ... }
  preferred_persona_id        text,
  preferred_look_id           text,
  topics_to_avoid             text[] DEFAULT ARRAY[]::text[],
  topics_priority             text[] DEFAULT ARRAY[]::text[],
  approval_required           boolean DEFAULT true,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE client_content_preferences
    ADD CONSTRAINT ccp_freq_check
    CHECK (publishing_frequency IS NULL OR publishing_frequency IN ('daily','3x_weekly','weekly','bi_weekly'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ccp_client ON client_content_preferences(client_id) WHERE enabled = true;

-- ─────────────────────────────────────────────────────────────────
-- 6. RLS — service_role-only
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE content_topics              ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_videos              ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_publications        ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_engagement          ENABLE ROW LEVEL SECURITY;
ALTER TABLE client_content_preferences  ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN CREATE POLICY ct_service_role  ON content_topics             FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY cv_service_role  ON content_videos             FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY cp_service_role  ON content_publications       FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ce_service_role  ON content_engagement         FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ccp_service_role ON client_content_preferences FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 7. Verification
-- ─────────────────────────────────────────────────────────────────

-- SELECT tablename FROM pg_tables WHERE tablename LIKE 'content_%' OR tablename = 'client_content_preferences' ORDER BY tablename;

-- ═════════════════════════════════════════════════════════════════
-- ROLLBACK (commented — uncomment + run only to roll back)
-- ═════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS client_content_preferences;
-- DROP TABLE IF EXISTS content_engagement;
-- DROP TABLE IF EXISTS content_publications;
-- DROP TABLE IF EXISTS content_videos;
-- DROP TABLE IF EXISTS content_topics;
