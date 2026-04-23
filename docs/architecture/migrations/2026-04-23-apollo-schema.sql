-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX APOLLO ENRICHMENT — SCHEMA SCAFFOLDING (Part B.5)
-- File: docs/architecture/migrations/2026-04-23-apollo-schema.sql
--
-- Adds the schema surface the Apollo enrichment workflow will write
-- into. Schema-only — no live Apollo API calls are wired yet. The
-- corresponding workflow (workflows/clx-apollo-enrichment-v1.json)
-- ships with its Schedule Trigger DEACTIVATED and a placeholder
-- credential reference; Mary activates it after adding APOLLO_API_KEY
-- and creating the n8n Apollo HTTP Header Auth credential.
--
-- Idempotent — safe to re-run. All column adds use IF NOT EXISTS.
-- All tables use CREATE TABLE IF NOT EXISTS.
-- All RLS policies use DROP ... IF EXISTS / CREATE.
--
-- Runs AFTER 2026-04-22-scale-sprint-v1.sql (does not modify it).
-- Rollback SQL at the bottom (commented).
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. APOLLO-VERIFIED FIELDS ON leads
-- ─────────────────────────────────────────────────────────────────
-- Scraped values live in the original columns (email, full_name,
-- job_title, city). Apollo-verified values live alongside them in
-- *_verified columns so we can compare and grade source quality
-- without destructive overwrites.

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS apollo_person_id     text,
  ADD COLUMN IF NOT EXISTS apollo_org_id        text,
  ADD COLUMN IF NOT EXISTS verified_email       text,
  ADD COLUMN IF NOT EXISTS full_name_verified   text,
  ADD COLUMN IF NOT EXISTS job_title_verified   text,
  ADD COLUMN IF NOT EXISTS linkedin_url         text,
  ADD COLUMN IF NOT EXISTS direct_phone         text,
  ADD COLUMN IF NOT EXISTS mobile_phone         text,
  ADD COLUMN IF NOT EXISTS company_size         integer,
  ADD COLUMN IF NOT EXISTS company_revenue      text,
  ADD COLUMN IF NOT EXISTS tech_stack           jsonb,
  ADD COLUMN IF NOT EXISTS industry_verified    text,
  ADD COLUMN IF NOT EXISTS location_verified    text,
  ADD COLUMN IF NOT EXISTS apollo_enriched_at   timestamptz,
  ADD COLUMN IF NOT EXISTS email_source         text DEFAULT 'scraped';

-- Lookup index for idempotent upserts / dedupe against Apollo IDs.
CREATE INDEX IF NOT EXISTS idx_leads_apollo_person_id
  ON leads(apollo_person_id)
  WHERE apollo_person_id IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────
-- 2. APOLLO PLAN TIER ON clients
-- ─────────────────────────────────────────────────────────────────
-- Per-client Apollo plan so we can later enforce per-client monthly
-- quotas and bill upgraded plans. 'basic' = shared pool default.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS apollo_plan text DEFAULT 'basic';


-- ─────────────────────────────────────────────────────────────────
-- 3. APOLLO CREDITS LOG
-- ─────────────────────────────────────────────────────────────────
-- One row per Apollo API call. Drives monthly quota guard, cost
-- attribution, and future per-client billing.

