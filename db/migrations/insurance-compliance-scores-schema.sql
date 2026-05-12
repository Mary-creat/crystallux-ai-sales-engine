-- ══════════════════════════════════════════════════════════════════
-- Insurance Compliance Scores (Layer 2 — Insurance MGA)
-- ══════════════════════════════════════════════════════════════════
-- Per-MGA compliance scorecard. Computed daily. Insurers consume this
-- to assess MGA risk before deepening or renewing partnerships.
--
-- Every table tagged vertical_id text NOT NULL DEFAULT 'insurance'.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS compliance_scores (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                text NOT NULL DEFAULT 'insurance',
  client_id                  uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,  -- the MGA being scored
  snapshot_date              date NOT NULL DEFAULT CURRENT_DATE,
  overall_score              numeric(5,2) NOT NULL,
  component_scores           jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- { kyc_completion, suitability_documentation, disclosure_completion,
  --   review_completion, license_health, eo_coverage, audit_log_completeness }
  total_files_reviewed       integer DEFAULT 0,
  issues_identified          integer DEFAULT 0,
  risk_level                 text NOT NULL DEFAULT 'medium',          -- low | medium | high | critical
  recommendations            jsonb DEFAULT '[]'::jsonb,
  trend                      text DEFAULT 'stable',                   -- improving | stable | declining
  comparison_to_previous     numeric(5,2),
  created_at                 timestamptz DEFAULT now(),
  UNIQUE (vertical_id, client_id, snapshot_date)
);

DO $$ BEGIN
  ALTER TABLE compliance_scores
    ADD CONSTRAINT cs_risk_check
    CHECK (risk_level IN ('low','medium','high','critical'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE compliance_scores
    ADD CONSTRAINT cs_trend_check
    CHECK (trend IN ('improving','stable','declining'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_cs_client_date
  ON compliance_scores(client_id, snapshot_date DESC);

CREATE INDEX IF NOT EXISTS idx_cs_risk_high
  ON compliance_scores(snapshot_date DESC, risk_level)
  WHERE risk_level IN ('high','critical');

-- ══════════════════════════════════════════════════════════════════
-- Rollback
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS compliance_scores;
