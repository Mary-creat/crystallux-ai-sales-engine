-- ============================================================
-- Vertical context: MAXI taxonomy mapping, two config columns,
-- and one capability that reads them.
--
-- Why this exists
-- ---------------
-- Verified 2026-08-30 against production:
--
--   * niche_overlays IS the source of vertical behaviour. Eight
--     workflows read it -- campaign router, lead scoring, outreach
--     generation, Apollo enrichment, signal intelligence, video
--     outreach, voice outreach, copilot query.
--   * maxi_industries (22 rows) and maxi_industry_value_props (168)
--     are MARKETING copy. They are read by exactly two workflows,
--     both of which are MAXI's own listing endpoints, both inactive.
--   * The two taxonomies share only 3 slugs and have no foreign key,
--     so "construction" exists twice with different ids and nothing
--     joins them.
--
-- This migration does NOT move industry configuration into MAXI, and
-- does not move marketing copy into niche_overlays. It adds the one
-- missing edge between them, plus the two configuration fields that
-- genuinely have no home today.
--
-- Idempotent. Safe to re-run. Applies no data changes beyond the slug
-- mapping, which is confined to rows whose names already match.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Two configuration columns on the canonical vertical table
--
-- Roughly a dozen concepts in the multi-vertical brief have no home:
-- signal_weights, intent_rules, qualification_rules, terminology,
-- objection_handling, sales_process, followup_cadence,
-- conversion_event, channel_strategy.
--
-- Adding a dozen columns would make the table wider than it already
-- is (22 columns) for data that is always read as a whole and never
-- filtered on. Two structured JSONB fields keep the read pattern the
-- workflows already use -- fetch the row, read the keys.
--
-- behavior_config      = how to think about a buyer in this industry
-- sales_process_config = what sequence to run and what counts as won
-- ------------------------------------------------------------

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS behavior_config      jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS sales_process_config jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN niche_overlays.behavior_config IS
  'Industry buyer model. Keys: signal_types, signal_weights, intent_rules, '
  'qualification_rules, objection_handling, terminology, message_length. '
  'GLOBAL industry knowledge only -- never per-tenant learning, which '
  'belongs in client_icp_profiles.';

COMMENT ON COLUMN niche_overlays.sales_process_config IS
  'Stage sequence and conversion definition. Keys: sales_process (ordered '
  'stage list), followup_cadence, channel_strategy, conversion_event, '
  'average_sales_cycle_days, cta_types.';

-- ------------------------------------------------------------
-- 2. The missing edge: MAXI marketing industry -> operable vertical
--
-- Nullable on purpose. MAXI markets 22 industries; the Sales Engine
-- is configured for 8. A NULL here is not a defect -- it is the
-- honest statement "we advertise this industry and cannot yet run a
-- campaign for it", and it is queryable, which the current state is
-- not.
-- ------------------------------------------------------------

