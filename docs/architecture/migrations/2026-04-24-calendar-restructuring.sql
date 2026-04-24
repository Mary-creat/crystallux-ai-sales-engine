-- ══════════════════════════════════════════════════════════════════
-- Calendar Restructuring + No-Show Recovery (B.12a-2)
-- ══════════════════════════════════════════════════════════════════
-- Adds structured no-show detection, reshuffle tracking, and SMS
-- recovery plumbing on top of `appointment_log`. Creates the table
-- defensively (IF NOT EXISTS) because no prior migration in this
-- repo ships its CREATE — Mary created it manually in Supabase
-- during the v1 setup, so the column baseline here matches what the
-- dashboard + existing workflows already expect.
--
-- Additive only. Every ALTER is idempotent. Every CREATE is guarded.
-- Rollback block at the bottom (commented by default).
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. appointment_log baseline + new columns
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS appointment_log (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                uuid REFERENCES clients(id) ON DELETE CASCADE,
  lead_id                  uuid REFERENCES leads(id)   ON DELETE SET NULL,
  appointment_type         text,                               -- 'discovery' | 'closing' | 'onboarding' | 'follow_up'
  scheduled_start          timestamptz,
  scheduled_end            timestamptz,
  duration_minutes         integer,
  meeting_url              text,
  source_channel           text,                               -- 'calendly' | 'video' | 'manual' | 'voice'
  outcome                  text,                               -- 'completed' | 'no_show' | 'cancelled' | 'rebooked' | NULL while pending
  outcome_at               timestamptz,
  notes                    text,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

-- B.12a-2 additions — idempotent
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS no_show_flag              boolean       DEFAULT false;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS no_show_detected_at       timestamptz;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS recovery_sms_sent_at      timestamptz;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS recovery_sms_provider_ref text;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS rebook_link               text;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS rebooked_at               timestamptz;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS rebooked_appointment_id   uuid;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS originally_scheduled_for  timestamptz;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS reshuffle_count           integer DEFAULT 0;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS reshuffle_score           numeric(5,2);
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS reshuffle_reason          text;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS agent_id                  uuid;          -- reserved for Phase 10 agent auth

-- Guard rails
DO $$ BEGIN
  ALTER TABLE appointment_log
    ADD CONSTRAINT appointment_log_outcome_check
    CHECK (outcome IS NULL OR outcome IN ('completed','no_show','cancelled','rebooked','reshuffled'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE appointment_log
    ADD CONSTRAINT appointment_log_source_channel_check
    CHECK (source_channel IS NULL OR source_channel IN ('calendly','video','manual','voice','dashboard'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_appointment_log_client_start       ON appointment_log(client_id, scheduled_start);
CREATE INDEX IF NOT EXISTS idx_appointment_log_pending_no_show    ON appointment_log(scheduled_start) WHERE outcome IS NULL;
CREATE INDEX IF NOT EXISTS idx_appointment_log_no_show_flag       ON appointment_log(no_show_flag) WHERE no_show_flag = true;
CREATE INDEX IF NOT EXISTS idx_appointment_log_lead_id            ON appointment_log(lead_id);

-- ─────────────────────────────────────────────────────────────────
-- 2. calendar_reshuffle_log
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS calendar_reshuffle_log (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                uuid REFERENCES clients(id) ON DELETE CASCADE,
  vacated_appointment_id   uuid REFERENCES appointment_log(id) ON DELETE SET NULL,
  vacated_at               timestamptz NOT NULL DEFAULT now(),
  vacated_reason           text,                        -- 'cancellation' | 'no_show' | 'reschedule'
  slot_start               timestamptz,
  slot_end                 timestamptz,
  suggested_lead_ids       jsonb DEFAULT '[]'::jsonb,   -- [{lead_id, score, reason, rank}]
  suggester_source         text,                        -- 'rpc' | 'claude' | 'manual'
  selected_lead_id         uuid REFERENCES leads(id) ON DELETE SET NULL,
  selected_by              text,
  selected_at              timestamptz,
  new_appointment_id       uuid REFERENCES appointment_log(id) ON DELETE SET NULL,
  outcome                  text,                        -- 'filled' | 'unfilled' | 'expired'
  outcome_at               timestamptz,
  created_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE calendar_reshuffle_log
    ADD CONSTRAINT calendar_reshuffle_log_reason_check
    CHECK (vacated_reason IS NULL OR vacated_reason IN ('cancellation','no_show','reschedule','manual'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE calendar_reshuffle_log
    ADD CONSTRAINT calendar_reshuffle_log_outcome_check
    CHECK (outcome IS NULL OR outcome IN ('filled','unfilled','expired'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_reshuffle_log_client_vacated ON calendar_reshuffle_log(client_id, vacated_at DESC);
CREATE INDEX IF NOT EXISTS idx_reshuffle_log_outcome        ON calendar_reshuffle_log(outcome) WHERE outcome IS NULL;

-- ─────────────────────────────────────────────────────────────────
-- 3. Agent preferences for calendar (reserved; Component 3 expands)
-- ─────────────────────────────────────────────────────────────────
-- Stores per-agent working hours / buffer defaults so the reshuffle
-- suggester knows which slots are actually fillable. Kept lean here;
-- Component 3 (Morning Priority Task Ordering) adds columns.

CREATE TABLE IF NOT EXISTS agent_calendar_prefs (
  agent_id                 uuid PRIMARY KEY,
  client_id                uuid REFERENCES clients(id) ON DELETE CASCADE,
  timezone                 text DEFAULT 'America/Toronto',
  work_start_local         time DEFAULT '09:00',
  work_end_local           time DEFAULT '17:00',
  buffer_minutes           integer DEFAULT 15,
  max_per_day              integer DEFAULT 8,
  no_show_sms_enabled      boolean DEFAULT true,
  no_show_sms_template     text,                 -- null → use default in workflow
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_calendar_prefs_client ON agent_calendar_prefs(client_id);

-- ─────────────────────────────────────────────────────────────────
-- 4. RLS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE appointment_log         ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_reshuffle_log  ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_calendar_prefs    ENABLE ROW LEVEL SECURITY;

-- service_role full access (n8n backend)
DO $$ BEGIN
  CREATE POLICY appointment_log_service_role_all ON appointment_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY calendar_reshuffle_log_service_role_all ON calendar_reshuffle_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY agent_calendar_prefs_service_role_all ON agent_calendar_prefs
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 5. RPCs
-- ─────────────────────────────────────────────────────────────────

-- 5.1 Mark a pending appointment as a no-show.
CREATE OR REPLACE FUNCTION mark_appointment_no_show(p_appointment_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE appointment_log
     SET no_show_flag        = true,
         outcome             = 'no_show',
         outcome_at          = now(),
         no_show_detected_at = COALESCE(no_show_detected_at, now()),
         updated_at          = now()
   WHERE id = p_appointment_id
     AND outcome IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION mark_appointment_no_show(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_appointment_no_show(uuid) TO service_role;

-- 5.2 Return a client's appointments for a given day, joined with
-- lead name and current lead_status. Used by the "Your Day" panel.
CREATE OR REPLACE FUNCTION get_daily_appointments(
  p_client_id uuid,
  p_date      date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  appointment_id   uuid,
  scheduled_start  timestamptz,
  scheduled_end    timestamptz,
  appointment_type text,
  outcome          text,
  no_show_flag     boolean,
  meeting_url      text,
  lead_id          uuid,
  lead_name        text,
  lead_company     text,
  lead_status      text,
  lead_score       integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT  a.id, a.scheduled_start, a.scheduled_end, a.appointment_type,
            a.outcome, a.no_show_flag, a.meeting_url,
            l.id, (COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,''))::text,
            l.company, l.lead_status, l.lead_score
      FROM  appointment_log a
      LEFT JOIN leads l ON l.id = a.lead_id
     WHERE  a.client_id = p_client_id
       AND  a.scheduled_start::date = p_date
     ORDER BY a.scheduled_start ASC;
END;
$$;

REVOKE ALL ON FUNCTION get_daily_appointments(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_daily_appointments(uuid, date) TO service_role;

-- 5.3 Rank leads that could fill a freshly-vacated slot.
-- Baseline ranking: lead_score DESC, prefer same-day lead_status in
-- ('Booking Sent','Reply Received'), exclude do_not_contact.
CREATE OR REPLACE FUNCTION get_reshuffle_candidates(
  p_client_id  uuid,
  p_slot_start timestamptz,
  p_slot_end   timestamptz,
  p_limit      integer DEFAULT 5
)
RETURNS TABLE(
  lead_id    uuid,
  score      numeric,
  reason     text,
  lead_name  text,
  lead_email text,
  lead_phone text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT  l.id,
            COALESCE(l.lead_score, 0)::numeric
              + CASE WHEN l.lead_status IN ('Booking Sent','Reply Received','Interested') THEN 10 ELSE 0 END
              + CASE WHEN l.last_engagement_at > now() - interval '7 days' THEN 5 ELSE 0 END,
            ('status=' || COALESCE(l.lead_status,'?') ||
             ', score=' || COALESCE(l.lead_score::text,'0') ||
             CASE WHEN l.last_engagement_at IS NOT NULL
                  THEN ', last_eng=' || to_char(l.last_engagement_at,'YYYY-MM-DD')
                  ELSE '' END)::text,
            (COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,''))::text,
            l.email,
            l.phone
      FROM  leads l
     WHERE  l.client_id = p_client_id
       AND  COALESCE(l.do_not_contact, false) = false
       AND  NOT EXISTS (
              SELECT 1 FROM appointment_log a
               WHERE a.lead_id = l.id
                 AND a.outcome IS NULL
                 AND a.scheduled_start < p_slot_end
                 AND a.scheduled_end   > p_slot_start
            )
     ORDER BY 2 DESC, l.updated_at DESC
     LIMIT  p_limit;
END;
$$;

REVOKE ALL ON FUNCTION get_reshuffle_candidates(uuid, timestamptz, timestamptz, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_reshuffle_candidates(uuid, timestamptz, timestamptz, integer) TO service_role;

-- 5.4 Record that a reshuffle happened (vacated → filled).
CREATE OR REPLACE FUNCTION record_reshuffle(
  p_client_id              uuid,
  p_vacated_appointment_id uuid,
  p_vacated_reason         text,
  p_slot_start             timestamptz,
  p_slot_end               timestamptz,
  p_suggested              jsonb,
  p_suggester_source       text DEFAULT 'rpc'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO calendar_reshuffle_log (
    client_id, vacated_appointment_id, vacated_reason,
    slot_start, slot_end, suggested_lead_ids, suggester_source
  )
  VALUES (
    p_client_id, p_vacated_appointment_id, p_vacated_reason,
    p_slot_start, p_slot_end, COALESCE(p_suggested, '[]'::jsonb), p_suggester_source
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION record_reshuffle(uuid, uuid, text, timestamptz, timestamptz, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION record_reshuffle(uuid, uuid, text, timestamptz, timestamptz, jsonb, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 6. Monitoring seeds (scan_errors codes)
-- ─────────────────────────────────────────────────────────────────
-- These codes are used by the workflows; seeding keeps the error
-- monitor's known-codes allowlist in sync.

INSERT INTO scan_errors (error_code, severity, category, description, suggested_action, created_at)
SELECT 'NO_SHOW_DETECTED', 'info', 'calendar',
       'Appointment marked no-show by clx-no-show-detector-v1.',
       'Review appointment_log row; SMS recovery fires automatically.', now()
WHERE NOT EXISTS (SELECT 1 FROM scan_errors WHERE error_code = 'NO_SHOW_DETECTED');

INSERT INTO scan_errors (error_code, severity, category, description, suggested_action, created_at)
SELECT 'NO_SHOW_SMS_FAILED', 'warning', 'calendar',
       'Twilio SMS send failed for a no-show recovery.',
       'Check Twilio credentials + lead.phone format.', now()
WHERE NOT EXISTS (SELECT 1 FROM scan_errors WHERE error_code = 'NO_SHOW_SMS_FAILED');

INSERT INTO scan_errors (error_code, severity, category, description, suggested_action, created_at)
SELECT 'RESHUFFLE_NO_CANDIDATES', 'warning', 'calendar',
       'Vacated slot had no eligible reshuffle candidates.',
       'Slot will expire unfilled; review client lead funnel.', now()
WHERE NOT EXISTS (SELECT 1 FROM scan_errors WHERE error_code = 'RESHUFFLE_NO_CANDIDATES');

-- ─────────────────────────────────────────────────────────────────
-- 7. Verification queries (run manually after apply)
-- ─────────────────────────────────────────────────────────────────
-- SELECT count(*) FROM appointment_log;                            -- existing rows preserved
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='appointment_log' AND column_name LIKE 'no_show%';
-- SELECT count(*) FROM calendar_reshuffle_log;                     -- 0 expected until workflows run
-- SELECT proname FROM pg_proc
--   WHERE proname IN ('mark_appointment_no_show','get_daily_appointments',
--                     'get_reshuffle_candidates','record_reshuffle');

-- ─────────────────────────────────────────────────────────────────
-- 8. ROLLBACK (uncomment + run if you need to revert)
-- ─────────────────────────────────────────────────────────────────
-- DROP FUNCTION IF EXISTS record_reshuffle(uuid, uuid, text, timestamptz, timestamptz, jsonb, text);
-- DROP FUNCTION IF EXISTS get_reshuffle_candidates(uuid, timestamptz, timestamptz, integer);
-- DROP FUNCTION IF EXISTS get_daily_appointments(uuid, date);
-- DROP FUNCTION IF EXISTS mark_appointment_no_show(uuid);
-- DROP TABLE IF EXISTS calendar_reshuffle_log;
-- DROP TABLE IF EXISTS agent_calendar_prefs;
-- ALTER TABLE appointment_log
--   DROP COLUMN IF EXISTS no_show_flag,
--   DROP COLUMN IF EXISTS no_show_detected_at,
--   DROP COLUMN IF EXISTS recovery_sms_sent_at,
--   DROP COLUMN IF EXISTS recovery_sms_provider_ref,
--   DROP COLUMN IF EXISTS rebook_link,
--   DROP COLUMN IF EXISTS rebooked_at,
--   DROP COLUMN IF EXISTS rebooked_appointment_id,
--   DROP COLUMN IF EXISTS originally_scheduled_for,
--   DROP COLUMN IF EXISTS reshuffle_count,
--   DROP COLUMN IF EXISTS reshuffle_score,
--   DROP COLUMN IF EXISTS reshuffle_reason,
--   DROP COLUMN IF EXISTS agent_id;
-- -- NOTE: DO NOT drop appointment_log itself — it was created
-- -- manually pre-repo and may have rows we want to preserve.
-- -- The CREATE TABLE IF NOT EXISTS above was a no-op for you.
