-- ══════════════════════════════════════════════════════════════════
-- Training Coach Chat (Layer 1 — core engine, universal framework)
-- ══════════════════════════════════════════════════════════════════
-- Universal training framework. Topics can be universal (vertical_id
-- NULL) or vertical-specific (vertical_id set). The framework itself
-- is Layer 1 — verticals only contribute content via seed workflows.
--
-- LAYER 1 PURITY:
--   - training_topics.vertical_id is NULLABLE — universal-with-filter
--     pattern. NULL means "applies to any vertical".
--   - No insurance / mga / advisor terminology in column names.
--
-- Additive, idempotent.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS training_topics (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id           text,                                  -- NULL = universal; set = vertical-specific
  topic_category        text NOT NULL,
  topic_title           text NOT NULL,
  topic_description     text,
  difficulty_level      text DEFAULT 'beginner',
  estimated_minutes     integer DEFAULT 15,
  prerequisites         text[] DEFAULT ARRAY[]::text[],
  learning_objectives   text[] DEFAULT ARRAY[]::text[],
  content_outline       jsonb DEFAULT '{}'::jsonb,
  ai_coaching_prompts   jsonb DEFAULT '{}'::jsonb,
  is_active             boolean DEFAULT true,
  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE training_topics
    ADD CONSTRAINT tt_category_check
    CHECK (topic_category IN ('discovery','product_knowledge','objection_handling','closing','compliance','follow_up','sales_psychology','communication'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE training_topics
    ADD CONSTRAINT tt_difficulty_check
    CHECK (difficulty_level IN ('beginner','intermediate','advanced'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_tt_vertical
  ON training_topics(vertical_id, topic_category)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_tt_universal
  ON training_topics(topic_category)
  WHERE vertical_id IS NULL AND is_active = true;

CREATE TABLE IF NOT EXISTS training_sessions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  topic_id            uuid REFERENCES training_topics(id) ON DELETE SET NULL,
  session_messages    jsonb NOT NULL DEFAULT '[]'::jsonb,
  duration_seconds    integer DEFAULT 0,
  completed           boolean DEFAULT false,
  user_rating         integer,                                  -- 1-5
  feedback_notes      text,
  competency_score    numeric(5,2),                             -- 0-100 derived from chat performance
  started_at          timestamptz DEFAULT now(),
  completed_at        timestamptz,
  last_activity_at    timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE training_sessions
    ADD CONSTRAINT ts_rating_check
    CHECK (user_rating IS NULL OR (user_rating BETWEEN 1 AND 5));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ts_user
  ON training_sessions(user_id, last_activity_at DESC);

CREATE INDEX IF NOT EXISTS idx_ts_user_completed
  ON training_sessions(user_id, completed, completed_at DESC);

-- ══════════════════════════════════════════════════════════════════
-- Rollback
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS training_sessions;
-- DROP TABLE IF EXISTS training_topics;
