-- ============================================================
-- Lead ownership, step 1 of 2 — make provenance explicit
--
-- 2,378 of 2,518 leads have client_id = NULL. That is not corruption
-- and it is not a customer's data gone missing: every one of them is a
-- business in a vertical Crystallux SELLS TO -- construction 416,
-- dental 363, insurance_broker 287, beauty 284, cleaning 187, moving
-- 180, real estate 100 -- discovered by city-scan for Crystallux's own
-- outbound. They are the house prospect pool.
--
-- The 140 owned leads belong to the two test tenants.
--
-- So nothing is reassigned here. The pool is simply named, which turns
-- an ambiguous NULL into a fact you can query and a rule you can
-- enforce.
--
-- Idempotent. No data is moved between tenants. No row is deleted.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Name the two pools
--
-- 'house'  = Crystallux's own prospects. client_id is legitimately NULL.
-- 'tenant' = belongs to a paying client. client_id is mandatory.
--
-- Defaulting to 'house' is correct for every existing row: the 140
-- owned ones are corrected immediately below, and the rest genuinely
-- are house prospects.
-- ------------------------------------------------------------

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS lead_pool text NOT NULL DEFAULT 'house';

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'leads_lead_pool_check') THEN
    ALTER TABLE leads
      ADD CONSTRAINT leads_lead_pool_check CHECK (lead_pool IN ('house', 'tenant'));
  END IF;
END
$do$;

COMMENT ON COLUMN leads.lead_pool IS
  'house = Crystallux''s own prospect pool, client_id legitimately NULL. '
  'tenant = owned by a paying client, client_id mandatory and enforced by trigger.';

-- Any lead that already has an owner is, by definition, a tenant lead.
UPDATE leads SET lead_pool = 'tenant'
 WHERE client_id IS NOT NULL AND lead_pool <> 'tenant';

-- ------------------------------------------------------------
-- 2. Fail closed
--
-- A lead can no longer claim tenant origin without an owner. The check
-- is on the table rather than in the eleven workflows that insert
-- leads, because one of those -- clx-lead-import -- is a protected
-- production workflow, and a guard that skips the protected path is
-- not a guard. This covers every writer, including any added later.
--
-- Ownership also implies the pool, so a caller that sets client_id
-- correctly cannot then mislabel the row.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION leads_enforce_ownership()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NEW.client_id IS NOT NULL THEN
    NEW.lead_pool := 'tenant';
  ELSIF NEW.lead_pool = 'tenant' THEN
    RAISE EXCEPTION
      'lead_pool=tenant requires client_id (lead company=%, source=%)',
      COALESCE(NEW.company, '?'), COALESCE(NEW.source, '?')
      USING HINT = 'Tenant discovery must resolve an owning client before insert; '
                   'use lead_pool=house for the Crystallux prospect pool.';
  END IF;
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS leads_enforce_ownership_trg ON leads;
CREATE TRIGGER leads_enforce_ownership_trg
  BEFORE INSERT OR UPDATE OF client_id, lead_pool ON leads
  FOR EACH ROW EXECUTE FUNCTION leads_enforce_ownership();

CREATE INDEX IF NOT EXISTS leads_pool_client_idx ON leads (lead_pool, client_id);

-- ---- VERIFY ----
-- Expect: house 2378 / tenant 140, and no tenant row without a client_id.
SELECT lead_pool,
       count(*)                                  AS leads,
       count(*) FILTER (WHERE client_id IS NULL) AS without_owner
  FROM leads
 GROUP BY lead_pool
 ORDER BY lead_pool;

-- Expect 1 row: the trigger is installed.
SELECT tgname FROM pg_trigger WHERE tgname = 'leads_enforce_ownership_trg';
