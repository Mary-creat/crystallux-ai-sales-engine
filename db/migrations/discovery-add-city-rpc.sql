-- add_discovery_city — extend discovery coverage without touching a backend.
--
-- WHY
--
-- The MCP gateway has exposed a `scan_city` tool since it was written. Asked
-- to scan a city, it returned:
--
--   "City scan queued. The CLX City Scan Discovery workflow will process
--    <industry> in <city> on next scheduled run."
--
-- and wrote nothing. Nothing was queued, nothing was scheduled, and the
-- caller was told it had worked. Same family as the sender that reported
-- success on a dead key and the signal stage that stamps a status with no
-- signal behind it: a confident answer standing in for an action.
--
-- Now that the query registry is data (scan_query_tracker) rather than a
-- hardcoded object in the workflow, the tool can do the thing it claims.
-- This is the whole implementation: take the search terms a vertical
-- already uses, and repeat them in a new city.
--
-- Deliberately NOT a query generator. It cannot invent search terms, only
-- copy proven ones into new geography. An agent that could compose
-- arbitrary Google Places queries could spend arbitrary money; an agent
-- that can only widen an existing, human-chosen basket cannot.
--
-- Ambiguity fails closed. 'Eazer' matches two verticals, so it refuses and
-- names both rather than guessing which one the caller meant.

BEGIN;

CREATE OR REPLACE FUNCTION add_discovery_city(p_target text, p_city text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_city   text := btrim(coalesce(p_city, ''));
  v_target text := btrim(coalesce(p_target, ''));
  v_types  text[];
  v_type   text;
  v_terms  int;
  v_added  int;
  v_before int;
BEGIN
  IF v_city = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'a city is required');
  END IF;
  IF v_target = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'a vertical or client name is required');
  END IF;

  -- Resolve the caller's words to a product_type. Exact match first, then
  -- client name, so both "eazer_merchant" and "Eazer — Merchants" work.
  SELECT array_agg(DISTINCT t) INTO v_types
    FROM (
      SELECT product_type AS t FROM scan_query_tracker
       WHERE lower(product_type) = lower(v_target)
      UNION
      SELECT product_type AS t FROM clients
       WHERE product_type IS NOT NULL
         AND (lower(client_name) LIKE '%' || lower(v_target) || '%'
              OR lower(product_type) = lower(v_target))
    ) s;

  IF v_types IS NULL OR array_length(v_types, 1) = 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', format('no vertical or client matches %L', v_target));
  END IF;

  IF array_length(v_types, 1) > 1 THEN
    RETURN jsonb_build_object('ok', false,
      'error', format('%L is ambiguous - it matches %s. Name one.',
                      v_target, array_to_string(v_types, ', ')),
      'options', to_jsonb(v_types));
  END IF;

  v_type := v_types[1];

  -- The terms this vertical already searches, stripped of their old city.
  SELECT count(DISTINCT regexp_replace(search_query, ' in .* Canada$', ''))
    INTO v_terms
    FROM scan_query_tracker WHERE product_type = v_type;

  IF v_terms = 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', format('%L has no search terms to copy', v_type));
  END IF;

  SELECT count(*) INTO v_before
    FROM scan_query_tracker WHERE product_type = v_type AND city = v_city;

  INSERT INTO scan_query_tracker
    (search_query, city, industry, product_type,
     paused, total_scans, total_new_leads, consecutive_zero_new)
  SELECT DISTINCT
         regexp_replace(t.search_query, ' in .* Canada$', '')
           || ' in ' || v_city || ' Canada',
         v_city,
         t.industry,
         v_type,
         false, 0, 0, 0
    FROM scan_query_tracker t
   WHERE t.product_type = v_type
     AND NOT EXISTS (
       SELECT 1 FROM scan_query_tracker x
        WHERE x.city = v_city
          AND x.search_query = regexp_replace(t.search_query, ' in .* Canada$', '')
                                 || ' in ' || v_city || ' Canada');

  GET DIAGNOSTICS v_added = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'product_type', v_type,
    'city', v_city,
    'terms_available', v_terms,
    'queries_added', v_added,
    'already_present', v_before,
    'note', CASE WHEN v_added = 0
                 THEN format('%s already covered %L - nothing to add', v_type, v_city)
                 ELSE format('%s queries added for %s in %s. They run on the next discovery pass.',
                             v_added, v_type, v_city) END);
END;
$$;

COMMENT ON FUNCTION add_discovery_city(text, text) IS
  'Copy a vertical''s existing search terms into a new city. Idempotent. '
  'Cannot invent search terms - only widen geography.';

COMMIT;

-- Verify (safe, idempotent - run it twice and the second says 0 added):
--   SELECT add_discovery_city('Eazer - Merchants', 'Oakville');
--   SELECT add_discovery_city('eazer_merchant', 'Oakville');
--   SELECT add_discovery_city('Eazer', 'Oakville');   -- refuses: ambiguous
--   SELECT add_discovery_city('nonsense', 'Oakville');-- refuses: no match
