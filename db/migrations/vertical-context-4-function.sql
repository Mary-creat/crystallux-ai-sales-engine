-- ============================================================
-- Vertical context, step 4 of 5 — get_vertical_context()
--
-- One capability that any caller reads vertical behaviour from:
-- Sales Engine, Copilot, agent runtime, MAXI. Deliberately not named
-- after MAXI -- MAXI is a brand and a product grant, and naming a data
-- contract after a persona guarantees a rename later.
--
-- Global industry knowledge comes from niche_overlays. Tenant
-- specifics come from client_icp_profiles and are returned under their
-- own "tenant" key rather than merged, so a caller can always tell
-- which is which and one tenant's learning can never overwrite another
-- industry's defaults.
--
-- Requires step 1 (reads behavior_config and sales_process_config).
-- Idempotent: CREATE OR REPLACE. Uses the $fn$ tag rather than $$.
-- ============================================================

CREATE OR REPLACE FUNCTION get_vertical_context(
  p_vertical  text,
  p_client_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_overlay niche_overlays%ROWTYPE;
  v_tenant  jsonb := NULL;
BEGIN
  IF p_vertical IS NULL OR btrim(p_vertical) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vertical_required');
  END IF;

  -- Accept either the operational slug or the display vertical: callers
  -- in the wild pass both.
  SELECT * INTO v_overlay
    FROM niche_overlays
   WHERE niche_name = p_vertical
      OR vertical   = p_vertical
   ORDER BY (niche_name = p_vertical) DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'vertical_not_configured',
      'vertical', p_vertical,
      'hint', 'no niche_overlays row; the industry may be marketed in maxi_industries without being operable'
    );
  END IF;

  IF p_client_id IS NOT NULL THEN
    SELECT to_jsonb(c) INTO v_tenant
      FROM client_icp_profiles c
     WHERE c.client_id = p_client_id
       AND c.vertical  = v_overlay.niche_name
       AND c.is_active IS NOT FALSE
     ORDER BY c.created_at DESC
     LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'ok',                     true,
    'vertical',               v_overlay.niche_name,
    'vertical_name',          COALESCE(v_overlay.niche_display_name, v_overlay.display_name),
    'is_active',              v_overlay.is_active,
    'target_entity_type',     v_overlay.lead_target_type,
    'icp',                    v_overlay.icp_template,
    'decision_maker_titles',  v_overlay.apollo_title_keywords,
    'discovery_sources',      v_overlay.lead_discovery_sources,
    'routing',                v_overlay.routing_preferences,
    'pain_points',            v_overlay.pain_signals,
    'behavior',               v_overlay.behavior_config,
    'tone',                   v_overlay.outreach_tone,
    'system_prompt',          v_overlay.claude_system_prompt,
    'terminology',            COALESCE(v_overlay.behavior_config -> 'terminology', v_overlay.dashboard_labels),
    'dashboard_labels',       v_overlay.dashboard_labels,
    'preferred_channels',     v_overlay.preferred_channels,
    'offers',                 v_overlay.offer_mapping,
    'sales_process',          v_overlay.sales_process_config,
    'compliance',             v_overlay.compliance_notes,
    'tenant',                 v_tenant,
    'has_tenant_overlay',     (v_tenant IS NOT NULL),
    'source',                 'niche_overlays',
    'generated_at',           now()
  );
END
$fn$;

COMMENT ON FUNCTION get_vertical_context(text, uuid) IS 'Canonical vertical context for Sales, Copilot, agents and MAXI. Global knowledge from niche_overlays; tenant specifics returned separately under "tenant".';

GRANT EXECUTE ON FUNCTION get_vertical_context(text, uuid) TO service_role;

-- ---- VERIFY ----
-- Expect 1.
SELECT count(*) AS function_definitions
  FROM pg_proc WHERE proname = 'get_vertical_context';

-- Expect ok=true and a vertical name back.
SELECT get_vertical_context('construction') -> 'ok'       AS construction_ok,
       get_vertical_context('insurance_broker') -> 'ok'   AS insurance_ok;

-- Expect ok=false, error=vertical_not_configured. Restaurants are
-- marketed by MAXI but have no niche_overlays row -- this proves the
-- capability reports that honestly rather than inventing a default.
SELECT get_vertical_context('restaurant') AS restaurant_expected_not_configured;
