-- =============================================================================
-- v2.2.1 — Fix update_lead(uuid, jsonb) RPC
-- =============================================================================
-- Problem: The prior implementation used jsonb_each_text + quote_nullable to
-- build dynamic SQL. That stringifies every value, which silently corrupts
-- writes to boolean / timestamptz / integer columns (e.g. email_enriched gets
-- 'true' (text) instead of true (boolean) and the UPDATE either errors out or
-- is swallowed depending on the caller's error handling).
--
-- Fix: replace with an explicit, typed UPDATE that casts each allowed field
-- from p_fields->>'key' to its column type. Unknown keys in p_fields are
-- ignored. Only columns meant to be updated via this RPC are listed.
--
-- Callers: at v2.2.1 the email scraper has been migrated to a direct PATCH
-- against /rest/v1/leads, so this RPC is kept as a safety net for any other
-- service or ad-hoc tooling that still calls it.
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
    RAISE EXCEPTION 'update_lead: p_fields must be a JSON object, got %', jsonb_typeof(p_fields)
      USING ERRCODE = '22023';
  END IF;

  UPDATE leads AS l SET
    email             = COALESCE(NULLIF(p_fields->>'email', ''),           l.email),
    email_enriched    = COALESCE((p_fields->>'email_enriched')::boolean,    l.email_enriched),
    email_enriched_at = COALESCE((p_fields->>'email_enriched_at')::timestamptz, l.email_enriched_at),
    do_not_contact    = COALESCE((p_fields->>'do_not_contact')::boolean,    l.do_not_contact),
    lead_status       = COALESCE(NULLIF(p_fields->>'lead_status', ''),      l.lead_status),
    lead_type         = COALESCE(NULLIF(p_fields->>'lead_type', ''),        l.lead_type),
    product_type      = COALESCE(NULLIF(p_fields->>'product_type', ''),     l.product_type),
    full_name         = COALESCE(NULLIF(p_fields->>'full_name', ''),        l.full_name),
    company           = COALESCE(NULLIF(p_fields->>'company', ''),          l.company),
    industry          = COALESCE(NULLIF(p_fields->>'industry', ''),         l.industry),
    city              = COALESCE(NULLIF(p_fields->>'city', ''),             l.city),
    phone             = COALESCE(NULLIF(p_fields->>'phone', ''),            l.phone),
    notes             = COALESCE(p_fields->>'notes',                        l.notes),
    updated_at        = COALESCE((p_fields->>'updated_at')::timestamptz,    now())
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
