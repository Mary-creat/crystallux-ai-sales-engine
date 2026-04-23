-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX MULTI-CHANNEL OUTREACH — SCHEMA SCAFFOLDING (Part B.6)
-- File: docs/architecture/migrations/2026-04-23-multi-channel.sql
--
-- Adds the schema surface the LinkedIn / WhatsApp / Voice outreach
-- workflows will write into. Schema-only — no live Unipile, Twilio, or
-- Vapi API calls are wired yet. Each corresponding workflow ships with
-- its Schedule Trigger DEACTIVATED and placeholder credential notes.
--
-- Idempotent — safe to re-run. All column adds use IF NOT EXISTS.
-- All tables use CREATE TABLE IF NOT EXISTS.
-- All RLS policies use DROP ... IF EXISTS / CREATE.
--
-- Runs AFTER 2026-04-23-apollo-schema.sql (does not modify it).
-- Rollback SQL at the bottom (commented).
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. CHANNEL ROUTING FIELDS ON leads
-- ─────────────────────────────────────────────────────────────────
-- preferred_channel      — what Campaign Router decides based on
--                          Apollo-enriched signals + score
-- channels_attempted     — jsonb array of channels already tried, used
--                          for fallback routing and 48h cooldowns
-- last_channel_attempted — latest channel used (string)
-- country                — ISO2; referenced by WhatsApp Canadian
--                          routing rule (lead.country = 'CA')

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS preferred_channel          text DEFAULT 'email',
  ADD COLUMN IF NOT EXISTS channels_attempted         jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS last_channel_attempted     text,
  ADD COLUMN IF NOT EXISTS last_channel_attempted_at  timestamptz,
  ADD COLUMN IF NOT EXISTS country                    text;

-- Enforce the channel enumeration. Use DO block + exception guard so
-- re-runs don't trip on duplicate constraint name.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'leads_preferred_channel_check'
  ) THEN
    ALTER TABLE leads
      ADD CONSTRAINT leads_preferred_channel_check
      CHECK (preferred_channel IN (
        'email','linkedin','whatsapp','voice','video'
      ));
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- 2. OUTREACH_LOG (NEW — central channel log)
-- ─────────────────────────────────────────────────────────────────
-- Single source of truth for every outbound touch regardless of
-- channel. Per-channel tables below carry the provider-specific
-- metadata; this table carries the cross-channel state used by the
-- pipeline and the monitoring dashboard.

CREATE TABLE IF NOT EXISTS outreach_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id         uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id       uuid REFERENCES clients(id) ON DELETE SET NULL,
  channel         text NOT NULL DEFAULT 'email',
  channel_status  text,
  subject         text,
  message_excerpt text,
  provider_ref    text,
  sent_at         timestamptz DEFAULT now(),
  metadata        jsonb,
  created_at      timestamptz DEFAULT now()
);

-- Idempotent backfill — if an older outreach_log existed without these
-- columns, add them without failing the migration.
ALTER TABLE outreach_log
  ADD COLUMN IF NOT EXISTS channel        text DEFAULT 'email',
  ADD COLUMN IF NOT EXISTS channel_status text;

CREATE INDEX IF NOT EXISTS idx_outreach_log_lead    ON outreach_log(lead_id);
CREATE INDEX IF NOT EXISTS idx_outreach_log_client  ON outreach_log(client_id, sent_at);
CREATE INDEX IF NOT EXISTS idx_outreach_log_channel ON outreach_log(channel, sent_at);

ALTER TABLE outreach_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS outreach_log_service_role_all ON outreach_log;
CREATE POLICY outreach_log_service_role_all ON outreach_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 3. CHANNELS ENABLED ON clients
-- ─────────────────────────────────────────────────────────────────
-- Per-client allowlist — a client with Gmail-only workflow auth keeps
-- '["email"]' and never gets routed to LinkedIn/WhatsApp/Voice even if
-- the lead-level preferred_channel says otherwise.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS channels_enabled jsonb DEFAULT '["email"]'::jsonb;


-- ─────────────────────────────────────────────────────────────────
-- 4. NICHE OVERLAY — PREFERRED CHANNELS + VOICE SCRIPT
-- ─────────────────────────────────────────────────────────────────
-- Per-niche fallback order when the lead-level routing doesn't have a
-- strong signal. The voice_script_template is personalized at call
-- time by the voice-outreach workflow (Claude Haiku interpolation).

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS preferred_channels     jsonb DEFAULT '["email"]'::jsonb,
  ADD COLUMN IF NOT EXISTS voice_script_template  text;

-- Seed the insurance_broker overlay. Guarded so the UPDATE doesn't
-- stomp over Mary's future edits — only runs when the columns are
-- still at their default / NULL state.
UPDATE niche_overlays
SET preferred_channels = '["email", "voice", "linkedin", "whatsapp"]'::jsonb
WHERE niche_name = 'insurance_broker'
  AND (preferred_channels IS NULL OR preferred_channels = '["email"]'::jsonb);

