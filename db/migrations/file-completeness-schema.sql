-- ══════════════════════════════════════════════════════════════════
-- File Completeness Scoring (Layer 1 — core engine)
-- ══════════════════════════════════════════════════════════════════
-- Universal scoring framework. Works for any client file in any
-- vertical (leads, applications, listings, projects, engagements).
-- Rules are pluggable: platform default + per-vertical override +
-- per-client override.
--
-- LAYER 1 PURITY:
--   - file_completeness_rules.vertical_id is NULLABLE (universal-with-
--     filter). NULL = platform default.
--   - file_completeness_scores has NO vertical_id — universal counter.
--   - No insurance / mga / advisor terminology.
--
-- Additive, idempotent.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS file_completeness_rules (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id         text,                                  -- NULL = platform default
  client_id           uuid REFERENCES clients(id) ON DELETE CASCADE,  -- NULL = vertical/platform default
  file_type           text NOT NULL,                         -- 'lead' | 'policy_application' | 'mortgage_application' | 'listing' | ...
  field_name          text NOT NULL,
  field_table         text NOT NULL,                         -- source table (informational; logic in workflow)
  weight              integer NOT NULL DEFAULT 5,            -- higher = more important
  is_required         boolean DEFAULT false,
  validation_rules    jsonb DEFAULT '{}'::jsonb,             -- { min_length, regex, must_be_in, max_value, ... }
  description         text,
  is_active           boolean DEFAULT true,
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fcr_lookup
  ON file_completeness_rules(file_type, vertical_id, client_id, is_active);

CREATE TABLE IF NOT EXISTS file_completeness_scores (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_file_id         uuid NOT NULL,                       -- soft FK (no REFERENCES — points at the table named in client_file_type)
  client_file_type       text NOT NULL,
  total_score            integer NOT NULL DEFAULT 0,
  max_score              integer NOT NULL DEFAULT 0,
  percentage             numeric(5,2) GENERATED ALWAYS AS (
                           CASE WHEN max_score > 0
                                THEN (total_score::numeric * 100.0 / max_score::numeric)
                                ELSE 0 END
                         ) STORED,
  status                 text NOT NULL DEFAULT 'incomplete',
  field_scores           jsonb DEFAULT '{}'::jsonb,           -- { field_name: { score, max, complete, value_preview } }
  missing_fields         text[] DEFAULT ARRAY[]::text[],
  recommended_actions    text[] DEFAULT ARRAY[]::text[],
  calculated_at          timestamptz DEFAULT now(),
  UNIQUE (client_file_id, client_file_type)
);

DO $$ BEGIN
  ALTER TABLE file_completeness_scores
    ADD CONSTRAINT fcs_status_check
    CHECK (status IN ('incomplete','needs_work','nearly_ready','ready_for_review'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_fcs_file
  ON file_completeness_scores(client_file_id, client_file_type);

CREATE INDEX IF NOT EXISTS idx_fcs_status
  ON file_completeness_scores(status, percentage DESC);

-- ══════════════════════════════════════════════════════════════════
-- Rollback
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS file_completeness_scores;
-- DROP TABLE IF EXISTS file_completeness_rules;
