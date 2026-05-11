-- ══════════════════════════════════════════════════════════════════
-- Insurance 30-day Onboarding Curriculum (Layer 2 — Insurance MGA)
-- ══════════════════════════════════════════════════════════════════
-- Structured 30-day curriculum each new advisor walks through after
-- their license + E&O verification land. Per-day modules with
-- learning objectives + actions + completion criteria. Supervisor
-- signoff required for graduation.
--
-- Additive only. Idempotent.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS insurance_onboarding_curriculum (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id           text NOT NULL DEFAULT 'insurance',
  day_number            integer NOT NULL,    -- 1..30
  module_title          text NOT NULL,
  module_description    text,
  learning_objectives   text[] DEFAULT ARRAY[]::text[],
  required_actions      text[] DEFAULT ARRAY[]::text[],
  estimated_minutes     integer DEFAULT 30,
  resources             jsonb DEFAULT '[]'::jsonb,
  completion_criteria   jsonb DEFAULT '{}'::jsonb,
  is_mandatory          boolean DEFAULT true,
  is_active             boolean DEFAULT true,
  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now(),
  UNIQUE (vertical_id, day_number)
);

DO $$ BEGIN
  ALTER TABLE insurance_onboarding_curriculum
    ADD CONSTRAINT ioc_day_check
    CHECK (day_number BETWEEN 1 AND 30);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS advisor_onboarding_progress (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id             text NOT NULL DEFAULT 'insurance',
  advisor_id              uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  curriculum_id           uuid NOT NULL REFERENCES insurance_onboarding_curriculum(id),
  status                  text NOT NULL DEFAULT 'pending',  -- pending | in_progress | completed | skipped
  started_at              timestamptz,
  completed_at            timestamptz,
  time_spent_minutes      integer DEFAULT 0,
  notes                   text,
  supervisor_signoff      boolean DEFAULT false,
  supervisor_signoff_at   timestamptz,
  supervisor_signoff_by   uuid REFERENCES auth_users(id),
  created_at              timestamptz DEFAULT now(),
  updated_at              timestamptz DEFAULT now(),
  UNIQUE (advisor_id, curriculum_id)
);

DO $$ BEGIN
  ALTER TABLE advisor_onboarding_progress
    ADD CONSTRAINT aop_status_check
    CHECK (status IN ('pending','in_progress','completed','skipped'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_aop_advisor
  ON advisor_onboarding_progress(advisor_id, status);

-- ══════════════════════════════════════════════════════════════════
-- Rollback
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS advisor_onboarding_progress;
-- DROP TABLE IF EXISTS insurance_onboarding_curriculum;
