-- v3_pipeline_rls.sql
-- Enables RLS on pipeline_stats and grants execute on the RPC functions the
-- workflows call. Run once in Supabase SQL editor.
--
-- NOTE: `CREATE POLICY IF NOT EXISTS` is not supported by Postgres, so the
-- idempotent pattern below is DROP POLICY IF EXISTS then CREATE POLICY.
--
-- NOTE: The GRANT EXECUTE lines name specific function signatures. If any
-- signature below does not match what is actually deployed in Supabase, the
-- corresponding GRANT will error. Verify against `\df` or pg_proc before
-- running — or run each GRANT individually so partial failure is obvious.

-- ---------------------------------------------------------------------------
-- 1. pipeline_stats RLS
-- ---------------------------------------------------------------------------
-- Enabling RLS on a table that has no policies blocks ALL access from the
-- anon/authenticated roles until policies are created. If anything else in
-- Supabase (dashboards, other workflows, manual queries) reads pipeline_stats,
-- confirm it still works after this runs.

ALTER TABLE pipeline_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow anon insert on pipeline_stats" ON pipeline_stats;
CREATE POLICY "Allow anon insert on pipeline_stats"
  ON pipeline_stats
  FOR INSERT
  TO anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "Allow anon select on pipeline_stats" ON pipeline_stats;
CREATE POLICY "Allow anon select on pipeline_stats"
  ON pipeline_stats
  FOR SELECT
  TO anon
  USING (true);

-- ---------------------------------------------------------------------------
-- 2. Function execute grants (belt and suspenders)
-- ---------------------------------------------------------------------------
-- The workflows already call update_lead successfully (it has SECURITY DEFINER
-- + grant to anon). These re-grants cover the other RPCs the pipeline uses.

GRANT EXECUTE ON FUNCTION update_lead(uuid, jsonb)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION insert_lead_if_not_exists(text, text, text, text, text, text, text, text, text, text, text)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION upsert_scan_tracker(text, text, text, text, integer)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION update_lead_after_send(uuid, timestamptz, timestamptz, text, text, integer, timestamptz)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION mark_lead_send_failed(uuid, text)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION get_daily_send_count()
  TO anon, authenticated, service_role;
