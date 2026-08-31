-- ============================================================
-- update_lead silently discarded every research and explainability column
--
-- The function takes p_fields jsonb and writes a fixed list of columns.
-- Anything not on that list is accepted, ignored, and reported as success.
-- Five columns the Sales Engine depends on were never on it:
--
--   research_summary       the research itself
--   likely_business_need   the inferred need
--   research_angle         the outreach angle
--   researched_at          when research completed
--   score_components       the explainable-scoring decomposition
--
-- lead_status IS on the list. So every research pass wrote its status and
-- lost its content: the lead read 'Researched' with research_summary NULL,
-- which is the exact shape that sent 1,373 leads to the scorer with nothing
-- to reason about. Three sprints of workflow fixes could not have worked,
-- because the workflow was never the thing dropping the data.
--
-- It also explains score_components staying at 0 across every scoring run.
-- Explainable scoring was blocked here, not in the scorer.
--
-- Everything else about the function is unchanged: same signature, same
-- return shape, same SECURITY DEFINER, same NULLIF semantics on text so an
-- empty string still means "leave it alone" rather than "erase it".
--
-- researched_at and score_components take the plain COALESCE form rather
-- than NULLIF: a timestamp and a jsonb object have no empty-string case,
-- and NULLIF on them would be a type error.
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_lead(p_lead_id uuid, p_fields jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn$
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

    -- Research. The five columns this migration exists for.
    research_summary             = COALESCE(NULLIF(p_fields->>'research_summary', ''),        l.research_summary),
    likely_business_need         = COALESCE(NULLIF(p_fields->>'likely_business_need', ''),    l.likely_business_need),
    research_angle               = COALESCE(NULLIF(p_fields->>'research_angle', ''),          l.research_angle),
    researched_at                = COALESCE((p_fields->>'researched_at')::timestamptz,        l.researched_at),

    -- Scoring (integer, text, jsonb)
    lead_score                   = COALESCE((p_fields->>'lead_score')::integer,               l.lead_score),
    priority_level               = COALESCE(NULLIF(p_fields->>'priority_level', ''),          l.priority_level),
    decision_maker_probability   = COALESCE(NULLIF(p_fields->>'decision_maker_probability', ''), l.decision_maker_probability),
    company_size_estimate        = COALESCE(NULLIF(p_fields->>'company_size_estimate', ''),   l.company_size_estimate),
    scoring_reason               = COALESCE(NULLIF(p_fields->>'scoring_reason', ''),          l.scoring_reason),
    score_components             = COALESCE(p_fields->'score_components',                     l.score_components),

    updated_at                   = now()
  WHERE l.id = p_lead_id
  RETURNING l.* INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'lead not found', 'lead_id', p_lead_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'lead_id', v_row.id, 'lead_status', v_row.lead_status);
END;
$fn$;

-- ---- VERIFY ----
-- Expect all five to be true. Before this migration every one was false,
-- and the function reported success while discarding the values.
SELECT
  pg_get_functiondef(oid) LIKE '%research_summary%'     AS writes_research_summary,
  pg_get_functiondef(oid) LIKE '%likely_business_need%' AS writes_business_need,
  pg_get_functiondef(oid) LIKE '%research_angle%'       AS writes_research_angle,
  pg_get_functiondef(oid) LIKE '%researched_at%'        AS writes_researched_at,
  pg_get_functiondef(oid) LIKE '%score_components%'     AS writes_score_components
FROM pg_proc WHERE proname = 'update_lead';

-- Round-trip on one real tenant lead. Expect ok=true, then a non-null
-- summary, then the value cleared again so no test text is left behind.
SELECT update_lead(
  '4495edac-6e47-424c-be2f-f5379c8b8701'::uuid,
  '{"research_summary":"migration round-trip check"}'::jsonb) AS write_ok;

SELECT research_summary AS should_not_be_null
  FROM leads WHERE id = '4495edac-6e47-424c-be2f-f5379c8b8701';

UPDATE leads SET research_summary = NULL
 WHERE id = '4495edac-6e47-424c-be2f-f5379c8b8701'
   AND research_summary = 'migration round-trip check';