CREATE TABLE IF NOT EXISTS apollo_credits_log (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id       uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id     uuid REFERENCES clients(id) ON DELETE SET NULL,
  api_endpoint  text,
  credits_used  integer NOT NULL DEFAULT 1,
  cost_usd      numeric(10,4),
  called_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_apollo_credits_log_called_at
  ON apollo_credits_log(called_at);

CREATE INDEX IF NOT EXISTS idx_apollo_credits_log_client
  ON apollo_credits_log(client_id, called_at);

ALTER TABLE apollo_credits_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS apollo_credits_log_service_role_all ON apollo_credits_log;
CREATE POLICY apollo_credits_log_service_role_all ON apollo_credits_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 4. MONTHLY CREDIT-USAGE RPC
-- ─────────────────────────────────────────────────────────────────
-- Returns integer count of credits used in the current calendar month.
-- If p_client_id is NULL, returns the global (shared pool) count.
-- Workflow calls this pre-flight to gate against the monthly cap.

CREATE OR REPLACE FUNCTION get_monthly_apollo_credits_used(
  p_client_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_used integer;
BEGIN
  SELECT COALESCE(SUM(credits_used), 0) INTO v_used
  FROM apollo_credits_log
  WHERE called_at >= date_trunc('month', now())
    AND called_at <  date_trunc('month', now()) + interval '1 month'
    AND (p_client_id IS NULL OR client_id = p_client_id);

  RETURN v_used;
END;
$$;

GRANT EXECUTE ON FUNCTION get_monthly_apollo_credits_used(uuid) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 5. NICHE OVERLAY — APOLLO TITLE KEYWORDS
-- ─────────────────────────────────────────────────────────────────
-- Per-niche list of job titles that mark a person as the primary
-- decision-maker in an org. Apollo People Search returns multiple
-- contacts per org; we pick the first one whose title matches any
-- of these keywords.

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS apollo_title_keywords jsonb DEFAULT '[]'::jsonb;

-- Seed the insurance_broker overlay with the decision-maker titles
-- that matter for brokerage outreach.
UPDATE niche_overlays
SET apollo_title_keywords = '[
  "Broker of Record",
  "Principal",
  "Owner",
  "Managing Partner",
  "President",
  "Founder"
]'::jsonb
WHERE niche_name = 'insurance_broker'
  AND (apollo_title_keywords IS NULL
       OR apollo_title_keywords = '[]'::jsonb);


-- ─────────────────────────────────────────────────────────────────
-- 6. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 15
SELECT 'leads apollo-* columns' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'apollo_person_id','apollo_org_id','verified_email',
    'full_name_verified','job_title_verified','linkedin_url',
    'direct_phone','mobile_phone','company_size','company_revenue',
    'tech_stack','industry_verified','location_verified',
    'apollo_enriched_at','email_source'
  );

-- Expect 1
SELECT 'clients.apollo_plan' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'clients' AND column_name = 'apollo_plan';

-- Expect 1
SELECT 'apollo_credits_log table' AS check_name,
       COUNT(*) AS present
FROM information_schema.tables
WHERE table_name = 'apollo_credits_log';

-- Expect 1
SELECT 'get_monthly_apollo_credits_used RPC' AS check_name,
       COUNT(*) AS present
FROM information_schema.routines
WHERE routine_name = 'get_monthly_apollo_credits_used';

-- Expect 1 row with non-empty jsonb array
SELECT niche_name,
       jsonb_array_length(apollo_title_keywords) AS title_keyword_count
FROM niche_overlays
WHERE niche_name = 'insurance_broker';


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo — test on staging first)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 5. Niche overlay apollo_title_keywords
-- ALTER TABLE niche_overlays DROP COLUMN IF EXISTS apollo_title_keywords;
--
-- -- 4. Monthly credits RPC
-- DROP FUNCTION IF EXISTS get_monthly_apollo_credits_used(uuid);
--
-- -- 3. Apollo credits log
-- DROP TABLE IF EXISTS apollo_credits_log CASCADE;
--
-- -- 2. Clients apollo_plan
-- ALTER TABLE clients DROP COLUMN IF EXISTS apollo_plan;
--
-- -- 1. Leads apollo-* columns
-- DROP INDEX IF EXISTS idx_leads_apollo_person_id;
-- ALTER TABLE leads
--   DROP COLUMN IF EXISTS apollo_person_id,
--   DROP COLUMN IF EXISTS apollo_org_id,
--   DROP COLUMN IF EXISTS verified_email,
--   DROP COLUMN IF EXISTS full_name_verified,
--   DROP COLUMN IF EXISTS job_title_verified,
--   DROP COLUMN IF EXISTS linkedin_url,
--   DROP COLUMN IF EXISTS direct_phone,
--   DROP COLUMN IF EXISTS mobile_phone,
--   DROP COLUMN IF EXISTS company_size,
--   DROP COLUMN IF EXISTS company_revenue,
--   DROP COLUMN IF EXISTS tech_stack,
--   DROP COLUMN IF EXISTS industry_verified,
--   DROP COLUMN IF EXISTS location_verified,
--   DROP COLUMN IF EXISTS apollo_enriched_at,
--   DROP COLUMN IF EXISTS email_source;
