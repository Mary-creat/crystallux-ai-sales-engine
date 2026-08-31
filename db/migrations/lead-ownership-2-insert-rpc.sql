-- ============================================================
-- Lead ownership, step 2 of 2 — an explicit owner, without losing
-- the auto-match that already exists
--
-- CORRECTION TO AN EARLIER DIAGNOSIS, recorded because it nearly cost
-- something. I first concluded that insert_lead_if_not_exists "cannot
-- assign ownership" because client_id is not in its parameter list,
-- and drafted a replacement. Reading the actual body disproved that:
-- the function already resolves an owner, by matching the lead against
-- active clients on product_type, then industry, preferring the same
-- city, oldest client first.
--
-- The orphans are therefore not a broken function. They are that
-- auto-match correctly finding nothing: there are four clients, and a
-- house-pool prospect in construction or dental matches none of them.
-- The 2,378 unowned leads are working-as-designed, not corrupted.
--
-- The draft replacement would have thrown away the auto-match, changed
-- the return type from jsonb to uuid, and broken every existing caller.
-- This version keeps the body byte-for-byte in behaviour and adds one
-- optional parameter.
--
-- p_client_id, when supplied, OVERRIDES the auto-match. That is what a
-- tenant-scoped discovery job needs: it already knows whose lead this
-- is and should not be guessing. When omitted, behaviour is exactly as
-- before, so nothing needs redeploying.
--
-- Run AFTER lead-ownership-1-provenance.sql.
-- ============================================================

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
  p_client_id    uuid DEFAULT NULL          -- new, last, defaulted: additive
)
RETURNS jsonb                                -- unchanged contract
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_existing_id uuid;
  v_new_id      uuid;
  v_client_id   uuid;
BEGIN
  IF p_company IS NULL OR length(trim(p_company)) = 0 THEN
    RETURN jsonb_build_object(
      'status',  'error',
      'message', 'company is required'
    );
  END IF;

  -- Dedup check (enforced at app layer; the leads_company_unique
  -- constraint is still the last line of defense)
  SELECT id INTO v_existing_id
  FROM leads
  WHERE company = p_company
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status',  'duplicate',
      'id',      v_existing_id,
      'company', p_company
    );
  END IF;

  IF p_client_id IS NOT NULL THEN
    -- An explicit owner wins. A tenant-scoped discovery job already
    -- knows whose lead this is; guessing would be strictly worse.
    v_client_id := p_client_id;
  ELSE
    -- Unchanged auto-match:
    --   Priority 1: exact product_type match AND same city
    --   Priority 2: exact product_type match AND any city
    --   Priority 3: industry ILIKE match (legacy fallback)
    SELECT id INTO v_client_id
    FROM clients
    WHERE active = true
      AND (
           product_type = p_product_type
        OR (p_industry IS NOT NULL AND industry ILIKE '%' || p_industry || '%')
      )
    ORDER BY
      CASE WHEN product_type = p_product_type THEN 0 ELSE 1 END,
      CASE WHEN city = p_city                 THEN 0 ELSE 1 END,
      created_at ASC
    LIMIT 1;
  END IF;

  INSERT INTO leads (
    full_name, email, phone, company, job_title, industry, city,
    source, lead_status, product_type, notes, client_id, lead_pool
  )
  VALUES (
    p_full_name, p_email, p_phone, p_company, p_job_title, p_industry, p_city,
    p_source, p_lead_status, p_product_type, p_notes, v_client_id,
    CASE WHEN v_client_id IS NULL THEN 'house' ELSE 'tenant' END
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'status',         'inserted',
    'id',             v_new_id,
    'company',        p_company,
    'client_id',      v_client_id,
    'client_matched', v_client_id IS NOT NULL,
    'owner_explicit', p_client_id IS NOT NULL,   -- additive, harmless to old readers
    'lead_pool',      CASE WHEN v_client_id IS NULL THEN 'house' ELSE 'tenant' END
  );
END;
$fn$;

COMMENT ON FUNCTION insert_lead_if_not_exists(text,text,text,text,text,text,text,text,text,text,text,uuid) IS
  'Canonical lead insert with dedup. Supplying p_client_id assigns ownership '
  'explicitly and overrides the client auto-match; omitting it preserves the '
  'original auto-match behaviour exactly. Sets lead_pool to match.';

GRANT EXECUTE ON FUNCTION insert_lead_if_not_exists(text,text,text,text,text,text,text,text,text,text,text,uuid) TO service_role;

-- ---- VERIFY ----
-- Expect TWO rows: the original 11-arg version and this 12-arg one.
-- Both return jsonb. Existing callers bind to the 11-arg signature and
-- are completely unaffected.
SELECT pronargs, pg_get_function_result(oid) AS returns
  FROM pg_proc WHERE proname = 'insert_lead_if_not_exists'
 ORDER BY pronargs;

-- Expect house 2378 / tenant 140 — unchanged. This migration inserts nothing.
SELECT lead_pool, count(*) AS leads FROM leads GROUP BY lead_pool ORDER BY lead_pool;
