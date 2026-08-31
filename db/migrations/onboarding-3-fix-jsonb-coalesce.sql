-- ============================================================
-- Onboarding fix 3 — jsonb/text mismatch, and self-contained
--
-- Two distinct bugs, both runtime-only. The SQL validator parses grammar
-- and both are grammatically valid, so only calling the function found
-- them.
--
--   1. v_inherited || 'titles' resolved as anyarray || anyarray, so the
--      untyped literal was coerced to text[] and threw
--      "malformed array literal". Five occurrences. Fixed with
--      array_append().
--
--   2. offer_override = COALESCE(p_offer, offer_override) mixed text with
--      jsonb. COALESCE requires one type on both sides.
--
-- SELF-CONTAINED ON PURPOSE. It carries fix 1 as well, so applying this
-- alone is sufficient whether or not onboarding-2 was ever applied. Two
-- files that must be applied in the right order to produce a working
-- function is exactly the fragility that has already cost several rounds
-- here.
--
-- WHAT WAS AUDITED, since fixing these one at a time is the failure mode:
-- every assignment in the function was type-checked against production
-- columns.
--   calendly_link    text   <- p_booking_url    text    ok
--   niche_name       text   <- overlay          text    ok
--   onboarding_stage text   <- literal          text    ok
--   channels_enabled jsonb  <- p_channels       jsonb   ok
--   offer_override   jsonb  <- p_offer          text    FIXED
--   titles etc.      text[] <- v_titles         text[]  ok
--   company_size_*   int    <- ->> ::int                ok
--   return payload   jsonb  <- to_jsonb(...)            ok
-- offer_override was the only mismatch. p_channels is already jsonb, so
-- no conversion is needed there.
--
-- WHY to_jsonb(p_offer) AND NOT AN OBJECT SHAPE: offer_override has no
-- consumer anywhere. Searched all 326 workflows, both dashboards, the
-- marketing site and every migration -- the only references are the
-- column definition in 2026-04-22-scale-sprint-v1.sql and this function.
-- With no canonical shape to reuse, a JSON string is the least
-- presumptuous choice; inventing an object structure nothing reads would
-- be guessing at a contract.
--
-- channels_enabled DOES have a canonical shape and it is preserved: all
-- four live clients hold a JSON array, ["email"]. p_channels is passed
-- through unchanged.
--
-- No schema change. No column type is altered.
-- ============================================================

