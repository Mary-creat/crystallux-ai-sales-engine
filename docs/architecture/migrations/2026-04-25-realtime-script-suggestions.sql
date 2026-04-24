-- ══════════════════════════════════════════════════════════════════
-- Real-Time Closing Script Suggestions (B.12c-2 / Component 7)
-- ══════════════════════════════════════════════════════════════════
-- The real-time classifier (B.12c-1) raises a trigger state on
-- certain intents (objection / closing_signal / stall / confusion).
-- This migration stores the script that was shown, the agent's
-- response to it, and builds the learning loop that feeds
-- conversion_rate updates back onto closing_scripts.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. script_suggestion_log — one row per suggestion shown
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS script_suggestion_log (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id                    uuid,
  chunk_id                   uuid REFERENCES call_transcript_chunks(id) ON DELETE SET NULL,
  agent_id                   uuid,
  client_id                  uuid REFERENCES clients(id) ON DELETE CASCADE,
  suggested_at               timestamptz DEFAULT now(),
  trigger_state              text,                                   -- 'objection' | 'closing_signal' | 'stall' | 'confusion'
  trigger_sentiment          text,
  script_id                  uuid,                                   -- closing_scripts / objection_handlers / discovery_frameworks id
  script_type                text,                                   -- 'closing' | 'objection' | 'discovery' | 'followup'
  script_content_shown       text,
  rank_shown                 integer DEFAULT 1,
  agent_action               text,                                   -- 'accepted' | 'rejected' | 'modified' | 'ignored' | 'no_response'
  action_at                  timestamptz,
  time_to_response_ms        integer,
  call_outcome_after         text,
  feedback_notes             text
);

