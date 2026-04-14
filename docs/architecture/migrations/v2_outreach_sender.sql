-- ============================================================================
-- Crystallux Outreach Sender v2 — RPC functions
-- Apply in Supabase SQL Editor before importing clx-outreach-sender-v2.json
-- ============================================================================

-- mark_lead_send_failed appends to leads.notes; ensure the column exists.
ALTER TABLE leads ADD COLUMN IF NOT EXISTS notes text;

-- ---------------------------------------------------------------------------
-- 1. update_lead_after_send — atomic update after a successful Gmail send
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_lead_after_send(
  p_lead_id uuid,
  p_outreach_sent_at timestamptz DEFAULT now(),
  p_followup_scheduled_at timestamptz DEFAULT NULL,
  p_lead_status text DEFAULT 'Contacted',
  p_outreach_channel text DEFAULT 'email',
  p_total_emails_sent integer DEFAULT 1,
  p_last_email_sent_at timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_id uuid;
BEGIN
  UPDATE leads SET
    outreach_sent_at      = p_outreach_sent_at,
    followup_scheduled_at = p_followup_scheduled_at,
    lead_status           = p_lead_status,
    outreach_channel      = p_outreach_channel,
    total_emails_sent     = p_total_emails_sent,
    last_email_sent_at    = p_last_email_sent_at,
    updated_at            = now()
  WHERE id = p_lead_id
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Lead not found: ' || p_lead_id);
  END IF;

  RETURN jsonb_build_object('status', 'updated', 'id', v_updated_id);
END;
$$;

GRANT EXECUTE ON FUNCTION update_lead_after_send(uuid, timestamptz, timestamptz, text, text, integer, timestamptz) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. mark_lead_send_failed — record a Gmail send failure on the lead
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mark_lead_send_failed(
  p_lead_id uuid,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE leads SET
    lead_status = 'Send Failed',
    notes       = COALESCE(notes, '') || E'\n[SEND FAILED ' || now()::text || '] ' || COALESCE(p_error_message, 'Unknown error'),
    updated_at  = now()
  WHERE id = p_lead_id;

  RETURN jsonb_build_object('status', 'marked_failed', 'id', p_lead_id);
END;
$$;

GRANT EXECUTE ON FUNCTION mark_lead_send_failed(uuid, text) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. get_daily_send_count — Gmail daily-limit guard (450 = safe headroom)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_daily_send_count()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM leads
  WHERE last_email_sent_at >= CURRENT_DATE
    AND last_email_sent_at <  CURRENT_DATE + interval '1 day';

  RETURN jsonb_build_object(
    'count',     v_count,
    'limit',     450,
    'remaining', GREATEST(450 - v_count, 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_send_count() TO service_role;
