-- Crystallux — reconcile commerce tenancy with the established `clients` model
-- ============================================================================
-- Apply AFTER commerce-phase1-auth-lifecycle.sql. Idempotent.
--
-- WHY THIS EXISTS
-- commerce-phase1-inventory-orders.sql introduced commerce_tenants as the root
-- of the commerce hierarchy. That was a duplicate: `clients` is already this
-- platform's tenant table, referenced by client_id on roughly 27 tables across
-- the sales engine, dashboards and billing. Two tenant roots means two answers
-- to "who owns this row", and they drift.
--
-- WHAT THIS DOES -- AND DELIBERATELY DOES NOT DO
-- It does NOT rip commerce_tenants out. Every commerce function references it,
-- and rewriting eight functions to chase a naming preference is risk without
-- return. Instead commerce_tenants becomes a commerce-specific EXTENSION of a
-- client: identity lives in `clients`, and commerce_tenants carries only the
-- commerce profile hanging off it.
--
-- So there is one tenant of record, and the Stage-3 seller model has somewhere
-- real to attach -- including clients.stripe_account_id, which is what Stripe
-- Connect needs when outside warehouses start selling through the platform.
--
-- Safe to run now precisely because the commerce tables are still empty. The
-- same change after a pallet is loaded would need a data migration.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Link commerce_tenants to the tenant of record
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE commerce_tenants
  ADD COLUMN IF NOT EXISTS client_id uuid REFERENCES clients(id) ON DELETE RESTRICT;

-- One commerce profile per client. Without this the "extension" claim is only
-- a convention, and conventions do not survive contact with a busy quarter.
CREATE UNIQUE INDEX IF NOT EXISTS commerce_tenants_client_uniq
  ON commerce_tenants (client_id) WHERE client_id IS NOT NULL;

COMMENT ON TABLE commerce_tenants IS
  'Commerce profile for a client. `clients` is the tenant of record for the '
  'whole platform -- do not treat this as a second tenant root. One row per '
  'selling entity; client_id is the identity.';
COMMENT ON COLUMN commerce_tenants.client_id IS
  'The owning client. Null only for the bootstrap Crystallux row on databases '
  'where no matching client exists yet.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Make sure Crystallux exists as a client, then attach the commerce tenant
-- ─────────────────────────────────────────────────────────────────────────────

-- industry is NOT NULL on clients, so it has to be supplied.
INSERT INTO clients (client_name, industry, active, notes)
SELECT 'Crystallux', 'liquidation', true,
       'Crystallux selling its own liquidation inventory. Tenant of record for '
       'the commerce layer.'
WHERE NOT EXISTS (SELECT 1 FROM clients WHERE client_name = 'Crystallux');

UPDATE commerce_tenants ct
   SET client_id = c.id
  FROM clients c
 WHERE ct.name = 'Crystallux'
   AND c.client_name = 'Crystallux'
   AND ct.client_id IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Resolve a commerce tenant from a client, and vice versa
--    Stage 3 onboards a warehouse as a client; this is how it acquires the
--    commerce hierarchy without anyone hand-inserting rows.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION commerce_tenant_for_client(p_client_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tenant uuid; v_name text;
BEGIN
  SELECT id INTO v_tenant FROM commerce_tenants WHERE client_id = p_client_id;
  IF v_tenant IS NOT NULL THEN RETURN v_tenant; END IF;

  SELECT client_name INTO v_name FROM clients WHERE id = p_client_id;
  IF v_name IS NULL THEN RETURN NULL; END IF;

  -- Name collisions are possible across clients, so disambiguate rather than
  -- fail on the unique constraint.
  INSERT INTO commerce_tenants (name, client_id)
  VALUES (v_name || ' (' || left(p_client_id::text, 8) || ')', p_client_id)
  ON CONFLICT (name) DO UPDATE SET client_id = EXCLUDED.client_id
  RETURNING id INTO v_tenant;

  INSERT INTO commerce_sellers (tenant_id, name)
  VALUES (v_tenant, v_name)
  ON CONFLICT (tenant_id, name) DO NOTHING;

  INSERT INTO commerce_warehouses (tenant_id, name)
  VALUES (v_tenant, v_name || ' Main')
  ON CONFLICT (tenant_id, name) DO NOTHING;

  RETURN v_tenant;
END $$;

-- Read model for the admin UI: one row per selling entity, with the client
-- identity attached. Stage 3 lists sellers from here.
CREATE OR REPLACE VIEW commerce_tenant_directory AS
  SELECT ct.id            AS commerce_tenant_id,
         ct.name          AS commerce_tenant_name,
         c.id             AS client_id,
         c.client_name,
         c.active         AS client_active,
         c.stripe_account_id,
         (SELECT count(*) FROM commerce_warehouses w WHERE w.tenant_id = ct.id) AS warehouses,
         (SELECT count(*) FROM products p            WHERE p.tenant_id = ct.id) AS products
  FROM commerce_tenants ct
  LEFT JOIN clients c ON c.id = ct.client_id;

COMMIT;

-- Verify:
-- SELECT * FROM commerce_tenant_directory;
--   -> one row, commerce_tenant_name 'Crystallux', client_id populated
-- SELECT commerce_tenant_for_client((SELECT id FROM clients WHERE client_name='Crystallux'));
--   -> the existing tenant id, not a new one
