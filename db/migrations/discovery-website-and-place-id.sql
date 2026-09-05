-- Discovery loses the website and the Google place id. This restores both.
--
-- WHAT IS BROKEN
--
-- clx-b2c-discovery-v2.1 asks Google for websiteUri, receives it, parses it
-- correctly into `website` -- and then Process Each Business writes it into
-- a prose note:
--
--   p_notes: 'Places ID: ' + place_id + ' | Address: ' + addr +
--            ' | Website: ' + website
--
-- insert_lead_if_not_exists has no p_website and no p_place_id, so both
-- land in a text blob and neither reaches its own column.
--
-- The consequence is the whole contact chain. clx-email-scraper-v3 selects
--   leads?website=not.is.null
-- so a lead with a NULL website is invisible to it forever. Discovery finds
-- a business, throws away the one field that could produce an email address,
-- and the lead can be researched and scored but never contacted. Twelve
-- leads arrived on 2026-09-05 with a website each; all twelve stored NULL.
--
-- DEDUPLICATION
--
-- Dedup matched on `company` string equality. Google's place id is an exact
-- identity for a specific business at a specific address, so when we have
-- one we use it: it catches the same shop listed under a slightly different
-- name, which a string compare misses. Company remains the fallback, and
-- leads_company_unique remains the backstop.
--
-- The reply now says WHICH rule matched and what already exists, because
-- "duplicate" on its own gives a caller nothing to act on.
--
-- KNOWN LIMIT, DELIBERATELY NOT CHANGED HERE
--
-- leads_company_unique makes company globally unique, so a chain -- two
-- branches of the same pharmacy in two cities -- can only ever be one lead.
-- For insurance brokers and movers that is correct. For Eazer merchant
-- recruitment each LOCATION is a separate merchant, so it is wrong. That is
-- a product decision about what a lead is, not a bug to fix quietly inside
-- a migration, and it is written up for the owner rather than acted on.
--
-- Additive and safe to re-run. The old 12-argument signature is dropped
-- explicitly: adding parameters to CREATE OR REPLACE would leave BOTH
-- versions resident and make a 12-argument named call ambiguous.

BEGIN;

DROP FUNCTION IF EXISTS insert_lead_if_not_exists(
  text, text, text, text, text, text, text, text, text, text, text, uuid);

