-- Eazer tenants — merchant recruitment and same-day delivery contracts.
--
-- Eazer is a three-sided marketplace operated by Crystallux Group Inc.
-- (North York, ON): merchants, delivery partners, and users. Only one of
-- those three sides is a discovery problem.
--
-- Google Maps indexes BUSINESSES. It finds shops to onboard, and it finds
-- organisations that already pay someone to move parcels. It cannot find
-- individual drivers or consumers -- those are paid acquisition, and
-- pointing this engine at them would build a pipeline that returns nothing
-- while looking like it works.
--
-- So two tenants, not three, and they are separate tenants rather than one
-- because the pitch is genuinely different:
--
--   Eazer — Merchants   "list your shop on Eazer and we bring you orders"
--   Eazer — Delivery    "we move your parcels same-day, on contract"
--
-- Keeping them apart means each gets its own leads, its own messaging and
-- its own attribution. Merging them would produce one pipeline where half
-- the leads get the wrong offer.
--
-- WHY ONE IS ACTIVE AND ONE IS NOT
--
-- clx-b2c-discovery-v2.1 scans every active client's product_type across
-- five GTA cities. Merchants alone is 15 queries x 5 cities = 75 searches;
-- adding delivery makes it 145. Every business found is then a Claude
-- research call and a Claude scoring call, so the second tenant is seeded
-- dormant and switched on deliberately once the first has proven its yield.
-- That is the dormant-by-default policy applied to spend rather than risk.
--
-- To activate the second tenant later:
--   UPDATE clients SET active = true WHERE client_name = 'Eazer — Delivery';

BEGIN;

-- Merchants: restaurants first, then pharmacy, grocery and local retail.
INSERT INTO clients
  (client_name, industry, product_type, city, active,
   channels_enabled, onboarding_stage, notes)
SELECT
  'Eazer — Merchants',
  'food and retail',
  'eazer_merchant',
  'Toronto GTA',
  true,
  '["email"]'::jsonb,
  'active',
  'Eazer merchant recruitment: restaurants, pharmacies, grocery and local '
  'retail across the GTA, to list on Eazer Shops. Operated by Crystallux '
  'Group Inc. Discovery queries live in clx-b2c-discovery-v2.1 under '
  'product_type eazer_merchant.'
WHERE NOT EXISTS (
  SELECT 1 FROM clients WHERE client_name = 'Eazer — Merchants');

-- Same-day delivery contracts. Seeded dormant on purpose -- see above.
INSERT INTO clients
  (client_name, industry, product_type, city, active,
   channels_enabled, onboarding_stage, notes)
SELECT
  'Eazer — Delivery',
  'same-day delivery',
  'eazer_delivery',
  'Toronto GTA',
  false,
  '["email"]'::jsonb,
  'active',
  'Eazer B2B same-day delivery contracts: businesses that already move '
  'parcels locally -- auto parts, medical supply, dental labs, print, '
  'florists, wholesale. Seeded inactive; set active = true to begin '
  'discovery. Queries live under product_type eazer_delivery.'
WHERE NOT EXISTS (
  SELECT 1 FROM clients WHERE client_name = 'Eazer — Delivery');

COMMIT;

-- Verify:
--   SELECT client_name, product_type, city, active, industry
--     FROM clients WHERE client_name LIKE 'Eazer%';
--
-- Expect two rows: Merchants active = true, Delivery active = false.
