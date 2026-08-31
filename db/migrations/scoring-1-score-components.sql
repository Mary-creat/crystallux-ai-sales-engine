-- ============================================================
-- Explainable scoring — one column for the structured breakdown
--
-- clx-lead-scoring-v2 already produces a human narrative in
-- scoring_reason and that is kept unchanged. What it could not produce
-- was a structured breakdown, because there was nowhere to put one:
-- leads has exactly two jsonb columns and both are taken (tech_stack,
-- channels_attempted). One column is the minimum that works.
--
-- WHAT THE BREAKDOWN HONESTLY CONTAINS, and what it deliberately does
-- not. The final score has two parts and only one of them is arithmetic:
--
--   ai_base_score        Claude's judgement. NOT decomposed into
--                        invented point values -- there are none to
--                        report, and fabricating "+10 ICP fit" would be
--                        false precision.
--   ai_assessment        the qualitative calls that accompany it:
--                        priority_level, decision_maker_probability,
--                        company_size_estimate, marked as judgement.
--   deterministic_bonus  genuinely decomposable, because it is real
--                        arithmetic in the workflow: +10 when
--                        apollo_enriched_at is set, +15 when
--                        job_title_verified matches the decision-maker
--                        keywords, with the evidence for each.
--   clamped_at_100       whether the sum was capped.
--
-- So the breakdown reconciles with the score where arithmetic exists and
-- says "model judgement" where it does not. It can never contradict the
-- number because it never invents one.
--
-- On a failed parse it holds {final_score: null, status: 'not_scored',
-- reason: ...} rather than a zero.
--
-- Idempotent. No existing column altered.
-- ============================================================

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS score_components jsonb;

COMMENT ON COLUMN leads.score_components IS
  'Structured scoring explanation. Separates Claude''s ai_base_score and '
  'qualitative ai_assessment from the deterministic Apollo bonus, which is '
  'decomposed with evidence. Never fabricates point values for the model '
  'judgement. {status: not_scored} when parsing failed.';

-- update_lead uses an explicit column allowlist, so the new field has to be
-- named there or it is silently dropped -- the same trap that made
-- signal_error a no-op.
CREATE OR REPLACE FUNCTION update_lead_score_components(
  p_lead_id uuid,
  p_components jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_n integer;
BEGIN
  IF p_lead_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'lead_id required');
  END IF;
  UPDATE leads SET score_components = p_components, updated_at = now()
   WHERE id = p_lead_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', v_n > 0, 'rows', v_n);
END;
$fn$;

GRANT EXECUTE ON FUNCTION update_lead_score_components(uuid, jsonb) TO service_role;

-- ---- VERIFY ----
SELECT column_name, data_type FROM information_schema.columns
 WHERE table_name = 'leads' AND column_name = 'score_components';

-- Expect 0 until the scorer next runs; this migration populates nothing.
SELECT count(*) AS leads_with_components FROM leads WHERE score_components IS NOT NULL;