CREATE OR REPLACE FUNCTION upsert_client_icp_from_onboarding(
  p_client_id        uuid,
  p_vertical         text,
  p_geography        text    DEFAULT NULL,
  p_company_size_min integer DEFAULT NULL,
  p_company_size_max integer DEFAULT NULL,
  p_titles           text[]  DEFAULT NULL,
  p_include_keywords text[]  DEFAULT NULL,
  p_exclude_keywords text[]  DEFAULT NULL,
  p_signal_types     text[]  DEFAULT NULL,
  p_offer            text    DEFAULT NULL,
  p_booking_url      text    DEFAULT NULL,
  p_channels         jsonb   DEFAULT NULL,
  p_objective        text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_overlay   niche_overlays%ROWTYPE;
  v_profile_id uuid;
  v_titles    text[];
  v_include   text[];
  v_exclude   text[];
  v_signals   text[];
  v_geo       text;
  v_inherited text[] := ARRAY[]::text[];
BEGIN
  IF p_client_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'client_id required');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM clients WHERE id = p_client_id) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown client');
  END IF;

  -- The vertical must be one the engine can actually operate. Accepting an
  -- unconfigured one would let a tenant onboard into a campaign that can
  -- never run -- MAXI markets 22 industries, the engine is configured for 8.
  SELECT * INTO v_overlay FROM niche_overlays
   WHERE niche_name = p_vertical OR vertical = p_vertical
   ORDER BY (niche_name = p_vertical) DESC LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'vertical_not_configured', 'vertical', p_vertical,
      'hint', 'The Sales Engine has no configuration for this vertical yet.');
  END IF;

  -- Tenant answer wins; otherwise inherit the industry default. Inheritance
  -- is recorded so the tenant can be shown what it did not choose.
  v_titles := COALESCE(p_titles,
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_overlay.apollo_title_keywords, '[]'::jsonb))));
  IF p_titles IS NULL THEN v_inherited := array_append(v_inherited, 'titles'); END IF;

  v_include := COALESCE(p_include_keywords,
    ARRAY(SELECT jsonb_array_elements_text(
      COALESCE(v_overlay.routing_preferences -> 'search_keywords', '[]'::jsonb))));
  IF p_include_keywords IS NULL THEN v_inherited := array_append(v_inherited, 'include_keywords'); END IF;

  v_exclude := COALESCE(p_exclude_keywords,
    ARRAY(SELECT jsonb_array_elements_text(
      COALESCE(v_overlay.routing_preferences -> 'exclude_keywords', '[]'::jsonb))));
  IF p_exclude_keywords IS NULL THEN v_inherited := array_append(v_inherited, 'exclude_keywords'); END IF;

  v_signals := COALESCE(p_signal_types,
    ARRAY(SELECT jsonb_array_elements_text(
      COALESCE(v_overlay.behavior_config -> 'signal_types', '[]'::jsonb))));
  IF p_signal_types IS NULL THEN v_inherited := array_append(v_inherited, 'signal_types'); END IF;

  v_geo := COALESCE(p_geography, v_overlay.icp_template ->> 'geography');
  IF p_geography IS NULL THEN v_inherited := array_append(v_inherited, 'geography'); END IF;

  -- One profile per (client, vertical). A tenant may target more than one
  -- industry; it may not accumulate duplicate profiles for the same one.
  SELECT id INTO v_profile_id FROM client_icp_profiles
   WHERE client_id = p_client_id AND vertical = v_overlay.niche_name LIMIT 1;

  IF v_profile_id IS NULL THEN
    INSERT INTO client_icp_profiles (
      client_id, name, vertical, geography, company_size_min, company_size_max,
      titles, include_keywords, exclude_keywords, signal_types, is_active
    ) VALUES (
      p_client_id,
      COALESCE(p_objective, v_overlay.niche_display_name, v_overlay.niche_name),
      v_overlay.niche_name, v_geo,
      COALESCE(p_company_size_min, (v_overlay.icp_template ->> 'company_size_min')::int),
      COALESCE(p_company_size_max, (v_overlay.icp_template ->> 'company_size_max')::int),
      v_titles, v_include, v_exclude, v_signals, true
    ) RETURNING id INTO v_profile_id;
  ELSE
    UPDATE client_icp_profiles SET
      name             = COALESCE(p_objective, name),
      geography        = v_geo,
      company_size_min = COALESCE(p_company_size_min, company_size_min),
      company_size_max = COALESCE(p_company_size_max, company_size_max),
      titles           = v_titles,
      include_keywords = v_include,
      exclude_keywords = v_exclude,
      signal_types     = v_signals,
      is_active        = true
     WHERE id = v_profile_id;
  END IF;

  -- Delivery preferences live on clients, where the sender and booking
  -- config already are. Only what the tenant supplied is written.
  UPDATE clients SET
    -- p_offer is text and offer_override is jsonb, so COALESCE saw two
    -- different types and refused. to_jsonb() converts the text into a
    -- JSON string, which is valid jsonb; a bare ::jsonb cast would have
    -- thrown on ordinary prose like 'Commercial cleaning contract',
    -- because that is not raw JSON.
    offer_override   = COALESCE(to_jsonb(p_offer), offer_override),
    calendly_link    = COALESCE(p_booking_url, calendly_link),
    channels_enabled = COALESCE(p_channels, channels_enabled),
    niche_name       = COALESCE(niche_name, v_overlay.niche_name),
    onboarding_stage = COALESCE(onboarding_stage, 'icp_defined'),
    updated_at       = now()
   WHERE id = p_client_id;

  -- Tick the checklist box that has existed all along and never been set.
  --
  -- Written as update-then-insert rather than ON CONFLICT (client_id):
  -- client_onboarding is unique on id only, so an upsert targeting
  -- client_id would fail at runtime with "no unique or exclusion
  -- constraint matching the ON CONFLICT specification". Adding that
  -- constraint would be presuming one onboarding row per client, and the
  -- table carries a `stage` column suggesting otherwise -- not a
  -- decision to make in passing.
  UPDATE client_onboarding
     SET icp_defined = true,
         stage = COALESCE(stage, 'icp_defined')
   WHERE client_id = p_client_id;

  IF NOT FOUND THEN
    INSERT INTO client_onboarding (client_id, stage, icp_defined)
    VALUES (p_client_id, 'icp_defined', true);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'profile_id', v_profile_id,
    'client_id', p_client_id,
    'vertical', v_overlay.niche_name,
    'geography', v_geo,
    'titles', to_jsonb(v_titles),
    'signal_types', to_jsonb(v_signals),
    'inherited_from_vertical', to_jsonb(v_inherited),
    'note', 'Vertical defaults are read from niche_overlays at write time; the global row is never modified.'
  );
END;
$fn$;

COMMENT ON FUNCTION upsert_client_icp_from_onboarding IS
  'Turns tenant onboarding answers into a client_icp_profiles row, inheriting '
  'unanswered fields from niche_overlays without copying or modifying global '
  'vertical configuration. Idempotent per (client, vertical).';

GRANT EXECUTE ON FUNCTION upsert_client_icp_from_onboarding(
  uuid,text,text,integer,integer,text[],text[],text[],text[],text,text,jsonb,text) TO service_role;



-- ---- VERIFY ----
-- Expect ok=true, vertical=construction, inherited_from_vertical listing
-- the five fields taken from the overlay.
SELECT upsert_client_icp_from_onboarding(
  '6edc687d-07b0-4478-bb4b-820dc4eebf5d'::uuid,
  'construction',
  p_offer      => 'Qualified construction project pipeline',
  p_channels   => '["email"]'::jsonb,
  p_booking_url=> 'https://calendly.com/crystallux/construction'
) AS onboarding_proof;

-- Expect 1 profile for the test tenant on construction.
SELECT client_id, vertical, geography, array_length(titles,1) AS title_count, is_active
  FROM client_icp_profiles;

-- Expect offer_override as a JSON string, channels_enabled as a JSON
-- array, and the three text fields populated.
SELECT jsonb_typeof(offer_override)   AS offer_type,
       offer_override,
       jsonb_typeof(channels_enabled) AS channels_type,
       channels_enabled,
       calendly_link, niche_name, onboarding_stage
  FROM clients WHERE id = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';

-- Expect 8 rows, none modified: onboarding must never write to global
-- vertical configuration.
SELECT count(*) AS niche_overlays_rows,
       count(*) FILTER (WHERE updated_at > now() - interval '10 minutes') AS modified_recently
  FROM niche_overlays;

-- Expect refusals, unchanged.
SELECT upsert_client_icp_from_onboarding(
  '00000000-0000-0000-0000-000000000000'::uuid,'construction') AS unknown_client_refused;
SELECT upsert_client_icp_from_onboarding(
  '6edc687d-07b0-4478-bb4b-820dc4eebf5d'::uuid,'restaurant') AS unconfigured_vertical_refused;
