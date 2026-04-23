-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX VIDEO OUTREACH — SCHEMA SCAFFOLDING (Part B.7)
-- File: docs/architecture/migrations/2026-04-23-video-schema.sql
--
-- Adds the schema surface the Tavus video outreach workflows will write
-- into. Schema-only — no live Tavus calls. The matching workflows ship
-- active=false with placeholder credential notes only. Activation steps
-- live in OPERATIONS_HANDBOOK §15.
--
-- Idempotent — safe to re-run. All column adds use IF NOT EXISTS,
-- table creates use IF NOT EXISTS, policies DROP ... IF EXISTS first.
--
-- Runs AFTER:
--   * 2026-04-23-apollo-schema.sql
--   * 2026-04-23-multi-channel.sql
--
-- Rollback SQL at the bottom (commented).
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. VIDEO FIELDS ON leads
-- ─────────────────────────────────────────────────────────────────
-- video_request_id      — provider-side ID returned by the generation
--                         API (Tavus video_id). Used to correlate the
--                         async ready callback to the originating lead.
-- video_url             — final hosted MP4/HLS URL delivered by the
--                         provider once rendering completes.
-- video_status          — 'generating' | 'ready' | 'failed' | 'delivered'
-- video_delivered_at    — timestamp the video-embedded email landed
--                         in the lead's inbox.
-- video_script          — the personalised script the video was rendered
--                         against. Kept for audit + A/B analysis.

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS video_request_id    text,
  ADD COLUMN IF NOT EXISTS video_url           text,
  ADD COLUMN IF NOT EXISTS video_status        text,
  ADD COLUMN IF NOT EXISTS video_delivered_at  timestamptz,
  ADD COLUMN IF NOT EXISTS video_script        text;

CREATE INDEX IF NOT EXISTS idx_leads_video_request_id
  ON leads(video_request_id)
  WHERE video_request_id IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────
-- 2. VIDEO_GENERATION_LOG (NEW — per-generation audit trail)
-- ─────────────────────────────────────────────────────────────────
-- Captures one row per generation request (success or fail). Cross-
-- channel state lives in outreach_log; this table carries the
-- provider-specific render metadata (script, duration, cost_usd) used
-- for reconciliation against the Tavus invoice.