DO $$ BEGIN
  ALTER TABLE script_suggestion_log
    ADD CONSTRAINT script_suggestion_log_action_check
    CHECK (agent_action IS NULL OR agent_action IN ('accepted','rejected','modified','ignored','no_response'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE script_suggestion_log
    ADD CONSTRAINT script_suggestion_log_trigger_check
    CHECK (trigger_state IS NULL OR trigger_state IN ('objection','closing_signal','stall','confusion'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_suggestion_agent
  ON script_suggestion_log(agent_id, suggested_at DESC);
CREATE INDEX IF NOT EXISTS idx_suggestion_call
  ON script_suggestion_log(call_id, suggested_at ASC);
CREATE INDEX IF NOT EXISTS idx_suggestion_script
  ON script_suggestion_log(script_id, agent_action);
CREATE INDEX IF NOT EXISTS idx_suggestion_unfed
  ON script_suggestion_log(suggested_at DESC)
  WHERE agent_action IS NULL;

-- ─────────────────────────────────────────────────────────────────
-- 2. clients tier flag
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS realtime_script_suggestions_enabled    boolean       DEFAULT false;
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS realtime_script_suggestions_enabled_at timestamptz;

-- ─────────────────────────────────────────────────────────────────
-- 3. RLS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE script_suggestion_log ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY script_suggestion_log_service_role_all ON script_suggestion_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 4. RPCs
-- ─────────────────────────────────────────────────────────────────

-- 4.1 Match a trigger state + lead context to a ranked list of
-- candidate scripts from the existing libraries. Returns up to 3
-- per call. Pulls from closing_scripts (for 'closing_signal'),
-- objection_handlers (for 'objection'), discovery_frameworks (for
-- 'stall' or 'confusion'). Ranked by times_used DESC then
-- conversion_rate DESC then last_used_at DESC.
CREATE OR REPLACE FUNCTION match_script_to_state(
  p_trigger_state text,
  p_vertical      text,
  p_lead_context  jsonb DEFAULT '{}'::jsonb,
  p_limit         integer DEFAULT 3
)
RETURNS TABLE(
  script_id        uuid,
  script_type      text,
  script_title     text,
  script_body      text,
  conversion_rate  numeric,
  rank             integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_trigger_state = 'closing_signal' THEN
    RETURN QUERY
      SELECT  c.id, 'closing'::text,
              (c.close_type || ' — ' || COALESCE(c.trigger_condition,''))::text,
              c.script_text,
              c.conversion_rate,
              row_number() OVER (ORDER BY COALESCE(c.times_used,0) DESC,
                                          COALESCE(c.conversion_rate,0) DESC,
                                          c.last_used_at DESC NULLS LAST)::integer
        FROM closing_scripts c
       WHERE (p_vertical IS NULL OR c.niche_name = p_vertical OR c.vertical = p_vertical)
       LIMIT p_limit;

  ELSIF p_trigger_state = 'objection' THEN
    RETURN QUERY
      SELECT  o.id, 'objection'::text,
              (o.objection_category || ' — ' || COALESCE(o.objection_text,''))::text,
              o.response_script,
              o.conversion_rate,
              row_number() OVER (ORDER BY COALESCE(o.times_used,0) DESC,
                                          COALESCE(o.conversion_rate,0) DESC)::integer
        FROM objection_handlers o
       WHERE (p_vertical IS NULL OR o.niche_name = p_vertical OR o.vertical = p_vertical)
       LIMIT p_limit;

  ELSIF p_trigger_state IN ('stall','confusion') THEN
    RETURN QUERY
      SELECT  d.id, 'discovery'::text,
              d.name::text,
              (CASE WHEN d.question_sequence IS NOT NULL
                    THEN array_to_string(
                      ARRAY(SELECT jsonb_array_elements_text(d.question_sequence)), E'\n')
                    ELSE NULL END)::text,
              NULL::numeric,
              row_number() OVER (ORDER BY COALESCE(d.times_used,0) DESC,
                                          COALESCE(d.conversion_lift,0) DESC)::integer
        FROM discovery_frameworks d
       WHERE (p_vertical IS NULL OR d.niche_name = p_vertical OR d.vertical = p_vertical)
       LIMIT p_limit;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION match_script_to_state(text, text, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION match_script_to_state(text, text, jsonb, integer) TO service_role;

-- 4.2 Log a suggestion (insert-only). Returns the new id.
CREATE OR REPLACE FUNCTION log_suggestion_shown(
  p_call_id       uuid,
  p_chunk_id      uuid,
  p_agent_id      uuid,
  p_client_id     uuid,
  p_trigger_state text,
  p_trigger_sent  text,
  p_script_id     uuid,
  p_script_type   text,
  p_content       text,
  p_rank          integer
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO script_suggestion_log (
    call_id, chunk_id, agent_id, client_id,
    trigger_state, trigger_sentiment,
    script_id, script_type, script_content_shown, rank_shown
  )
  VALUES (
    p_call_id, p_chunk_id, p_agent_id, p_client_id,
    p_trigger_state, p_trigger_sent,
    p_script_id, p_script_type, p_content, COALESCE(p_rank, 1)
  )
  RETURNING id INTO v_id;

  -- Also bump call_event_log.script_suggestions_shown (UPSERT stub
  -- to keep counter fresh even if event row not finalised yet).
  INSERT INTO call_event_log (call_id, script_suggestions_shown)
  VALUES (p_call_id, 1)
  ON CONFLICT (call_id) DO UPDATE SET
    script_suggestions_shown = COALESCE(call_event_log.script_suggestions_shown, 0) + 1;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION log_suggestion_shown(uuid, uuid, uuid, uuid, text, text, uuid, text, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION log_suggestion_shown(uuid, uuid, uuid, uuid, text, text, uuid, text, text, integer) TO service_role;

-- 4.3 Record the agent's feedback on a suggestion.
CREATE OR REPLACE FUNCTION log_suggestion_feedback(
  p_suggestion_id uuid,
  p_action        text,
  p_notes         text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_suggested_at timestamptz;
  v_call_id      uuid;
BEGIN
  SELECT suggested_at, call_id INTO v_suggested_at, v_call_id
    FROM script_suggestion_log WHERE id = p_suggestion_id;

  UPDATE script_suggestion_log
     SET agent_action         = p_action,
         action_at            = now(),
         time_to_response_ms  = CASE WHEN v_suggested_at IS NOT NULL
                                     THEN EXTRACT(EPOCH FROM (now() - v_suggested_at))::integer * 1000
                                     ELSE NULL END,
         feedback_notes       = p_notes
   WHERE id = p_suggestion_id;

  IF p_action = 'accepted' AND v_call_id IS NOT NULL THEN
    INSERT INTO call_event_log (call_id, script_suggestions_accepted)
    VALUES (v_call_id, 1)
    ON CONFLICT (call_id) DO UPDATE SET
      script_suggestions_accepted = COALESCE(call_event_log.script_suggestions_accepted, 0) + 1;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION log_suggestion_feedback(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION log_suggestion_feedback(uuid, text, text) TO service_role;

-- 4.4 Learning loop — recompute each script's conversion_rate from
-- suggestion_log outcomes over the last 90 days. Runs daily.
CREATE OR REPLACE FUNCTION refresh_script_conversion_rates(p_period_days integer DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_updated integer := 0;
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT script_id, script_type,
           COUNT(*)                                                   AS total,
           COUNT(*) FILTER (WHERE agent_action IN ('accepted','modified')) AS used,
           COUNT(*) FILTER (WHERE agent_action = 'accepted')          AS accepted
      FROM script_suggestion_log
     WHERE script_id IS NOT NULL
       AND suggested_at > now() - (p_period_days * interval '1 day')
       AND agent_action IS NOT NULL
     GROUP BY script_id, script_type
    HAVING COUNT(*) >= 3
  LOOP
    IF rec.script_type = 'closing' THEN
      UPDATE closing_scripts
         SET conversion_rate = ROUND((rec.accepted::numeric / NULLIF(rec.total, 0)) * 100, 2)
       WHERE id = rec.script_id;
    ELSIF rec.script_type = 'objection' THEN
      UPDATE objection_handlers
         SET conversion_rate = ROUND((rec.accepted::numeric / NULLIF(rec.total, 0)) * 100, 2)
       WHERE id = rec.script_id;
    END IF;
    v_updated := v_updated + 1;
  END LOOP;
  RETURN v_updated;
END;
$$;

REVOKE ALL ON FUNCTION refresh_script_conversion_rates(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION refresh_script_conversion_rates(integer) TO service_role;

-- 4.5 Per-client tier flip.
CREATE OR REPLACE FUNCTION enable_realtime_script_suggestions(p_client_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE clients
     SET realtime_script_suggestions_enabled    = true,
         realtime_script_suggestions_enabled_at = now()
   WHERE id = p_client_id;
END;
$$;

REVOKE ALL ON FUNCTION enable_realtime_script_suggestions(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION enable_realtime_script_suggestions(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 5. monitoring_thresholds seeds
-- ─────────────────────────────────────────────────────────────────

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('SCRIPT_SUGGEST_FAILED',  60,   5, 'warning'),
  ('SCRIPT_MATCH_NO_RESULT', 60,   5, 'info'),
  ('SCRIPT_LEARNING_FAILED', 1440, 1, 'warning')
ON CONFLICT (error_code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- 6. Verification
-- ─────────────────────────────────────────────────────────────────
-- SELECT count(*) FROM script_suggestion_log;
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='clients' AND column_name='realtime_script_suggestions_enabled';
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'match_script_to_state','log_suggestion_shown','log_suggestion_feedback',
--   'refresh_script_conversion_rates','enable_realtime_script_suggestions'
-- );

-- ─────────────────────────────────────────────────────────────────
-- 7. ROLLBACK
-- ─────────────────────────────────────────────────────────────────
-- DELETE FROM monitoring_thresholds WHERE error_code IN (
--   'SCRIPT_SUGGEST_FAILED','SCRIPT_MATCH_NO_RESULT','SCRIPT_LEARNING_FAILED'
-- );
-- DROP FUNCTION IF EXISTS enable_realtime_script_suggestions(uuid);
-- DROP FUNCTION IF EXISTS refresh_script_conversion_rates(integer);
-- DROP FUNCTION IF EXISTS log_suggestion_feedback(uuid, text, text);
-- DROP FUNCTION IF EXISTS log_suggestion_shown(uuid, uuid, uuid, uuid, text, text, uuid, text, text, integer);
-- DROP FUNCTION IF EXISTS match_script_to_state(text, text, jsonb, integer);
-- DROP TABLE IF EXISTS script_suggestion_log;
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS realtime_script_suggestions_enabled,
--   DROP COLUMN IF EXISTS realtime_script_suggestions_enabled_at;
