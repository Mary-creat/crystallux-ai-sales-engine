-- ══════════════════════════════════════════════════════════════════
-- Client-Facing Productivity Indicator (B.12b-2 / Component 5)
-- ══════════════════════════════════════════════════════════════════
-- Per-agent productivity tracking with consent-gated data collection,
-- AI-classified activities, and traffic-light dashboards for both
-- the agent (self-view, private by default) and the admin/manager
-- (aggregate team view, only agents who opted in + shared).
--
-- Privacy model: COACHING NOT SURVEILLANCE. Nothing is tracked
-- without agent consent. Consent recorded with version so future
-- policy changes can force re-consent.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. agent_activity_log — per-event log of agent work
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_activity_log (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id          uuid,                        -- FK loose; team_members id
  client_id         uuid REFERENCES clients(id) ON DELETE CASCADE,
  activity_type     text,                        -- see CHECK below
  activity_metadata jsonb DEFAULT '{}'::jsonb,
  classification    text DEFAULT 'unknown',      -- see CHECK below
  minutes_duration  integer,
  started_at        timestamptz,
  ended_at          timestamptz,
  created_at        timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE agent_activity_log
    ADD CONSTRAINT agent_activity_log_type_check
    CHECK (activity_type IN (
      'outreach_sent','call_made','meeting_held','follow_up_sent',
      'lead_qualified','deal_closed','dashboard_session','idle','manual_note'
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE agent_activity_log
    ADD CONSTRAINT agent_activity_log_classification_check
    CHECK (classification IN ('productive','neutral','unproductive','unknown'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_activity_agent_date
  ON agent_activity_log(agent_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_client_date
  ON agent_activity_log(client_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_classification
  ON agent_activity_log(classification, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_unclassified
  ON agent_activity_log(id) WHERE classification = 'unknown';

-- ─────────────────────────────────────────────────────────────────
-- 2. agent_daily_summary — rolled-up per-day view
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agent_daily_summary (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id               uuid NOT NULL,
  client_id              uuid REFERENCES clients(id) ON DELETE CASCADE,
  summary_date           date NOT NULL,
  total_minutes_tracked  integer DEFAULT 0,
  productive_minutes     integer DEFAULT 0,
  neutral_minutes        integer DEFAULT 0,
  unproductive_minutes   integer DEFAULT 0,
  productivity_score     numeric(5,2),
  calls_made             integer DEFAULT 0,
  emails_sent            integer DEFAULT 0,
  meetings_held          integer DEFAULT 0,
  follow_ups_sent        integer DEFAULT 0,
  leads_qualified        integer DEFAULT 0,
  deals_closed           integer DEFAULT 0,
  trend                  text DEFAULT 'insufficient_data',
  coaching_flags         jsonb DEFAULT '[]'::jsonb,
  generated_at           timestamptz DEFAULT now(),
  UNIQUE(agent_id, summary_date)
);

DO $$ BEGIN
  ALTER TABLE agent_daily_summary
    ADD CONSTRAINT agent_daily_summary_trend_check
    CHECK (trend IN ('improving','stable','declining','insufficient_data'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_summary_agent_date
  ON agent_daily_summary(agent_id, summary_date DESC);
CREATE INDEX IF NOT EXISTS idx_summary_client_date
  ON agent_daily_summary(client_id, summary_date DESC);

-- ─────────────────────────────────────────────────────────────────
-- 3. team_members consent columns (additive, safe if pre-existing)
-- ─────────────────────────────────────────────────────────────────
-- team_members was created by 2026-04-18-full-platform-foundation.sql
-- If it doesn't exist for some reason we create a minimal stub so
-- the ALTERs below don't fail. Production already has the full table.

CREATE TABLE IF NOT EXISTS team_members (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id  uuid REFERENCES clients(id) ON DELETE CASCADE,
  email      text,
  full_name  text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE team_members ADD COLUMN IF NOT EXISTS productivity_tracking_consent         boolean DEFAULT false;
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS productivity_tracking_consent_at      timestamptz;
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS productivity_tracking_consent_version text;
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS share_with_manager                    boolean DEFAULT false;

-- ─────────────────────────────────────────────────────────────────
-- 4. clients tier flag
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE clients ADD COLUMN IF NOT EXISTS productivity_tier_enabled boolean       DEFAULT false;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS productivity_tier_price   numeric(10,2);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS productivity_tier_enabled_at timestamptz;

-- ─────────────────────────────────────────────────────────────────
-- 5. RLS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE agent_activity_log   ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_daily_summary  ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY agent_activity_log_service_role_all ON agent_activity_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY agent_daily_summary_service_role_all ON agent_daily_summary
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 6. RPCs
-- ─────────────────────────────────────────────────────────────────

-- 6.1 Consent-gated activity write. Returns the inserted id or
-- NULL if the agent hasn't consented.
CREATE OR REPLACE FUNCTION record_agent_activity(
  p_agent_id       uuid,
  p_client_id      uuid,
  p_activity_type  text,
  p_metadata       jsonb,
  p_duration_min   integer,
  p_started_at     timestamptz DEFAULT now(),
  p_ended_at       timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_consent boolean;
  v_id uuid;
BEGIN
  SELECT COALESCE(productivity_tracking_consent, false)
    INTO v_consent
    FROM team_members
   WHERE id = p_agent_id;

  IF NOT COALESCE(v_consent, false) THEN
    RETURN NULL;
  END IF;

  INSERT INTO agent_activity_log (
    agent_id, client_id, activity_type, activity_metadata,
    minutes_duration, started_at, ended_at
  )
  VALUES (
    p_agent_id, p_client_id, p_activity_type, COALESCE(p_metadata,'{}'::jsonb),
    p_duration_min, p_started_at, p_ended_at
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION record_agent_activity(uuid, uuid, text, jsonb, integer, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION record_agent_activity(uuid, uuid, text, jsonb, integer, timestamptz, timestamptz) TO service_role;

-- 6.2 Heuristic classifier — fallback when Claude classifier hasn't
-- run yet or is unavailable.
CREATE OR REPLACE FUNCTION classify_activity_heuristic(p_activity_id uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_type text;
  v_dur  integer;
  v_class text;
BEGIN
  SELECT activity_type, minutes_duration INTO v_type, v_dur
    FROM agent_activity_log WHERE id = p_activity_id;

  v_class := CASE
    WHEN v_type IN ('lead_qualified','deal_closed','meeting_held')                       THEN 'productive'
    WHEN v_type = 'outreach_sent'    AND COALESCE(v_dur, 5)  < 10                         THEN 'productive'
    WHEN v_type = 'call_made'        AND COALESCE(v_dur, 10) BETWEEN 2 AND 45             THEN 'productive'
    WHEN v_type = 'follow_up_sent'                                                        THEN 'productive'
    WHEN v_type = 'manual_note'                                                           THEN 'neutral'
    WHEN v_type = 'dashboard_session' AND COALESCE(v_dur, 5)  < 30                        THEN 'neutral'
    WHEN v_type = 'dashboard_session' AND COALESCE(v_dur, 0)  >= 60                       THEN 'unproductive'
    WHEN v_type = 'idle'             AND COALESCE(v_dur, 0)  > 15                         THEN 'unproductive'
    ELSE 'unknown'
  END;

  UPDATE agent_activity_log SET classification = v_class WHERE id = p_activity_id;
  RETURN v_class;
END;
$$;

REVOKE ALL ON FUNCTION classify_activity_heuristic(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION classify_activity_heuristic(uuid) TO service_role;

-- 6.3 Roll up a day's activity into agent_daily_summary, including
-- trend vs prior 7 days and coaching flags.
CREATE OR REPLACE FUNCTION calculate_daily_summary(
  p_agent_id uuid,
  p_date     date DEFAULT CURRENT_DATE
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_client_id    uuid;
  v_prod_min     integer;
  v_neut_min     integer;
  v_unprod_min   integer;
  v_total_min    integer;
  v_score        numeric(5,2);
  v_calls        integer;
  v_emails       integer;
  v_meetings     integer;
  v_followups    integer;
  v_qualified    integer;
  v_closed       integer;
  v_prev_avg     numeric(5,2);
  v_trend        text;
  v_flags        jsonb := '[]'::jsonb;
  v_red_streak   integer;
  v_id           uuid;
BEGIN
  SELECT client_id INTO v_client_id FROM team_members WHERE id = p_agent_id LIMIT 1;

  SELECT
    COALESCE(SUM(CASE WHEN classification = 'productive'   THEN minutes_duration ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN classification = 'neutral'      THEN minutes_duration ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN classification = 'unproductive' THEN minutes_duration ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN activity_type = 'call_made'       THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN activity_type = 'outreach_sent'   THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN activity_type = 'meeting_held'    THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN activity_type = 'follow_up_sent'  THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN activity_type = 'lead_qualified'  THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN activity_type = 'deal_closed'     THEN 1 ELSE 0 END), 0)
  INTO v_prod_min, v_neut_min, v_unprod_min,
       v_calls, v_emails, v_meetings, v_followups, v_qualified, v_closed
  FROM agent_activity_log
  WHERE agent_id = p_agent_id
    AND started_at::date = p_date;

  v_total_min := v_prod_min + v_neut_min + v_unprod_min;

  IF v_total_min > 0 THEN
    v_score := ROUND(((v_prod_min * 100.0) + (v_neut_min * 50.0) + (v_unprod_min * 0.0)) / v_total_min, 2);
  ELSE
    v_score := NULL;
  END IF;

  -- Trend vs prior 7 days
  SELECT AVG(productivity_score)
    INTO v_prev_avg
    FROM agent_daily_summary
   WHERE agent_id = p_agent_id
     AND summary_date BETWEEN p_date - interval '7 days' AND p_date - interval '1 day'
     AND productivity_score IS NOT NULL;

  v_trend := CASE
    WHEN v_score IS NULL OR v_prev_avg IS NULL THEN 'insufficient_data'
    WHEN v_score > v_prev_avg + 5              THEN 'improving'
    WHEN v_score < v_prev_avg - 5              THEN 'declining'
    ELSE 'stable'
  END;

  -- Flag: 3+ red days in a row (including today)
  SELECT COUNT(*)
    INTO v_red_streak
    FROM agent_daily_summary
   WHERE agent_id = p_agent_id
     AND summary_date BETWEEN p_date - interval '6 days' AND p_date - interval '1 day'
     AND productivity_score < 50;

  IF v_score IS NOT NULL AND v_score < 50 AND v_red_streak >= 2 THEN
    v_flags := v_flags || jsonb_build_array(jsonb_build_object(
      'code', 'RED_STREAK_3PLUS',
      'severity', 'info',
      'message', 'Three or more consecutive red days — consider a coaching conversation.'
    ));
  END IF;

  IF v_total_min < 60 AND v_score IS NOT NULL THEN
    v_flags := v_flags || jsonb_build_array(jsonb_build_object(
      'code', 'LOW_TRACKED_TIME',
      'severity', 'info',
      'message', 'Under 60 min of tracked activity today — score may not be representative.'
    ));
  END IF;

  INSERT INTO agent_daily_summary (
    agent_id, client_id, summary_date,
    total_minutes_tracked, productive_minutes, neutral_minutes, unproductive_minutes,
    productivity_score,
    calls_made, emails_sent, meetings_held, follow_ups_sent, leads_qualified, deals_closed,
    trend, coaching_flags, generated_at
  )
  VALUES (
    p_agent_id, v_client_id, p_date,
    v_total_min, v_prod_min, v_neut_min, v_unprod_min,
    v_score,
    v_calls, v_emails, v_meetings, v_followups, v_qualified, v_closed,
    v_trend, v_flags, now()
  )
  ON CONFLICT (agent_id, summary_date) DO UPDATE SET
    total_minutes_tracked = EXCLUDED.total_minutes_tracked,
    productive_minutes    = EXCLUDED.productive_minutes,
    neutral_minutes       = EXCLUDED.neutral_minutes,
    unproductive_minutes  = EXCLUDED.unproductive_minutes,
    productivity_score    = EXCLUDED.productivity_score,
    calls_made            = EXCLUDED.calls_made,
    emails_sent           = EXCLUDED.emails_sent,
    meetings_held         = EXCLUDED.meetings_held,
    follow_ups_sent       = EXCLUDED.follow_ups_sent,
    leads_qualified       = EXCLUDED.leads_qualified,
    deals_closed          = EXCLUDED.deals_closed,
    trend                 = EXCLUDED.trend,
    coaching_flags        = EXCLUDED.coaching_flags,
    generated_at          = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION calculate_daily_summary(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION calculate_daily_summary(uuid, date) TO service_role;

-- 6.4 Per-client productivity tier flip.
CREATE OR REPLACE FUNCTION enable_productivity_tier(
  p_client_id uuid,
  p_price     numeric DEFAULT 1000
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE clients
     SET productivity_tier_enabled    = true,
         productivity_tier_price      = p_price,
         productivity_tier_enabled_at = now()
   WHERE id = p_client_id;
END;
$$;

REVOKE ALL ON FUNCTION enable_productivity_tier(uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION enable_productivity_tier(uuid, numeric) TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 7. monitoring_thresholds seeds (existing schema uses
--    error_code/window_minutes/count_threshold/severity).
-- ─────────────────────────────────────────────────────────────────

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('PRODUCTIVITY_TRACKING_FAILED',    60,    3, 'warning'),
  ('PRODUCTIVITY_CLASSIFIER_FAILED',  60,    5, 'warning'),
  ('AGENT_PRODUCTIVITY_RED_STREAK',   10080, 3, 'info')
ON CONFLICT (error_code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- 8. Verification queries (run after apply)
-- ─────────────────────────────────────────────────────────────────
-- SELECT count(*) FROM agent_activity_log;      -- 0 until workflows run
-- SELECT count(*) FROM agent_daily_summary;     -- 0 until generator runs
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='team_members'
--     AND column_name IN ('productivity_tracking_consent','share_with_manager');
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='clients' AND column_name='productivity_tier_enabled';
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'record_agent_activity','classify_activity_heuristic',
--   'calculate_daily_summary','enable_productivity_tier'
-- );

-- ─────────────────────────────────────────────────────────────────
-- 9. ROLLBACK
-- ─────────────────────────────────────────────────────────────────
-- DELETE FROM monitoring_thresholds WHERE error_code IN (
--   'PRODUCTIVITY_TRACKING_FAILED','PRODUCTIVITY_CLASSIFIER_FAILED',
--   'AGENT_PRODUCTIVITY_RED_STREAK'
-- );
-- DROP FUNCTION IF EXISTS enable_productivity_tier(uuid, numeric);
-- DROP FUNCTION IF EXISTS calculate_daily_summary(uuid, date);
-- DROP FUNCTION IF EXISTS classify_activity_heuristic(uuid);
-- DROP FUNCTION IF EXISTS record_agent_activity(uuid, uuid, text, jsonb, integer, timestamptz, timestamptz);
-- DROP TABLE IF EXISTS agent_daily_summary;
-- DROP TABLE IF EXISTS agent_activity_log;
-- ALTER TABLE team_members
--   DROP COLUMN IF EXISTS productivity_tracking_consent,
--   DROP COLUMN IF EXISTS productivity_tracking_consent_at,
--   DROP COLUMN IF EXISTS productivity_tracking_consent_version,
--   DROP COLUMN IF EXISTS share_with_manager;
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS productivity_tier_enabled,
--   DROP COLUMN IF EXISTS productivity_tier_price,
--   DROP COLUMN IF EXISTS productivity_tier_enabled_at;
