-- ============================================================
-- Onboarding → client_icp_profiles
--
-- Everything needed already exists and nothing connects it:
--   client_onboarding        a checklist -- icp_defined, calendar_configured,
--                            goals_set -- with 0 rows
--   client_onboarding_status a milestone timeline, 2 rows
--   client_icp_profiles      the tenant targeting store, 0 rows
--   niche_overlays           global vertical knowledge, 8 rows, fully configured
--   clients                  offer_override, calendly_link, channels_enabled
--
-- So no second onboarding framework is built here. One function writes the
-- tenant's answers into the stores that already hold them, and ticks the
-- checklist box that already exists.
--
-- THE DIVISION, which is the whole point:
--   niche_overlays      = what is true of the INDUSTRY. Never written here.
--   client_icp_profiles = what is true of THIS TENANT. Only overrides.
--   clients             = how this tenant DELIVERS -- offer, calendar, channels.
--
-- Where a tenant does not answer, the vertical default is read from
-- niche_overlays at write time rather than copied in. A tenant that says
-- nothing about buyer titles inherits the industry's; a tenant that names
-- its own gets its own. The global row is never modified.
--
-- Idempotent: re-running for the same (client, vertical) updates that
-- profile rather than accumulating duplicates.
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
  IF p_titles IS NULL THEN v_inherited := v_inherited || 'titles'; END IF;

  v_include := COALESCE(p_include_keywords,
    ARRAY(SELECT jsonb_array_elements_text(
      COALESCE(v_overlay.routing_preferences -> 'search_keywords', '[]'::jsonb))));
  IF p_include_keywords IS NULL THEN v_inherited := v_inherited || 'include_keywords'; END IF;

  v_exclude := COALESCE(p_exclude_keywords,
    ARRAY(SELECT jsonb_array_elements_text(
      COALESCE(v_overlay.routing_preferences -> 'exclude_keywords', '[]'::jsonb))));
  IF p_exclude_keywords IS NULL THEN v_inherited := v_inherited || 'exclude_keywords'; END IF;

  v_signals := COALESCE(p_signal_types,
    ARRAY(SELECT jsonb_array_elements_text(
      COALESCE(v_overlay.behavior_config -> 'signal_types', '[]'::jsonb))));
  IF p_signal_types IS NULL THEN v_inherited := v_inherited || 'signal_types'; END IF;

  v_geo := COALESCE(p_geography, v_overlay.icp_template ->> 'geography');
  IF p_geography IS NULL THEN v_inherited := v_inherited || 'geography'; END IF;

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
    offer_override   = COALESCE(p_offer, offer_override),
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
-- Expect the function.
SELECT proname, pronargs FROM pg_proc WHERE proname = 'upsert_client_icp_from_onboarding';

-- Expect ok=false, vertical_not_configured. Restaurants are marketed by MAXI
-- and cannot be operated, so a tenant must not be able to onboard into one.
SELECT upsert_client_icp_from_onboarding(
  '6edc687d-07b0-4478-bb4b-820dc4eebf5d'::uuid, 'restaurant') AS unconfigured_vertical_refused;

-- Expect ok=false, unknown client.
SELECT upsert_client_icp_from_onboarding(
  '00000000-0000-0000-0000-000000000000'::uuid, 'construction') AS unknown_client_refused;

-- Expect 0 until a real onboarding runs. This migration creates no profile.
SELECT count(*) AS icp_profiles FROM client_icp_profiles;