CREATE OR REPLACE FUNCTION insert_lead_if_not_exists(
  p_full_name    text DEFAULT NULL,
  p_email        text DEFAULT NULL,
  p_phone        text DEFAULT NULL,
  p_company      text DEFAULT NULL,
  p_job_title    text DEFAULT 'Owner',
  p_industry     text DEFAULT NULL,
  p_city         text DEFAULT NULL,
  p_source       text DEFAULT 'google_maps_discovery',
  p_lead_status  text DEFAULT 'New Lead',
  p_product_type text DEFAULT NULL,
  p_notes        text DEFAULT NULL,
  p_client_id    uuid DEFAULT NULL,
  p_website      text DEFAULT NULL,   -- new, defaulted: callers need not change
  p_place_id     text DEFAULT NULL    -- new, defaulted
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_existing   leads%ROWTYPE;
  v_new_id     uuid;
  v_client_id  uuid;
  v_matched_on text;
  v_website    text := nullif(btrim(coalesce(p_website, '')), '');
  v_place_id   text := nullif(btrim(coalesce(p_place_id, '')), '');
BEGIN
  IF p_company IS NULL OR length(trim(p_company)) = 0 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'company is required');
  END IF;

  -- Identity first: a Google place id names one business at one address.
  IF v_place_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM leads WHERE place_id = v_place_id LIMIT 1;
    IF FOUND THEN v_matched_on := 'place_id'; END IF;
  END IF;

  IF v_matched_on IS NULL THEN
    SELECT * INTO v_existing FROM leads WHERE company = p_company LIMIT 1;
    IF FOUND THEN v_matched_on := 'company'; END IF;
  END IF;

  IF v_matched_on IS NOT NULL THEN
    -- Backfill what the existing row is missing rather than discarding a
    -- fresher answer. A lead that predates this fix has no website; the
    -- scan that just found one should not have to throw it away.
    UPDATE leads
       SET website  = COALESCE(website,  v_website),
           place_id = COALESCE(place_id, v_place_id),
           phone    = COALESCE(phone,    nullif(btrim(coalesce(p_phone,'')), '')),
           updated_at = now()
     WHERE id = v_existing.id
       AND (  (website  IS NULL AND v_website  IS NOT NULL)
           OR (place_id IS NULL AND v_place_id IS NOT NULL)
           OR (phone    IS NULL AND nullif(btrim(coalesce(p_phone,'')),'') IS NOT NULL));

    RETURN jsonb_build_object(
      'status',            'duplicate',
      'id',                v_existing.id,
      'company',           v_existing.company,
      'matched_on',        v_matched_on,
      'existing_city',     v_existing.city,
      'existing_status',   v_existing.lead_status,
      'existing_pool',     v_existing.lead_pool,
      'enriched',          (v_existing.website IS NULL AND v_website IS NOT NULL)
                        OR (v_existing.place_id IS NULL AND v_place_id IS NOT NULL));
  END IF;

  IF p_client_id IS NOT NULL THEN
    v_client_id := p_client_id;
  ELSE
    SELECT id INTO v_client_id
      FROM clients
     WHERE active = true
       AND ( product_type = p_product_type
          OR (p_industry IS NOT NULL AND industry ILIKE '%' || p_industry || '%') )
     ORDER BY CASE WHEN product_type = p_product_type THEN 0 ELSE 1 END,
              CASE WHEN city = p_city                 THEN 0 ELSE 1 END,
              created_at ASC
     LIMIT 1;
  END IF;

  INSERT INTO leads (
    full_name, email, phone, company, job_title, industry, city,
    source, lead_status, product_type, notes, client_id, lead_pool,
    website, place_id
  )
  VALUES (
    p_full_name, p_email, p_phone, p_company, p_job_title, p_industry, p_city,
    p_source, p_lead_status, p_product_type, p_notes, v_client_id,
    CASE WHEN v_client_id IS NULL THEN 'house' ELSE 'tenant' END,
    v_website, v_place_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'status',         'inserted',
    'id',             v_new_id,
    'company',        p_company,
    'client_id',      v_client_id,
    'client_matched', v_client_id IS NOT NULL,
    'owner_explicit', p_client_id IS NOT NULL,
    'lead_pool',      CASE WHEN v_client_id IS NULL THEN 'house' ELSE 'tenant' END,
    'has_website',    v_website IS NOT NULL,
    'scrapable',      v_website IS NOT NULL);
END;
$fn$;

COMMENT ON FUNCTION insert_lead_if_not_exists(text,text,text,text,text,text,text,text,text,text,text,uuid,text,text) IS
  'Canonical lead insert. Dedups on place_id when supplied, else company, '
  'and reports which rule matched. Backfills website/place_id/phone onto an '
  'existing row rather than discarding a fresher answer.';

GRANT EXECUTE ON FUNCTION insert_lead_if_not_exists(text,text,text,text,text,text,text,text,text,text,text,uuid,text,text) TO service_role;

COMMIT;

-- Backfill: recover websites already captured in the notes blob, so the
-- email scraper can reach leads discovered before this fix.
--   UPDATE leads
--      SET website = substring(notes from 'Website: (https?://[^ |]+)')
--    WHERE website IS NULL
--      AND notes LIKE '%Website: %';
--
-- Verify:
--   SELECT count(*) FILTER (WHERE website IS NOT NULL) AS with_site,
--          count(*) FILTER (WHERE place_id IS NOT NULL) AS with_place,
--          count(*) AS total
--     FROM leads WHERE source = 'google_maps_discovery';
