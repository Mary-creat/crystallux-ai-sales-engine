-- ══════════════════════════════════════════════════════════════════
-- Listening Intelligence (B.12c-1 / Component 6)
-- ══════════════════════════════════════════════════════════════════
-- Real-time call transcript capture + AI-classified sentiment,
-- intent, and topics; post-call coaching analysis; customer +
-- agent consent tracking. Canadian two-party consent model
-- (CRTC / PIPEDA) — both agent and customer must be informed
-- before any transcript is recorded.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. call_transcript_chunks — one row per Vapi-emitted transcript
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS call_transcript_chunks (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id                 uuid NOT NULL,
  agent_id                uuid,
  lead_id                 uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id               uuid REFERENCES clients(id) ON DELETE CASCADE,
  chunk_sequence          integer NOT NULL,
  speaker                 text DEFAULT 'unknown',
  transcript_text         text NOT NULL,
  transcript_confidence   numeric(5,2),
  detected_at             timestamptz DEFAULT now(),
  sentiment               text DEFAULT 'unknown',
  sentiment_score         numeric(5,2),
  detected_intent         text DEFAULT 'unknown',
  detected_topics         jsonb DEFAULT '[]'::jsonb,
  classified_at           timestamptz,
  classifier_model        text,
  classifier_latency_ms   integer
);