CREATE TABLE IF NOT EXISTS video_generation_log (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id        uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id      uuid REFERENCES clients(id) ON DELETE SET NULL,
  request_id     text,
  provider       text NOT NULL DEFAULT 'tavus',
  script         text,
  cost_usd       numeric(10,4),
  duration_sec   integer,
  thumbnail_url  text,
  video_url      text,
  status         text,
  generated_at   timestamptz DEFAULT now(),
  completed_at   timestamptz,
  metadata       jsonb,
  created_at     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_video_gen_log_lead
  ON video_generation_log(lead_id);
CREATE INDEX IF NOT EXISTS idx_video_gen_log_client
  ON video_generation_log(client_id, generated_at);
CREATE INDEX IF NOT EXISTS idx_video_gen_log_request
  ON video_generation_log(request_id)
  WHERE request_id IS NOT NULL;

ALTER TABLE video_generation_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS video_generation_log_service_role_all ON video_generation_log;
CREATE POLICY video_generation_log_service_role_all ON video_generation_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 3. VIDEO FIELDS ON clients
-- ─────────────────────────────────────────────────────────────────
-- video_monthly_cap  — hard ceiling on generations per calendar month
--                      per client. Tavus bills per render; the cap is
--                      the client's monthly budget converted to units.
--                      50 = ~$50/mo at $1/video.
-- video_enabled      — allowlist gate. Defaults false — a client must
--                      be explicitly flipped on once Tavus credential
--                      + replica_id are configured for them.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS video_monthly_cap integer DEFAULT 50,
  ADD COLUMN IF NOT EXISTS video_enabled     boolean DEFAULT false;


-- ─────────────────────────────────────────────────────────────────
-- 4. NICHE OVERLAY — VIDEO SCRIPT TEMPLATE
-- ─────────────────────────────────────────────────────────────────
-- Per-niche script skeleton. At generation time, the video-outreach
-- workflow interpolates {first_name} / {company} / {city} / {industry}
-- and hands the result to Claude Haiku for light personalisation,
-- then sends to Tavus.

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS video_script_template text;

-- Seed the insurance_broker overlay with a 60-second peer-advisor
-- script. Guarded so re-runs don't overwrite Mary's edits.
UPDATE niche_overlays
SET video_script_template = 'Hey {first_name}, quick 60 seconds. I''m Mary — I run Crystallux and I work with insurance brokers across Canada. I noticed {company} focuses on the {city} market, and I wanted to reach out peer-to-peer. Here''s what I''m seeing with brokers right now: renewal season is brutal on retention, and the brokers who automate the 60-day-before-renewal touch are quietly dominating. We built a system that runs that whole sequence for you — zero manual follow-up. My founding broker clients are booking ten discovery meetings a month off it. If you have 20 minutes, I''d love to show you how it works, specifically tuned to {company}. I''ll drop a Calendly link in the follow-up email. Talk soon.'
WHERE niche_name = 'insurance_broker'
  AND video_script_template IS NULL;


-- ─────────────────────────────────────────────────────────────────
-- 5. MONTHLY COUNT RPC (per-client video budget gate)
-- ─────────────────────────────────────────────────────────────────
-- Mirrors the daily-count RPCs from the multi-channel migration.
-- Called by clx-video-outreach-v1 pre-flight to gate against each
-- client's video_monthly_cap. Uses calendar month (not rolling 30d)
-- to line up with Tavus billing cycles.

CREATE OR REPLACE FUNCTION get_monthly_video_count(p_client_id uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM video_generation_log
  WHERE generated_at >= date_trunc('month', now())
    AND generated_at <  date_trunc('month', now()) + interval '1 month'
    AND (p_client_id IS NULL OR client_id = p_client_id);
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION get_monthly_video_count(uuid) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 6. MONITORING THRESHOLDS
-- ─────────────────────────────────────────────────────────────────
-- Matches the error codes clx-video-outreach-v1 and clx-video-ready-v1
-- emit to scan_errors. ON CONFLICT DO NOTHING so re-runs don't stomp
-- thresholds Mary has tuned in the dashboard.

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('VIDEO_GENERATION_FAILED', 10, 5, 'warning'),
  ('VIDEO_DELIVERY_FAILED',   10, 5, 'warning')
ON CONFLICT (error_code) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 7. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 5
SELECT 'leads video columns' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'video_request_id','video_url','video_status',
    'video_delivered_at','video_script'
  );

-- Expect 1
SELECT 'video_generation_log table' AS check_name,
       COUNT(*) AS present
FROM information_schema.tables
WHERE table_name = 'video_generation_log';

-- Expect 2
SELECT 'clients video columns' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'clients'
  AND column_name IN ('video_monthly_cap','video_enabled');

-- Expect 1
SELECT 'niche_overlays.video_script_template' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'niche_overlays'
  AND column_name = 'video_script_template';

-- Expect 1
SELECT 'get_monthly_video_count RPC' AS check_name,
       COUNT(*) AS present
FROM information_schema.routines
WHERE routine_name = 'get_monthly_video_count';

-- Expect 1 row with a non-null script
SELECT niche_name,
       length(video_script_template) AS script_len
FROM niche_overlays
WHERE niche_name = 'insurance_broker';


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo — test on staging first)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 6. Monitoring thresholds
-- DELETE FROM monitoring_thresholds
-- WHERE error_code IN ('VIDEO_GENERATION_FAILED','VIDEO_DELIVERY_FAILED');
--
-- -- 5. Monthly count RPC
-- DROP FUNCTION IF EXISTS get_monthly_video_count(uuid);
--
-- -- 4. Niche overlay video column
-- ALTER TABLE niche_overlays DROP COLUMN IF EXISTS video_script_template;
--
-- -- 3. Clients video columns
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS video_monthly_cap,
--   DROP COLUMN IF EXISTS video_enabled;
--
-- -- 2. Video generation log
-- DROP TABLE IF EXISTS video_generation_log CASCADE;
--
-- -- 1. Leads video columns
-- DROP INDEX IF EXISTS idx_leads_video_request_id;
-- ALTER TABLE leads
--   DROP COLUMN IF EXISTS video_request_id,
--   DROP COLUMN IF EXISTS video_url,
--   DROP COLUMN IF EXISTS video_status,
--   DROP COLUMN IF EXISTS video_delivered_at,
--   DROP COLUMN IF EXISTS video_script;
