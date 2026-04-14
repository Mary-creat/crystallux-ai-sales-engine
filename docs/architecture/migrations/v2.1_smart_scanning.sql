-- ============================================================
-- CLX v2.1 — Smart Scanning + Multi-Tenant + Auto Client Assignment
-- ============================================================
-- Run order: this file is idempotent. Safe to re-run.
--
-- What it does:
--   1. upsert_scan_tracker(...)          — per-query telemetry + auto-pause
--   2. insert_lead_if_not_exists(...)    — now auto-assigns client_id
--   3. Indexes for the hot paths used by the Build B2C Scan List node
--   4. service_role RLS policies on scan_query_tracker (in line with
--      docs/setup/supabase-rls-setup.md — n8n uses service_role, anon blocked)
-- ============================================================


-- ------------------------------------------------------------
-- 1. upsert_scan_tracker
-- ------------------------------------------------------------
-- Called once per (scan item outcome) by the n8n workflow.
-- Aggregates into scan_query_tracker and auto-pauses queries that
-- return zero new leads three times in a row.
--
-- Semantics:
--   p_new_leads > 0  → reset consecutive_zero_new to 0, unpause
--   p_new_leads = 0  → increment consecutive_zero_new;
--                      if it reaches 3, flip paused = true
--
-- Note on granularity: the workflow calls this per-item (once per
-- business processed, plus once per zero-result query). A query that
-- returns 10 duplicates therefore increments consecutive_zero_new by
-- 10, which pauses it quickly — this is intentional cost-optimization
-- behavior. Queries that find even one new lead reset immediately.

CREATE OR REPLACE FUNCTION upsert_scan_tracker(
  p_search_query text,
  p_city         text,
  p_industry     text,
  p_product_type text,
  p_new_leads    integer DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO scan_query_tracker (
    search_query,
    city,
    industry,
    product_type,
    last_scanned_at,
    total_scans,
    total_new_leads,
    consecutive_zero_new,
    paused
  )
  VALUES (
    p_search_query,
    p_city,
    p_industry,
    p_product_type,
    now(),
    1,
    COALESCE(p_new_leads, 0),
    CASE WHEN COALESCE(p_new_leads, 0) = 0 THEN 1 ELSE 0 END,
    false
  )
  ON CONFLICT (search_query, city) DO UPDATE SET
    last_scanned_at      = now(),
    total_scans          = scan_query_tracker.total_scans + 1,
    total_new_leads      = scan_query_tracker.total_new_leads + COALESCE(p_new_leads, 0),
    consecutive_zero_new = CASE
                              WHEN COALESCE(p_new_leads, 0) > 0 THEN 0
                              ELSE scan_query_tracker.consecutive_zero_new + 1
                           END,
    paused               = CASE
                              WHEN COALESCE(p_new_leads, 0) > 0 THEN false
                              WHEN scan_query_tracker.consecutive_zero_new + 1 >= 3 THEN true
                              ELSE scan_query_tracker.paused
                           END,
    industry             = COALESCE(scan_query_tracker.industry,     p_industry),
    product_type         = COALESCE(scan_query_tracker.product_type, p_product_type);
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_scan_tracker(text, text, text, text, integer)
  TO service_role;


-- ------------------------------------------------------------
-- 2. insert_lead_if_not_exists — with client auto-assignment
-- ------------------------------------------------------------
-- Matches new leads to an active client by product_type (primary)
-- or industry (fallback). Prefers clients whose city matches the
-- lead's city, then falls back to oldest-created client in the
-- matching product/industry. Returns client_matched so the caller
-- can tell whether a lead went to the unassigned pool.

DROP FUNCTION IF EXISTS insert_lead_if_not_exists(
  text, text, text, text, text, text, text, text, text, text, text
);

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
  p_notes        text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- Auto-match client:
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

  INSERT INTO leads (
    full_name, email, phone, company, job_title, industry, city,
    source, lead_status, product_type, notes, client_id
  )
  VALUES (
    p_full_name, p_email, p_phone, p_company, p_job_title, p_industry, p_city,
    p_source, p_lead_status, p_product_type, p_notes, v_client_id
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'status',         'inserted',
    'id',             v_new_id,
    'company',        p_company,
    'client_id',      v_client_id,
    'client_matched', v_client_id IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION insert_lead_if_not_exists(
  text, text, text, text, text, text, text, text, text, text, text
) TO service_role;


-- ------------------------------------------------------------
-- 3. Indexes (idempotent)
-- ------------------------------------------------------------
-- scan_query_tracker already has UNIQUE(search_query, city) which
-- covers lookups by (query, city). Add a partial index for the
-- "active queries" hot path used by Fetch Scan Tracker in n8n.

CREATE INDEX IF NOT EXISTS idx_scan_query_tracker_active
  ON scan_query_tracker (last_scanned_at DESC)
  WHERE paused = false;

CREATE INDEX IF NOT EXISTS idx_scan_query_tracker_paused_retry
  ON scan_query_tracker (paused, last_scanned_at)
  WHERE paused = true;

-- clients: fast lookup of active clients by product_type/industry/city
-- for the auto-assignment path in insert_lead_if_not_exists.
CREATE INDEX IF NOT EXISTS idx_clients_active_product_type
  ON clients (active, product_type)
  WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_clients_active_industry
  ON clients (active, industry)
  WHERE active = true;


-- ------------------------------------------------------------
-- 4. RLS — align with docs/setup/supabase-rls-setup.md
-- ------------------------------------------------------------
-- n8n uses the service_role key; anon must be blocked.

ALTER TABLE scan_query_tracker ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access on scan_query_tracker" ON scan_query_tracker;
CREATE POLICY "Service role full access on scan_query_tracker"
  ON scan_query_tracker
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
