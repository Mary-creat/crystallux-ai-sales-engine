-- Eazer tenants and their discovery queries.
--
-- Eazer is a three-sided marketplace operated by Crystallux Group Inc.
-- (North York, ON): merchants, delivery partners, and users. Only one of
-- those three is a discovery problem.
--
-- Google Maps indexes BUSINESSES. It finds shops to onboard, and it finds
-- organisations that already pay someone to move parcels. It cannot find
-- individual drivers or consumers -- those are paid acquisition, and
-- pointing this engine at them would build a pipeline that returns nothing
-- while looking like it works.
--
-- Two tenants, not three, and separate because the pitch differs:
--   Eazer — Merchants   "list your shop on Eazer and we bring you orders"
--   Eazer — Delivery    "we move your parcels same-day, on contract"
--
-- WHY THE QUERIES ARE HERE AND NOT IN THE WORKFLOW
--
-- They used to be a hardcoded object inside clx-b2c-discovery-v2.1, so
-- adding a city meant editing JavaScript and redeploying. scan_query_tracker
-- already held every (query, city, industry, product_type) the engine had
-- run, and it is now read as the registry rather than as a memo. Adding a
-- search is an INSERT; stopping one is an UPDATE or a DELETE. No deploy.
--
-- WHY ONE TENANT IS ACTIVE AND ONE IS NOT
--
-- Discovery scans every active client's product_type. Merchants alone is
-- 15 queries x 5 cities = 75 searches; both is 145. Every business found
-- costs a Claude research call and a Claude scoring call, so the second
-- tenant is seeded dormant and switched on once the first has shown its
-- yield -- dormant-by-default applied to spend rather than to risk.
--
--   UPDATE clients SET active = true WHERE client_name = 'Eazer — Delivery';
--
-- Its queries are seeded anyway: an inactive client's product_type is never
-- added to the scan set, so the rows sit inert until the client is switched
-- on. Nothing extra to remember later.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The tenants
-- ---------------------------------------------------------------------------

INSERT INTO clients
  (client_name, industry, product_type, city, active,
   channels_enabled, onboarding_stage, notes)
SELECT
  'Eazer — Merchants', 'food and retail', 'eazer_merchant', 'Toronto GTA',
  true, '["email"]'::jsonb, 'active',
  'Eazer merchant recruitment: restaurants, pharmacies, grocery and local '
  'retail across the GTA, to list on Eazer Shops. Operated by Crystallux '
  'Group Inc. Queries live in scan_query_tracker, product_type eazer_merchant.'
WHERE NOT EXISTS (SELECT 1 FROM clients WHERE client_name = 'Eazer — Merchants');

INSERT INTO clients
  (client_name, industry, product_type, city, active,
   channels_enabled, onboarding_stage, notes)
SELECT
  'Eazer — Delivery', 'same-day delivery', 'eazer_delivery', 'Toronto GTA',
  false, '["email"]'::jsonb, 'active',
  'Eazer B2B same-day delivery contracts: businesses that already move '
  'parcels locally. Seeded inactive; set active = true to begin discovery. '
  'Queries live in scan_query_tracker, product_type eazer_delivery.'
WHERE NOT EXISTS (SELECT 1 FROM clients WHERE client_name = 'Eazer — Delivery');

-- ---------------------------------------------------------------------------
-- 2. The discovery queries
--
-- search_query must read '<term> in <City> Canada' -- that exact string is
-- the dedupe key the tracker has always used, and a different shape would
-- re-scan everything as if it were new.
-- ---------------------------------------------------------------------------

-- Merchants: restaurants first, then the rest of the local retail basket.
INSERT INTO scan_query_tracker
  (search_query, city, industry, product_type,
   paused, total_scans, total_new_leads, consecutive_zero_new)
SELECT q.term || ' in ' || c.city || ' Canada', c.city,
       'food and retail', 'eazer_merchant', false, 0, 0, 0
FROM (VALUES
  ('restaurant'), ('takeout restaurant'), ('pizza restaurant'),
  ('halal restaurant'), ('caribbean restaurant'), ('african restaurant'),
  ('breakfast restaurant'), ('sandwich shop'), ('bakery'),
  ('pharmacy'), ('grocery store'), ('convenience store'),
  ('african grocery store'), ('butcher shop'), ('electronics store')
) AS q(term)
CROSS JOIN (VALUES
  ('Toronto'), ('Mississauga'), ('Brampton'), ('Vaughan'), ('Markham')
) AS c(city)
WHERE NOT EXISTS (
  SELECT 1 FROM scan_query_tracker t
   WHERE t.search_query = q.term || ' in ' || c.city || ' Canada'
     AND t.city = c.city);

-- Delivery: businesses whose own customers already expect same-day, so the
-- cost line exists and the pitch is displacement rather than education.
INSERT INTO scan_query_tracker
  (search_query, city, industry, product_type,
   paused, total_scans, total_new_leads, consecutive_zero_new)
SELECT q.term || ' in ' || c.city || ' Canada', c.city,
       'same-day delivery', 'eazer_delivery', false, 0, 0, 0
FROM (VALUES
  ('auto parts store'), ('medical supply store'), ('dental laboratory'),
  ('printing company'), ('sign shop'), ('florist'),
  ('wholesale distributor'), ('restaurant supply store'),
  ('appliance store'), ('furniture store'), ('building supply store'),
  ('commercial bakery'), ('office supply store'), ('courier service')
) AS q(term)
CROSS JOIN (VALUES
  ('Toronto'), ('Mississauga'), ('Brampton'), ('Vaughan'), ('Markham')
) AS c(city)
WHERE NOT EXISTS (
  SELECT 1 FROM scan_query_tracker t
   WHERE t.search_query = q.term || ' in ' || c.city || ' Canada'
     AND t.city = c.city);

COMMIT;

-- Verify:
--   SELECT client_name, product_type, active FROM clients
--    WHERE client_name LIKE 'Eazer%';
--   -- Merchants true, Delivery false
--
--   SELECT product_type, count(*) FROM scan_query_tracker
--    WHERE product_type LIKE 'eazer%' GROUP BY 1;
--   -- eazer_merchant 75, eazer_delivery 70
--
-- Adding a city later is one statement, no deploy:
--   INSERT INTO scan_query_tracker
--     (search_query, city, industry, product_type, paused,
--      total_scans, total_new_leads, consecutive_zero_new)
--   SELECT DISTINCT
--     regexp_replace(search_query, ' in .* Canada$', '') || ' in Oshawa Canada',
--     'Oshawa', industry, product_type, false, 0, 0, 0
--     FROM scan_query_tracker WHERE product_type = 'eazer_merchant';
