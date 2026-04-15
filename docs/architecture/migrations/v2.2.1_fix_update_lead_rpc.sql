-- =============================================================================
-- v2.2.1 — Fix update_lead(uuid, jsonb) RPC
-- =============================================================================
-- PROBLEM
-- The prior implementation looped p_fields via jsonb_each_text and built a
-- dynamic UPDATE string wrapping every value in quote_nullable. That forces
-- EVERY value to text. For a boolean column the generated SQL becomes
--     SET email_enriched = 'true'
-- which either raises 22P02 (invalid input syntax for boolean) or, worse, is
-- swallowed by the caller and never applied. Same failure mode for integer
-- and timestamptz columns.
--
-- FIX
-- Replace the function with an explicit UPDATE that casts each allowed field
-- from p_fields to its real column type, wrapped in COALESCE so unset fields
-- are preserved. Text columns use NULLIF(..., '') so that accidentally passing
-- an empty string does not clobber existing values. Booleans / integers /
-- timestamptz are cast natively by PostgreSQL, so the JSON types `true`,
-- `42`, and ISO-8601 strings all land correctly.
--
-- Keys in p_fields that don't match a known column are silently ignored
-- (desired behaviour — callers shouldn't be able to write arbitrary columns).
--
-- At v2.2.1 the email-scraper workflow has been migrated to a direct PATCH
-- on /rest/v1/leads, so this RPC is kept as a safety net for any other caller.
-- =============================================================================

CREATE OR REPLACE FUNCTION update_lead(p_lead_id uuid, p_fields jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row leads;
BEGIN
  IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN
    RAISE EXCEPTION 'update_lead: p_fields must be a JSON object'
      USING ERRCODE = '22023';
  END IF;

  UPDATE leads AS l SET
    -- Identity / core (text)
    email                        = COALESCE(NULLIF(p_fields->>'email', ''),                   l.email),
    full_name                    = COALESCE(NULLIF(p_fields->>'full_name', ''),               l.full_name),
    company                      = COALESCE(NULLIF(p_fields->>'company', ''),                 l.company),
    industry                     = COALESCE(NULLIF(p_fields->>'industry', ''),                l.industry),
    city                         = COALESCE(NULLIF(p_fields->>'city', ''),                    l.city),
    phone                        = COALESCE(NULLIF(p_fields->>'phone', ''),                   l.phone),
    notes                        = COALESCE(p_fields->>'notes',                               l.notes),
    lead_status                  = COALESCE(NULLIF(p_fields->>'lead_status', ''),             l.lead_status),
    lead_type                    = COALESCE(NULLIF(p_fields->>'lead_type', ''),               l.lead_type),
    product_type                 = COALESCE(NULLIF(p_fields->>'product_type', ''),            l.product_type),

    -- Enrichment (boolean, timestamptz)
    email_enriched               = COALESCE((p_fields->>'email_enriched')::boolean,           l.email_enriched),
    email_enriched_at            = COALESCE((p_fields->>'email_enriched_at')::timestamptz,    l.email_enriched_at),
    do_not_contact               = COALESCE((p_fields->>'do_not_contact')::boolean,           l.do_not_contact),

    -- Scoring (integer, text)
    lead_score                   = COALESCE((p_fields->>'lead_score')::integer,               l.lead_score),
    priority_level               = COALESCE(NULLIF(p_fields->>'priority_level', ''),          l.priority_level),
    decision_maker_probability   = COALESCE(NULLIF(p_fields->>'decision_maker_probability', ''), l.decision_maker_probability),
    company_size_estimate        = COALESCE(NULLIF(p_fields->>'company_size_estimate', ''),   l.company_size_estimate),
    scoring_reason               = COALESCE(NULLIF(p_fields->>'scoring_reason', ''),          l.scoring_reason),

    -- Signal detection (text)
    detected_signal              = COALESCE(NULLIF(p_fields->>'detected_signal', ''),         l.detected_signal),
    growth_stage                 = COALESCE(NULLIF(p_fields->>'growth_stage', ''),            l.growth_stage),
    recommended_campaign_type    = COALESCE(NULLIF(p_fields->>'recommended_campaign_type', ''), l.recommended_campaign_type),
    signal_confidence            = COALESCE(NULLIF(p_fields->>'signal_confidence', ''),       l.signal_confidence),
    outreach_timing              = COALESCE(NULLIF(p_fields->>'outreach_timing', ''),         l.outreach_timing),

    -- Campaign router (text)
    campaign_name                = COALESCE(NULLIF(p_fields->>'campaign_name', ''),           l.campaign_name),
    campaign_type                = COALESCE(NULLIF(p_fields->>'campaign_type', ''),           l.campaign_type),
    campaign_value_proposition   = COALESCE(NULLIF(p_fields->>'campaign_value_proposition', ''), l.campaign_value_proposition),
    campaign_pain_point          = COALESCE(NULLIF(p_fields->>'campaign_pain_point', ''),     l.campaign_pain_point),
    campaign_call_to_action      = COALESCE(NULLIF(p_fields->>'campaign_call_to_action', ''), l.campaign_call_to_action),
    campaign_tone                = COALESCE(NULLIF(p_fields->>'campaign_tone', ''),           l.campaign_tone),

    -- Outreach generation (text, integer, timestamptz)
    email_subject                = COALESCE(NULLIF(p_fields->>'email_subject', ''),           l.email_subject),
    email_body                   = COALESCE(p_fields->>'email_body',                          l.email_body),
    linkedin_message             = COALESCE(p_fields->>'linkedin_message',                    l.linkedin_message),
    whatsapp_message             = COALESCE(p_fields->>'whatsapp_message',                    l.whatsapp_message),
    followup_message             = COALESCE(p_fields->>'followup_message',                    l.followup_message),
    outreach_angle               = COALESCE(NULLIF(p_fields->>'outreach_angle', ''),          l.outreach_angle),
    personalization_score        = COALESCE((p_fields->>'personalization_score')::integer,   l.personalization_score),
    outreach_generated_at        = COALESCE((p_fields->>'outreach_generated_at')::timestamptz, l.outreach_generated_at),

    -- Outreach sending
    outreach_sent_at             = COALESCE((p_fields->>'outreach_sent_at')::timestamptz,     l.outreach_sent_at),
    followup_scheduled_at        = COALESCE((p_fields->>'followup_scheduled_at')::timestamptz, l.followup_scheduled_at),
    outreach_channel             = COALESCE(NULLIF(p_fields->>'outreach_channel', ''),        l.outreach_channel),

    -- Follow-up sequence
    followup_count               = COALESCE((p_fields->>'followup_count')::integer,           l.followup_count),
    followup_sent_at             = COALESCE((p_fields->>'followup_sent_at')::timestamptz,     l.followup_sent_at),
    next_followup_scheduled_at   = COALESCE((p_fields->>'next_followup_scheduled_at')::timestamptz, l.next_followup_scheduled_at),
    reply_detected               = COALESCE((p_fields->>'reply_detected')::boolean,           l.reply_detected),

    -- Pipeline / stale tracking
    is_stale                     = COALESCE((p_fields->>'is_stale')::boolean,                 l.is_stale),
    stale_reason                 = COALESCE(NULLIF(p_fields->>'stale_reason', ''),            l.stale_reason),
    stale_detected_at            = COALESCE((p_fields->>'stale_detected_at')::timestamptz,    l.stale_detected_at),

    -- Booking flow
    reply_text                   = COALESCE(p_fields->>'reply_text',                          l.reply_text),
    interest_detected            = COALESCE((p_fields->>'interest_detected')::boolean,        l.interest_detected),
    booking_email_sent           = COALESCE((p_fields->>'booking_email_sent')::boolean,       l.booking_email_sent),
    booking_email_sent_at        = COALESCE((p_fields->>'booking_email_sent_at')::timestamptz, l.booking_email_sent_at),
    calendly_link                = COALESCE(NULLIF(p_fields->>'calendly_link', ''),           l.calendly_link),
    meeting_scheduled            = COALESCE((p_fields->>'meeting_scheduled')::boolean,        l.meeting_scheduled),
    meeting_datetime             = COALESCE((p_fields->>'meeting_datetime')::timestamptz,     l.meeting_datetime),
    meeting_notes                = COALESCE(p_fields->>'meeting_notes',                       l.meeting_notes),

    -- Always bump updated_at (caller can override by passing it explicitly)
    updated_at                   = COALESCE((p_fields->>'updated_at')::timestamptz,           now())
  WHERE l.id = p_lead_id
  RETURNING l.* INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_lead: lead % not found', p_lead_id
      USING ERRCODE = 'P0002';
  END IF;

  RETURN to_jsonb(v_row);
END;
$$;

GRANT EXECUTE ON FUNCTION update_lead(uuid, jsonb) TO anon, authenticated, service_role;

-- =============================================================================
-- SMOKE TESTS (run manually against a disposable test row)
-- =============================================================================
-- Run the block below in the Supabase SQL editor to verify the fix.
-- It creates a test lead, exercises boolean / integer / timestamptz / text
-- updates, and then cleans up.
--
-- DO $smoke$
-- DECLARE
--   v_id uuid;
--   v_result jsonb;
-- BEGIN
--   -- seed
--   INSERT INTO leads (full_name, company, email_enriched, do_not_contact, lead_score)
--   VALUES ('Smoke Test', 'Test Co', false, false, 0)
--   RETURNING id INTO v_id;
--
--   -- 1. boolean + text + timestamptz via RPC
--   v_result := update_lead(v_id, jsonb_build_object(
--     'email',             'smoke@test.local',
--     'email_enriched',    true,
--     'email_enriched_at', now()
--   ));
--   ASSERT (v_result->>'email_enriched')::boolean = true,
--     'email_enriched should be true, got ' || (v_result->>'email_enriched');
--   ASSERT v_result->>'email' = 'smoke@test.local',
--     'email should have been updated';
--
--   -- 2. integer cast
--   v_result := update_lead(v_id, jsonb_build_object('lead_score', 87));
--   ASSERT (v_result->>'lead_score')::integer = 87,
--     'lead_score should be 87, got ' || (v_result->>'lead_score');
--
--   -- 3. empty-string text must NOT clobber
--   v_result := update_lead(v_id, jsonb_build_object('email', ''));
--   ASSERT v_result->>'email' = 'smoke@test.local',
--     'empty string must not clobber existing email';
--
--   -- 4. unknown key is ignored
--   v_result := update_lead(v_id, jsonb_build_object('this_column_does_not_exist', 'x'));
--   ASSERT v_result IS NOT NULL, 'unknown keys should be ignored, not error';
--
--   -- cleanup
--   DELETE FROM leads WHERE id = v_id;
--   RAISE NOTICE 'update_lead smoke tests passed';
-- END
-- $smoke$;