UPDATE niche_overlays
SET voice_script_template = 'Hi, this is Mary from Crystallux. I work with insurance brokers in {city} like you at {company}. Most brokers I speak with are losing clients during renewal season to rate-shopping sites. We help you reach out to every client 60 days before their renewal, automatically. My founding broker clients are booking 10 discovery meetings per month. I''d love 20 minutes to show you how it works at {company}. Can I send you a Calendly link to grab a time this week?'
WHERE niche_name = 'insurance_broker'
  AND voice_script_template IS NULL;


-- ─────────────────────────────────────────────────────────────────
-- 5. PER-CHANNEL PROVIDER LOGS
-- ─────────────────────────────────────────────────────────────────
-- Provider-specific metadata captured verbatim. Cross-channel state
-- lives in outreach_log; these tables exist so we can replay / audit
-- against the provider API when reconciling failures.

CREATE TABLE IF NOT EXISTS linkedin_outreach_log (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id            uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id          uuid REFERENCES clients(id) ON DELETE SET NULL,
  unipile_chat_id    text,
  message_text       text,
  sent_at            timestamptz DEFAULT now(),
  status             text,
  response_received  boolean NOT NULL DEFAULT false,
  metadata           jsonb,
  created_at         timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_linkedin_log_lead
  ON linkedin_outreach_log(lead_id);
CREATE INDEX IF NOT EXISTS idx_linkedin_log_client
  ON linkedin_outreach_log(client_id, sent_at);

ALTER TABLE linkedin_outreach_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS linkedin_outreach_log_service_role_all ON linkedin_outreach_log;
CREATE POLICY linkedin_outreach_log_service_role_all ON linkedin_outreach_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


CREATE TABLE IF NOT EXISTS whatsapp_outreach_log (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id            uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id          uuid REFERENCES clients(id) ON DELETE SET NULL,
  twilio_message_sid text,
  message_text       text,
  sent_at            timestamptz DEFAULT now(),
  status             text,
  response_received  boolean NOT NULL DEFAULT false,
  metadata           jsonb,
  created_at         timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_log_lead
  ON whatsapp_outreach_log(lead_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_log_client
  ON whatsapp_outreach_log(client_id, sent_at);

ALTER TABLE whatsapp_outreach_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS whatsapp_outreach_log_service_role_all ON whatsapp_outreach_log;
CREATE POLICY whatsapp_outreach_log_service_role_all ON whatsapp_outreach_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


CREATE TABLE IF NOT EXISTS voice_call_log (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id        uuid REFERENCES leads(id) ON DELETE CASCADE,
  client_id      uuid REFERENCES clients(id) ON DELETE SET NULL,
  vapi_call_id   text,
  call_outcome   text,
  duration_sec   integer,
  transcript     text,
  recording_url  text,
  cost_usd       numeric(10,4),
  called_at      timestamptz DEFAULT now(),
  metadata       jsonb,
  created_at     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_voice_call_log_lead
  ON voice_call_log(lead_id);
CREATE INDEX IF NOT EXISTS idx_voice_call_log_client
  ON voice_call_log(client_id, called_at);
CREATE INDEX IF NOT EXISTS idx_voice_call_log_vapi
  ON voice_call_log(vapi_call_id)
  WHERE vapi_call_id IS NOT NULL;

ALTER TABLE voice_call_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS voice_call_log_service_role_all ON voice_call_log;
CREATE POLICY voice_call_log_service_role_all ON voice_call_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 6. DAILY COUNT RPCs (per-channel rate limits)
-- ─────────────────────────────────────────────────────────────────
-- Mirrors get_daily_send_count_per_client (email) from the scale
-- sprint migration. Each channel workflow calls its RPC pre-flight to
-- gate against per-day caps.
--   LinkedIn: 20 connections/day/account (Unipile safety + platform
--             non-automation enforcement)
--   WhatsApp: default 100/day/client (Twilio template-message pacing)
--   Voice:    50/day/client (Vapi + human follow-up workload)

CREATE OR REPLACE FUNCTION get_daily_linkedin_count(p_client_id uuid DEFAULT NULL)
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
  FROM linkedin_outreach_log
  WHERE sent_at >= CURRENT_DATE
    AND sent_at <  CURRENT_DATE + interval '1 day'
    AND (p_client_id IS NULL OR client_id = p_client_id);
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_linkedin_count(uuid) TO service_role;


CREATE OR REPLACE FUNCTION get_daily_whatsapp_count(p_client_id uuid DEFAULT NULL)
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
  FROM whatsapp_outreach_log
  WHERE sent_at >= CURRENT_DATE
    AND sent_at <  CURRENT_DATE + interval '1 day'
    AND (p_client_id IS NULL OR client_id = p_client_id);
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_whatsapp_count(uuid) TO service_role;


CREATE OR REPLACE FUNCTION get_daily_voice_count(p_client_id uuid DEFAULT NULL)
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
  FROM voice_call_log
  WHERE called_at >= CURRENT_DATE
    AND called_at <  CURRENT_DATE + interval '1 day'
    AND (p_client_id IS NULL OR client_id = p_client_id);
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_voice_count(uuid) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 7. DNCL PLACEHOLDER
-- ─────────────────────────────────────────────────────────────────
-- Canadian Do-Not-Call List compliance placeholder. Real
-- implementation requires a paid CRTC DNCL subscription and a
-- synchronized local mirror (refreshed daily). For Part B.6 we return
-- TRUE unconditionally so the voice workflow's compliance gate is
-- wired but permissive. Mary must replace this with the real check
-- BEFORE the first live Canadian call.

CREATE OR REPLACE FUNCTION check_dncl_status(p_phone_number text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  -- PLACEHOLDER — always passes. Replace with real CRTC DNCL lookup
  -- before activating voice outreach to Canadian numbers.
  SELECT true;
$$;

GRANT EXECUTE ON FUNCTION check_dncl_status(text) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 8. MONITORING THRESHOLDS (new error codes)
-- ─────────────────────────────────────────────────────────────────
-- Matches the error codes the new channel workflows emit to
-- scan_errors. Uses ON CONFLICT DO NOTHING so re-runs are safe and
-- Mary can tune the thresholds in the dashboard without them getting
-- clobbered.

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('LINKEDIN_SEND_FAILED',  10, 5,  'warning'),
  ('WHATSAPP_SEND_FAILED',  10, 5,  'warning'),
  ('VOICE_CALL_FAILED',     10, 3,  'critical'),
  ('VOICE_DNCL_BLOCKED',    60, 1,  'critical')
ON CONFLICT (error_code) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 9. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 5
SELECT 'leads channel-routing columns' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'preferred_channel','channels_attempted',
    'last_channel_attempted','last_channel_attempted_at','country'
  );

-- Expect 1
SELECT 'leads.preferred_channel check constraint' AS check_name,
       COUNT(*) AS present
FROM pg_constraint
WHERE conname = 'leads_preferred_channel_check';

-- Expect 1
SELECT 'clients.channels_enabled' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'clients' AND column_name = 'channels_enabled';

-- Expect 4 (outreach_log, linkedin_outreach_log, whatsapp_outreach_log, voice_call_log)
SELECT 'channel log tables' AS check_name,
       COUNT(*) AS present
FROM information_schema.tables
WHERE table_name IN (
  'outreach_log','linkedin_outreach_log',
  'whatsapp_outreach_log','voice_call_log'
);

-- Expect 4
SELECT 'per-channel RPCs' AS check_name,
       COUNT(*) AS present
FROM information_schema.routines
WHERE routine_name IN (
  'get_daily_linkedin_count','get_daily_whatsapp_count',
  'get_daily_voice_count','check_dncl_status'
);

-- Expect 1 row with the seeded voice script and 4-item preferred_channels
SELECT niche_name,
       jsonb_array_length(preferred_channels) AS channel_count,
       length(voice_script_template) AS script_len
FROM niche_overlays
WHERE niche_name = 'insurance_broker';


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo — test on staging first)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 8. Monitoring thresholds added by this migration
-- DELETE FROM monitoring_thresholds
-- WHERE error_code IN (
--   'LINKEDIN_SEND_FAILED','WHATSAPP_SEND_FAILED',
--   'VOICE_CALL_FAILED','VOICE_DNCL_BLOCKED'
-- );
--
-- -- 7. DNCL placeholder
-- DROP FUNCTION IF EXISTS check_dncl_status(text);
--
-- -- 6. Daily count RPCs
-- DROP FUNCTION IF EXISTS get_daily_linkedin_count(uuid);
-- DROP FUNCTION IF EXISTS get_daily_whatsapp_count(uuid);
-- DROP FUNCTION IF EXISTS get_daily_voice_count(uuid);
--
-- -- 5. Per-channel provider logs
-- DROP TABLE IF EXISTS voice_call_log        CASCADE;
-- DROP TABLE IF EXISTS whatsapp_outreach_log CASCADE;
-- DROP TABLE IF EXISTS linkedin_outreach_log CASCADE;
--
-- -- 4. Niche overlay multi-channel fields
-- ALTER TABLE niche_overlays
--   DROP COLUMN IF EXISTS preferred_channels,
--   DROP COLUMN IF EXISTS voice_script_template;
--
-- -- 3. Clients channels_enabled
-- ALTER TABLE clients DROP COLUMN IF EXISTS channels_enabled;
--
-- -- 2. Outreach log (DROP ONLY IF you are certain it was created by
-- --    this migration — earlier environments may have their own).
-- DROP TABLE IF EXISTS outreach_log CASCADE;
--
-- -- 1. Leads channel-routing fields
-- ALTER TABLE leads DROP CONSTRAINT IF EXISTS leads_preferred_channel_check;
-- ALTER TABLE leads
--   DROP COLUMN IF EXISTS preferred_channel,
--   DROP COLUMN IF EXISTS channels_attempted,
--   DROP COLUMN IF EXISTS last_channel_attempted,
--   DROP COLUMN IF EXISTS last_channel_attempted_at,
--   DROP COLUMN IF EXISTS country;
