-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX ADMIN COPILOT — SCHEMA SCAFFOLDING (Phase 8)
-- File: docs/architecture/migrations/2026-04-24-admin-copilot.sql
--
-- Backing tables + RPCs for the Admin Copilot feature (persistent
-- conversational AI layer embedded in the admin dashboard).
--
-- Includes:
--   1. admin_action_log — audit trail of every copilot interaction
--   2. scan_errors: resolved, resolved_at, resolution_notes columns
--   3. admin_execute_select RPC — SELECT-only safe query executor
--   4. mark_error_resolved RPC — used by the Troubleshoot copilot
--
-- Idempotent — safe to re-run. Rollback SQL trailing.
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. ADMIN_ACTION_LOG TABLE
-- ─────────────────────────────────────────────────────────────────
-- Append-only log of every interaction with the Admin Copilot (and
-- the verify-access workflow from Phase 1). Enables audit, cost
-- analysis, usage-pattern mining, and future security review.

CREATE TABLE IF NOT EXISTS admin_action_log (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user         text DEFAULT 'mary',
  action_type        text,
  input_text         text,
  panel_context      text,
  generated_content  jsonb,
  result_summary     text,
  success            boolean DEFAULT true,
  error_message      text,
  created_at         timestamptz DEFAULT now()
);

-- Check constraint guards the enumeration. Use DO block for idempotency.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'admin_action_log_action_type_check'
  ) THEN
    ALTER TABLE admin_action_log
      ADD CONSTRAINT admin_action_log_action_type_check
      CHECK (action_type IN (
        'db_query',
        'troubleshoot_initiated',
        'troubleshoot_resolved',
        'feature_question',
        'error_resolved',
        'vertical_generated'
      ));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_admin_action_log_created_at
  ON admin_action_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_action_log_type
  ON admin_action_log(action_type, created_at DESC);

ALTER TABLE admin_action_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_action_log_service_role_all ON admin_action_log;
CREATE POLICY admin_action_log_service_role_all ON admin_action_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 2. SCAN_ERRORS: RESOLVED TRACKING
-- ─────────────────────────────────────────────────────────────────
-- Lets the Troubleshoot copilot mark an error as resolved with
-- operator notes. Existing scan_errors rows default to unresolved.

ALTER TABLE scan_errors
  ADD COLUMN IF NOT EXISTS resolved          boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS resolved_at       timestamptz,
  ADD COLUMN IF NOT EXISTS resolution_notes  text;

CREATE INDEX IF NOT EXISTS idx_scan_errors_unresolved
  ON scan_errors(created_at DESC)
  WHERE resolved = false;


-- ─────────────────────────────────────────────────────────────────
-- 3. ADMIN_EXECUTE_SELECT RPC (SELECT-only safe executor)
-- ─────────────────────────────────────────────────────────────────
-- Called by the DB Query copilot workflow after Claude generates a
-- SQL statement. Enforces:
--   * SELECT or WITH prefix (uppercased) only
--   * Regex blacklist on write keywords (INSERT, UPDATE, DELETE,
--     DROP, ALTER, TRUNCATE, CREATE, GRANT, REVOKE) as whole words
--   * Returns the result as JSONB (one row per result record)
--
-- SECURITY DEFINER so the copilot workflow can call it via service_role
-- without needing direct-table reads. Hardcoded search_path defence.

CREATE OR REPLACE FUNCTION admin_execute_select(p_query text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
  safe_query text;
BEGIN
  IF p_query IS NULL OR length(trim(p_query)) = 0 THEN
    RAISE EXCEPTION 'Empty query';
  END IF;

  safe_query := upper(trim(p_query));

  IF NOT (safe_query LIKE 'SELECT%' OR safe_query LIKE 'WITH%') THEN
    RAISE EXCEPTION 'Only SELECT or WITH queries allowed';
  END IF;

  -- Whole-word blacklist (whitespace or statement start/end delimited)
  IF safe_query ~* '(\s|;|^)(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE|VACUUM|CLUSTER|LOCK)(\s|;|$)' THEN
    RAISE EXCEPTION 'Write or DDL operations not permitted';
  END IF;

  -- Reject semicolons to prevent stacked statements (Postgres allows
  -- multi-statement in a single EXECUTE which could smuggle a write).
  IF position(';' IN p_query) > 0 AND position(';' IN p_query) < length(p_query) THEN
    RAISE EXCEPTION 'Semicolons not permitted inside the query';
  END IF;

  EXECUTE 'SELECT jsonb_agg(row_to_json(t)) FROM (' || p_query || ') t' INTO result;
  RETURN COALESCE(result, '[]'::jsonb);

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Query failed: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_execute_select(text) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 4. MARK_ERROR_RESOLVED RPC
-- ─────────────────────────────────────────────────────────────────
-- Called by the Troubleshoot copilot when Mary clicks the "Mark
-- Resolved" action. Writes resolved=true, resolved_at=now(),
-- resolution_notes, and logs the action to admin_action_log.

CREATE OR REPLACE FUNCTION mark_error_resolved(
  p_error_id uuid,
  p_resolution_notes text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_error_id IS NULL THEN
    RAISE EXCEPTION 'p_error_id required';
  END IF;

  UPDATE scan_errors
  SET resolved = true,
      resolved_at = now(),
      resolution_notes = COALESCE(p_resolution_notes, resolution_notes)
  WHERE id = p_error_id;

  INSERT INTO admin_action_log (action_type, input_text, result_summary, success)
  VALUES (
    'error_resolved',
    'scan_errors.id=' || p_error_id::text,
    COALESCE(p_resolution_notes, 'resolved without notes'),
    true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION mark_error_resolved(uuid, text) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 5. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 1
SELECT 'admin_action_log table' AS check_name, COUNT(*) AS present
FROM information_schema.tables WHERE table_name = 'admin_action_log';

-- Expect 3 (resolved, resolved_at, resolution_notes)
SELECT 'scan_errors resolved columns' AS check_name, COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'scan_errors'
  AND column_name IN ('resolved', 'resolved_at', 'resolution_notes');

-- Expect 2
SELECT 'copilot RPCs' AS check_name, COUNT(*) AS present
FROM information_schema.routines
WHERE routine_name IN ('admin_execute_select', 'mark_error_resolved');

-- Smoke test: admin_execute_select should accept a trivial SELECT
SELECT admin_execute_select('SELECT 1 AS ok');
-- and reject a write
-- SELECT admin_execute_select('DROP TABLE leads');  -- would raise


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ═══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS mark_error_resolved(uuid, text);
-- DROP FUNCTION IF EXISTS admin_execute_select(text);
-- DROP INDEX IF EXISTS idx_scan_errors_unresolved;
-- ALTER TABLE scan_errors
--   DROP COLUMN IF EXISTS resolution_notes,
--   DROP COLUMN IF EXISTS resolved_at,
--   DROP COLUMN IF EXISTS resolved;
-- DROP INDEX IF EXISTS idx_admin_action_log_type;
-- DROP INDEX IF EXISTS idx_admin_action_log_created_at;
-- ALTER TABLE admin_action_log
--   DROP CONSTRAINT IF EXISTS admin_action_log_action_type_check;
-- DROP TABLE IF EXISTS admin_action_log;