DO $$ BEGIN
  ALTER TABLE call_transcript_chunks
    ADD CONSTRAINT call_transcript_chunks_speaker_check
    CHECK (speaker IN ('agent','customer','unknown'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE call_transcript_chunks
    ADD CONSTRAINT call_transcript_chunks_sentiment_check
    CHECK (sentiment IN ('positive','neutral','negative','mixed','unknown'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE call_transcript_chunks
    ADD CONSTRAINT call_transcript_chunks_intent_check
    CHECK (detected_intent IN (
      'discovery_question','objection','closing_signal','stall',
      'confusion','buy_signal','dismissal','small_talk',
      'information_share','unknown'
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_transcript_call         ON call_transcript_chunks(call_id, chunk_sequence);
CREATE INDEX IF NOT EXISTS idx_transcript_agent_date   ON call_transcript_chunks(agent_id, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_transcript_intent       ON call_transcript_chunks(detected_intent, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_transcript_sentiment    ON call_transcript_chunks(sentiment, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_transcript_unclassified ON call_transcript_chunks(detected_at DESC) WHERE classified_at IS NULL;

-- ─────────────────────────────────────────────────────────────────
-- 2. call_event_log — rolled-up per-call record
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS call_event_log (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id                    uuid UNIQUE NOT NULL,
  agent_id                   uuid,
  lead_id                    uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id                  uuid REFERENCES clients(id) ON DELETE CASCADE,
  started_at                 timestamptz,
  ended_at                   timestamptz,
  duration_seconds           integer,
  overall_sentiment          text,
  sentiment_trajectory       jsonb DEFAULT '[]'::jsonb,
  key_objections             jsonb DEFAULT '[]'::jsonb,
  closing_signals_detected   integer DEFAULT 0,
  buy_signals_detected       integer DEFAULT 0,
  script_suggestions_shown   integer DEFAULT 0,
  script_suggestions_accepted integer DEFAULT 0,
  call_outcome               text,
  transcript_quality         text,
  claude_analysis            jsonb,
  analyzed_at                timestamptz,
  customer_consent_recorded  boolean DEFAULT false,
  consent_disclosure_read    boolean DEFAULT false
);

DO $$ BEGIN
  ALTER TABLE call_event_log
    ADD CONSTRAINT call_event_log_quality_check
    CHECK (transcript_quality IS NULL OR transcript_quality IN ('excellent','good','fair','poor','failed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_call_event_agent   ON call_event_log(agent_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_event_client  ON call_event_log(client_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_event_outcome ON call_event_log(call_outcome, started_at DESC);

-- ─────────────────────────────────────────────────────────────────
-- 3. clients + team_members consent columns
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE clients ADD COLUMN IF NOT EXISTS listening_intelligence_enabled     boolean       DEFAULT false;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS listening_intelligence_price       numeric(10,2);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS listening_intelligence_enabled_at  timestamptz;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS customer_consent_disclosure_script text
  DEFAULT 'This call is being recorded and analyzed for quality and coaching purposes. You may opt out at any time during this call.';

ALTER TABLE team_members ADD COLUMN IF NOT EXISTS call_recording_consent            boolean DEFAULT false;
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS call_recording_consent_at         timestamptz;
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS call_recording_consent_version    text;

-- ─────────────────────────────────────────────────────────────────
-- 4. RLS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE call_transcript_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE call_event_log         ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY call_transcript_chunks_service_role_all ON call_transcript_chunks
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY call_event_log_service_role_all ON call_event_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 5. RPCs
-- ─────────────────────────────────────────────────────────────────

-- 5.1 Consent-gated transcript chunk insert. Returns the new id or
-- NULL if the client doesn't have listening_intelligence_enabled OR
-- the agent hasn't consented to call recording.
CREATE OR REPLACE FUNCTION process_transcript_chunk(p_chunk_data jsonb)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_client_id   uuid := (p_chunk_data->>'client_id')::uuid;
  v_agent_id    uuid := (p_chunk_data->>'agent_id')::uuid;
  v_client_ok   boolean;
  v_agent_ok    boolean;
  v_id          uuid;
BEGIN
  SELECT COALESCE(listening_intelligence_enabled, false)
    INTO v_client_ok
    FROM clients WHERE id = v_client_id;
  IF NOT COALESCE(v_client_ok, false) THEN RETURN NULL; END IF;

  SELECT COALESCE(call_recording_consent, false)
    INTO v_agent_ok
    FROM team_members WHERE id = v_agent_id;
  IF NOT COALESCE(v_agent_ok, false) THEN RETURN NULL; END IF;

  INSERT INTO call_transcript_chunks (
    call_id, agent_id, lead_id, client_id,
    chunk_sequence, speaker, transcript_text, transcript_confidence,
    detected_at
  )
  VALUES (
    (p_chunk_data->>'call_id')::uuid,
    v_agent_id,
    NULLIF(p_chunk_data->>'lead_id','')::uuid,
    v_client_id,
    COALESCE((p_chunk_data->>'chunk_sequence')::integer, 0),
    COALESCE(p_chunk_data->>'speaker','unknown'),
    p_chunk_data->>'transcript_text',
    NULLIF(p_chunk_data->>'transcript_confidence','')::numeric,
    COALESCE((p_chunk_data->>'detected_at')::timestamptz, now())
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION process_transcript_chunk(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION process_transcript_chunk(jsonb) TO service_role;

-- 5.2 Return aggregated insights for a single call.
CREATE OR REPLACE FUNCTION get_call_insights(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v jsonb;
BEGIN
  SELECT jsonb_build_object(
    'call_id', p_call_id,
    'chunks', (SELECT count(*) FROM call_transcript_chunks WHERE call_id = p_call_id),
    'objection_count', (SELECT count(*) FROM call_transcript_chunks WHERE call_id = p_call_id AND detected_intent = 'objection'),
    'closing_signal_count', (SELECT count(*) FROM call_transcript_chunks WHERE call_id = p_call_id AND detected_intent = 'closing_signal'),
    'buy_signal_count', (SELECT count(*) FROM call_transcript_chunks WHERE call_id = p_call_id AND detected_intent = 'buy_signal'),
    'negative_sentiment_ratio',
      COALESCE(
        (SELECT count(*) FILTER (WHERE sentiment = 'negative')::numeric
                / NULLIF(count(*), 0)
           FROM call_transcript_chunks WHERE call_id = p_call_id),
        0),
    'topics', (SELECT jsonb_agg(DISTINCT topic)
                 FROM call_transcript_chunks c, jsonb_array_elements_text(c.detected_topics) topic
                WHERE c.call_id = p_call_id),
    'event', (SELECT to_jsonb(e) FROM call_event_log e WHERE e.call_id = p_call_id)
  ) INTO v;
  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION get_call_insights(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_call_insights(uuid) TO service_role;

-- 5.3 Per-agent patterns over a window.
CREATE OR REPLACE FUNCTION get_agent_call_patterns(
  p_agent_id     uuid,
  p_period_days  integer DEFAULT 30
)
RETURNS TABLE(
  total_calls           integer,
  avg_duration_sec      numeric,
  avg_objections        numeric,
  avg_closing_signals   numeric,
  avg_buy_signals       numeric,
  suggestion_accept_pct numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT  COUNT(*)::integer,
            ROUND(AVG(duration_seconds)::numeric, 1),
            ROUND(AVG(jsonb_array_length(COALESCE(key_objections,'[]'::jsonb)))::numeric, 2),
            ROUND(AVG(closing_signals_detected)::numeric, 2),
            ROUND(AVG(buy_signals_detected)::numeric, 2),
            CASE WHEN SUM(script_suggestions_shown) > 0
                 THEN ROUND(100.0 * SUM(script_suggestions_accepted)::numeric / SUM(script_suggestions_shown), 1)
                 ELSE NULL
            END
      FROM call_event_log
     WHERE agent_id = p_agent_id
       AND started_at > now() - (p_period_days * interval '1 day');
END;
$$;

REVOKE ALL ON FUNCTION get_agent_call_patterns(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_agent_call_patterns(uuid, integer) TO service_role;

-- 5.4 Per-client tier flip.
CREATE OR REPLACE FUNCTION enable_listening_intelligence(
  p_client_id uuid,
  p_price     numeric DEFAULT 2500
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE clients
     SET listening_intelligence_enabled    = true,
         listening_intelligence_price      = p_price,
         listening_intelligence_enabled_at = now()
   WHERE id = p_client_id;
END;
$$;

REVOKE ALL ON FUNCTION enable_listening_intelligence(uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION enable_listening_intelligence(uuid, numeric) TO service_role;

-- 5.5 UPSERT the per-call summary after Claude analysis. Called by
-- clx-post-call-analyzer-v1.
CREATE OR REPLACE FUNCTION finalize_call_analysis(
  p_call_id            uuid,
  p_overall_sentiment  text,
  p_trajectory         jsonb,
  p_key_objections     jsonb,
  p_closing_signals    integer,
  p_buy_signals        integer,
  p_outcome            text,
  p_quality            text,
  p_analysis           jsonb
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_agent_id  uuid;
  v_lead_id   uuid;
  v_client_id uuid;
  v_start     timestamptz;
  v_end       timestamptz;
  v_dur       integer;
  v_id        uuid;
BEGIN
  SELECT MIN(detected_at), MAX(detected_at), MAX(agent_id), MAX(lead_id), MAX(client_id)
    INTO v_start, v_end, v_agent_id, v_lead_id, v_client_id
    FROM call_transcript_chunks
   WHERE call_id = p_call_id;

  v_dur := CASE WHEN v_start IS NOT NULL AND v_end IS NOT NULL
                THEN EXTRACT(EPOCH FROM (v_end - v_start))::integer
                ELSE NULL END;

  INSERT INTO call_event_log (
    call_id, agent_id, lead_id, client_id,
    started_at, ended_at, duration_seconds,
    overall_sentiment, sentiment_trajectory, key_objections,
    closing_signals_detected, buy_signals_detected,
    call_outcome, transcript_quality,
    claude_analysis, analyzed_at
  )
  VALUES (
    p_call_id, v_agent_id, v_lead_id, v_client_id,
    v_start, v_end, v_dur,
    p_overall_sentiment, COALESCE(p_trajectory,'[]'::jsonb), COALESCE(p_key_objections,'[]'::jsonb),
    COALESCE(p_closing_signals, 0), COALESCE(p_buy_signals, 0),
    p_outcome, p_quality,
    p_analysis, now()
  )
  ON CONFLICT (call_id) DO UPDATE SET
    overall_sentiment        = EXCLUDED.overall_sentiment,
    sentiment_trajectory     = EXCLUDED.sentiment_trajectory,
    key_objections           = EXCLUDED.key_objections,
    closing_signals_detected = EXCLUDED.closing_signals_detected,
    buy_signals_detected     = EXCLUDED.buy_signals_detected,
    call_outcome             = EXCLUDED.call_outcome,
    transcript_quality       = EXCLUDED.transcript_quality,
    claude_analysis          = EXCLUDED.claude_analysis,
    analyzed_at              = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION finalize_call_analysis(uuid, text, jsonb, jsonb, integer, integer, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finalize_call_analysis(uuid, text, jsonb, jsonb, integer, integer, text, text, jsonb) TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 6. monitoring_thresholds seeds
-- ─────────────────────────────────────────────────────────────────

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('TRANSCRIPT_PROCESSING_FAILED', 60,   5, 'warning'),
  ('REALTIME_LATENCY_HIGH',        60,   3, 'warning'),
  ('CLAUDE_API_RATE_LIMITED',      60,   2, 'critical'),
  ('CONSENT_VIOLATION_DETECTED',   1440, 1, 'critical'),
  ('CALL_ANALYSIS_FAILED',         60,   3, 'warning')
ON CONFLICT (error_code) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────
-- 7. Verification
-- ─────────────────────────────────────────────────────────────────
-- SELECT count(*) FROM call_transcript_chunks;    -- 0 until Vapi streams
-- SELECT count(*) FROM call_event_log;            -- 0 until finalize runs
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='clients' AND column_name='listening_intelligence_enabled';
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='team_members' AND column_name='call_recording_consent';
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'process_transcript_chunk','get_call_insights','get_agent_call_patterns',
--   'enable_listening_intelligence','finalize_call_analysis'
-- );

-- ─────────────────────────────────────────────────────────────────
-- 8. ROLLBACK
-- ─────────────────────────────────────────────────────────────────
-- DELETE FROM monitoring_thresholds WHERE error_code IN (
--   'TRANSCRIPT_PROCESSING_FAILED','REALTIME_LATENCY_HIGH',
--   'CLAUDE_API_RATE_LIMITED','CONSENT_VIOLATION_DETECTED',
--   'CALL_ANALYSIS_FAILED'
-- );
-- DROP FUNCTION IF EXISTS finalize_call_analysis(uuid, text, jsonb, jsonb, integer, integer, text, text, jsonb);
-- DROP FUNCTION IF EXISTS enable_listening_intelligence(uuid, numeric);
-- DROP FUNCTION IF EXISTS get_agent_call_patterns(uuid, integer);
-- DROP FUNCTION IF EXISTS get_call_insights(uuid);
-- DROP FUNCTION IF EXISTS process_transcript_chunk(jsonb);
-- DROP TABLE IF EXISTS call_event_log;
-- DROP TABLE IF EXISTS call_transcript_chunks;
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS listening_intelligence_enabled,
--   DROP COLUMN IF EXISTS listening_intelligence_price,
--   DROP COLUMN IF EXISTS listening_intelligence_enabled_at,
--   DROP COLUMN IF EXISTS customer_consent_disclosure_script;
-- ALTER TABLE team_members
--   DROP COLUMN IF EXISTS call_recording_consent,
--   DROP COLUMN IF EXISTS call_recording_consent_at,
--   DROP COLUMN IF EXISTS call_recording_consent_version;
