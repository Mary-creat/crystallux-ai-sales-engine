-- clients holds three different relationships and cannot tell them apart.
--
-- THE PROBLEM
--
-- `clients` is correctly the tenant of record -- it is what scopes leads,
-- entitlement and isolation, and there must not be a second tenant root.
-- But six rows currently describe three different kinds of relationship:
--
--   Blonai Moving Company          a paying CUSTOMER
--   Crystallux Insurance Network   Crystallux's own operation
--   Crystallux Insurance Outreach  Crystallux's own operation
--   Crystallux (liquidation)       Crystallux's own operation
--   Eazer — Merchants              a Crystallux Group VENTURE
--   Eazer — Delivery               the same venture, second ICP
--
-- Nothing distinguishes them, so every count of "clients" counts
-- Crystallux's own operations as customers, and any revenue report built on
-- this table is wrong before it is written. It also makes the platform
-- unreadable to anyone new: five of six rows are not what the table is
-- called.
--
-- THE FIX, AND WHAT IT DELIBERATELY IS NOT
--
-- One column. Not a new table, not a rename of `clients`, not a second
-- tenant root -- the isolation model is sound and must not be disturbed to
-- fix a labelling problem.
--
--   customer  an external party that pays Crystallux for the platform
--   internal  Crystallux's own sales operation running on its own platform
--   venture   a Crystallux Group business using the platform to grow itself
--
-- Eazer is `venture`: operated by Crystallux Group Inc., not a customer,
-- but a real tenant whose leads must stay separate from everyone else's.
--
-- Defaults to 'customer' because that is what the table has always claimed
-- every row was, so nothing silently changes meaning. The rows that are not
-- customers are named explicitly below.

BEGIN;

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS tenant_type text NOT NULL DEFAULT 'customer';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'clients_tenant_type_check'
  ) THEN
    ALTER TABLE clients
      ADD CONSTRAINT clients_tenant_type_check
      CHECK (tenant_type IN ('customer', 'internal', 'venture'));
  END IF;
END $$;

COMMENT ON COLUMN clients.tenant_type IS
  'customer = pays Crystallux. internal = Crystallux''s own sales operation. '
  'venture = a Crystallux Group business (e.g. Eazer). All three are real '
  'tenants and scope leads identically; only the commercial relationship '
  'differs.';

-- Eazer: Crystallux Group Inc.'s own delivery marketplace.
UPDATE clients SET tenant_type = 'venture'
 WHERE client_name LIKE 'Eazer%';

-- Crystallux's own operations. Left as three rows rather than merged --
-- merging tenants would reassign their leads, and lead ownership is not
-- something to change while tidying names.
UPDATE clients SET tenant_type = 'internal'
 WHERE client_name IN ('Crystallux',
                       'Crystallux Insurance Network',
                       'Crystallux Insurance Outreach');

COMMIT;

-- Verify:
--   SELECT tenant_type, count(*), string_agg(client_name, ', ')
--     FROM clients GROUP BY tenant_type ORDER BY tenant_type;
--
-- Expect:
--   customer 1  Blonai Moving Company
--   internal 3  Crystallux, Crystallux Insurance Network, ...Outreach
--   venture  2  Eazer — Merchants, Eazer — Delivery
--
-- Real customer count, for any revenue report:
--   SELECT count(*) FROM clients WHERE tenant_type = 'customer' AND active;
--
-- STILL OPEN, and an owner decision rather than a migration:
--   'Crystallux Insurance Network' and 'Crystallux Insurance Outreach' are
--   not distinguishable by name, and 'Crystallux' with industry
--   'liquidation' names nothing at all. Renaming is safe -- no code matches
--   on client_name -- but only the owner knows what each one is for.
