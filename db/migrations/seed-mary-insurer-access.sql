-- Self-provision Mary's access to portal.crystallux.org
-- Idempotent: safe to re-run; cleans up partial state from previous failed runs.
-- Apply: psql "$DATABASE_URL" -f db/migrations/seed-mary-insurer-access.sql

BEGIN;

-- 1. Ensure Crystallux's own MGA carrier row exists
INSERT INTO insurance_carriers (carrier_name, carrier_type, vertical_id, active)
SELECT 'Crystallux Insurance Network', 'mga_wholesaler', 'insurance', true
WHERE NOT EXISTS (
  SELECT 1 FROM insurance_carriers WHERE carrier_name = 'Crystallux Insurance Network'
);

-- 2. Insert insurer_account linked to that carrier (only if Mary has no clean account row yet)
INSERT INTO insurer_accounts (carrier_id, company_name, contact_email, account_type)
SELECT
  (SELECT id FROM insurance_carriers WHERE carrier_name = 'Crystallux Insurance Network'),
  'Crystallux Insurance Network',
  'adesholaakintunde@gmail.com',
  'partner'
WHERE NOT EXISTS (
  SELECT 1 FROM insurer_accounts
  WHERE contact_email = 'adesholaakintunde@gmail.com'
    AND carrier_id IS NOT NULL
);

-- 3. Grant Mary the user link
INSERT INTO insurer_users (insurer_account_id, user_id, role_at_insurer, is_active)
SELECT
  (SELECT id FROM insurer_accounts
   WHERE contact_email = 'adesholaakintunde@gmail.com'
     AND carrier_id IS NOT NULL
   LIMIT 1),
  (SELECT id FROM auth_users WHERE email = 'adesholaakintunde@gmail.com'),
  'executive',
  true
WHERE NOT EXISTS (
  SELECT 1 FROM insurer_users
  WHERE user_id = (SELECT id FROM auth_users WHERE email = 'adesholaakintunde@gmail.com')
);

COMMIT;

-- 4. Verify — should return one row with role_at_insurer='executive', user_active=t
SELECT
  iu.role_at_insurer,
  iu.is_active AS user_active,
  ia.account_status,
  ia.company_name,
  ic.carrier_name
FROM insurer_users iu
JOIN insurer_accounts ia ON iu.insurer_account_id = ia.id
JOIN insurance_carriers ic ON ia.carrier_id = ic.id
WHERE iu.user_id = (SELECT id FROM auth_users WHERE email = 'adesholaakintunde@gmail.com');