ALTER TABLE maxi_industries
  ADD COLUMN IF NOT EXISTS niche_overlay_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'maxi_industries_niche_overlay_fk'
  ) THEN
    ALTER TABLE maxi_industries
      ADD CONSTRAINT maxi_industries_niche_overlay_fk
      FOREIGN KEY (niche_overlay_id) REFERENCES niche_overlays(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS maxi_industries_niche_overlay_idx
  ON maxi_industries (niche_overlay_id)
  WHERE niche_overlay_id IS NOT NULL;

COMMENT ON COLUMN maxi_industries.niche_overlay_id IS
  'The operable vertical behind this marketing industry. NULL means the '
  'industry is marketed but the Sales Engine has no configuration for it '
  'yet -- deliberately visible rather than implied.';

-- ------------------------------------------------------------
-- 3. Resolve the slug drift
--
-- Only mappings where the industry is genuinely the same are made.
-- Judgement calls are left NULL rather than guessed: MAXI's
-- "coaches" is not niche_overlays' "consulting", and "mortgage" is
-- not "insurance_broker". A wrong mapping would silently route a
-- campaign using the wrong ICP, which is worse than no mapping.
-- ------------------------------------------------------------

UPDATE maxi_industries mi
   SET niche_overlay_id = no.id
  FROM niche_overlays no
 WHERE mi.niche_overlay_id IS NULL
   AND no.niche_name = CASE mi.industry_slug
         WHEN 'construction' THEN 'construction'
         WHEN 'dental'       THEN 'dental'
         WHEN 'real_estate'  THEN 'real_estate'
         WHEN 'cleaning'     THEN 'cleaning_services'  -- slug drift
         WHEN 'lawyers'      THEN 'legal'              -- slug drift
         ELSE NULL
       END;

-- ------------------------------------------------------------
-- 4. get_vertical_context() -- one capability, read by anything
--
-- Deliberately NOT named after MAXI. MAXI is a marketing persona and
-- a product grant; naming a data contract after it would weld a brand
-- to a schema and guarantee a rename later. Sales, Copilot, the agent
-- runtime and MAXI itself are all callers of equal standing.
--
-- Global industry knowledge comes from niche_overlays. Tenant
-- specifics are layered on top from client_icp_profiles when a
-- client_id is supplied, and are returned in their own key rather
-- than merged, so a caller can always tell which is which -- and so
-- one tenant's learning can never overwrite another industry's
-- defaults.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_vertical_context(
  p_vertical  text,
  p_client_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_overlay niche_overlays%ROWTYPE;
  v_tenant  jsonb := NULL;
BEGIN
  IF p_vertical IS NULL OR btrim(p_vertical) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vertical_required');
  END IF;

  -- Accept either the operational slug or the display vertical, because
  -- callers in the wild pass both.
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
      'hint', 'niche_overlays has no row for this vertical; it may be '
              'marketed in maxi_industries without being operable'
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
    'ok',          true,
    'vertical',    v_overlay.niche_name,
    'vertical_name', COALESCE(v_overlay.niche_display_name, v_overlay.display_name),
    'is_active',   v_overlay.is_active,
    'target_entity_type', v_overlay.lead_target_type,

    -- who to look for
    'icp',                v_overlay.icp_template,
    'decision_maker_titles', v_overlay.apollo_title_keywords,
    'discovery_sources',  v_overlay.lead_discovery_sources,
    'routing',            v_overlay.routing_preferences,

    -- how to think about them
    'pain_points',        v_overlay.pain_signals,
    'behavior',           v_overlay.behavior_config,

    -- how to talk to them
    'tone',               v_overlay.outreach_tone,
    'system_prompt',      v_overlay.claude_system_prompt,
    'terminology',        COALESCE(v_overlay.behavior_config -> 'terminology',
                                   v_overlay.dashboard_labels),
    'dashboard_labels',   v_overlay.dashboard_labels,
    'preferred_channels', v_overlay.preferred_channels,

    -- what to sell and how the process runs
    'offers',             v_overlay.offer_mapping,
    'sales_process',      v_overlay.sales_process_config,
    'compliance',         v_overlay.compliance_notes,

    -- tenant layer, kept separate on purpose
    'tenant',             v_tenant,
    'has_tenant_overlay', (v_tenant IS NOT NULL),

    'source', 'niche_overlays',
    'generated_at', now()
  );
END;
$$;

COMMENT ON FUNCTION get_vertical_context(text, uuid) IS
  'Canonical vertical context for any caller: Sales Engine, Copilot, agent '
  'runtime, MAXI. Global industry knowledge from niche_overlays; per-tenant '
  'specifics from client_icp_profiles returned separately under "tenant" so '
  'the two can never be confused or cross-contaminated.';

GRANT EXECUTE ON FUNCTION get_vertical_context(text, uuid) TO service_role;

COMMIT;

-- ------------------------------------------------------------
-- Verify (run separately, after COMMIT)
-- ------------------------------------------------------------
-- select industry_slug, niche_overlay_id is not null as mapped
--   from maxi_industries order by mapped desc, industry_slug;
--
-- select get_vertical_context('construction');
-- select get_vertical_context('insurance_broker');
-- select get_vertical_context('nope_not_a_vertical');
