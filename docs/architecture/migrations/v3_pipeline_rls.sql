-- v3_pipeline_rls.sql
-- Enables RLS on pipeline_stats and re-grants execute on the RPC functions the
-- workflows call. Run once in the Supabase SQL editor.
--
-- ----------------------------------------------------------------------------
-- Function signature audit (verified against repo SQL migrations before shipping)
-- ----------------------------------------------------------------------------
-- All six GRANT EXECUTE signatures below match the CREATE OR REPLACE FUNCTION
-- signatures defined in:
--
--   update_lead(uuid, jsonb)
--     -> docs/architecture/migrations/v2.2.1_fix_update_lead_rpc.sql:28
--
--   insert_lead_if_not_exists(text, text, text, text, text, text, text, text,
--                             text, text, text)   -- 11 text params, all DEFAULT NULL
--     -> docs/architecture/migrations/v2.1_smart_scanning.sql:103
--
--   upsert_scan_tracker(text, text, text, text, integer)
--     -> docs/architecture/migrations/v2.1_smart_scanning.sql:33
--
--   update_lead_after_send(uuid, timestamptz, timestamptz, text, text, integer,
--                          timestamptz)
--     -> docs/architecture/migrations/v2_outreach_sender.sql:12
--
--   mark_lead_send_failed(uuid, text)
--     -> docs/architecture/migrations/v2_outreach_sender.sql:53
--
--   get_daily_send_count()
--     -> docs/architecture/migrations/v2_outreach_sender.sql:78
--
-- If Supabase has drifted from the repo (someone hand-edited a function), the
-- corresponding GRANT will error with "function ... does not exist". Run each
-- GRANT on its own if you need to pinpoint a drift — the RLS block and the
-- six GRANTs are independent statements.
--
-- ----------------------------------------------------------------------------
-- pipeline_stats RLS — operational note
-- ----------------------------------------------------------------------------
-- Enabling RLS on a previously unrestricted table blocks ALL access from the
-- anon/authenticated roles until policies land. The ALTER TABLE and the two
-- CREATE POLICY blocks should be run in a single transaction (psql / SQL
-- editor runs the whole file in one transaction by default) so there is no
-- window where the table is readable-by-nobody. If you run them line by line,
-- run the ALTER TABLE last.
--
-- If anything else in Supabase reads pipeline_stats (dashboards, other
-- workflows, manual queries), sanity-check it still works after this lands.


-- ============================================================================
-- 1. pipeline_stats RLS + idempotent anon policies
-- ============================================================================

ALTER TABLE pipeline_stats ENABLE ROW LEVEL SECURITY;

-- Idempotent CREATE POLICY via DO block (Postgres does not support
-- `CREATE POLICY IF NOT EXISTS`). Swallows the duplicate_object SQLSTATE 42710
-- on re-run so the migration stays idempotent.

DO $$
BEGIN
  CREATE POLICY "Allow anon insert on pipeline_stats"
    ON pipeline_stats
    FOR INSERT
    TO anon
    WITH CHECK (true);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE POLICY "Allow anon select on pipeline_stats"
    ON pipeline_stats
    FOR SELECT
    TO anon
    USING (true);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================================
-- 2. Function execute grants (belt and suspenders)
-- ============================================================================
-- update_lead already has SECURITY DEFINER + a prior GRANT; these statements
-- are idempotent no-ops in the steady state and guarantee role coverage after
-- any future role changes.

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
