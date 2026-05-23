-- ══════════════════════════════════════════════════════════════════
-- Workflow Drift Detection
-- ══════════════════════════════════════════════════════════════════
-- Tracks divergence between the repo (source of truth) and the live
-- n8n state. Run scripts/drift/detect-workflow-drift.py via cron on
-- the VPS to populate this table.
--
-- Drift types:
--   repo_only     — JSON exists in repo, never imported to n8n
--   n8n_only      — workflow active in n8n but no matching JSON in repo
--                   (likely UI-created, needs commit-back or delete)
--   content_diff  — same workflow id on both sides, but content hash
--                   differs (someone edited in n8n UI without
--                   committing back, OR a repo edit isn't shipped yet)
--   active_diff   — same content, but active flag differs (n8n thinks
--                   workflow is on/off, repo says otherwise)
--
-- Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS workflow_drift (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id     text NOT NULL,
  workflow_name   text,
  drift_type      text NOT NULL,
  repo_hash       text,
  n8n_hash        text,
  repo_active     boolean,
  n8n_active      boolean,
  repo_path       text,
  details         jsonb,
  detected_at     timestamptz DEFAULT now(),
  resolved_at     timestamptz,
  resolution_notes text
);

DO $$ BEGIN
  ALTER TABLE workflow_drift
    ADD CONSTRAINT wfd_type_check
    CHECK (drift_type IN ('repo_only','n8n_only','content_diff','active_diff'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_wfd_unresolved
  ON workflow_drift(detected_at DESC)
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_wfd_workflow
  ON workflow_drift(workflow_id, detected_at DESC);

-- ══════════════════════════════════════════════════════════════════
-- Run-summary table — one row per detection run for trend tracking
-- ══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS workflow_drift_runs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at          timestamptz DEFAULT now(),
  repo_count      int,
  n8n_count       int,
  drift_count     int,
  repo_only       int,
  n8n_only        int,
  content_diff    int,
  active_diff     int,
  duration_ms     int,
  metadata        jsonb
);

CREATE INDEX IF NOT EXISTS idx_wfdr_recent
  ON workflow_drift_runs(ran_at DESC);

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS workflow_drift_runs;
-- DROP TABLE IF EXISTS workflow_drift;
