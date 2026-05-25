-- Self-provision Mary's access to portal.crystallux.org
-- Auto-detects which email is registered in auth_users (info@crystallux.org
-- vs adesholaakintunde@gmail.com vs other variants).
-- Idempotent: safe to re-run.

BEGIN;

-- 1. Ensure Crystallux's own MGA carrier row exists
INSERT INTO insurance_carriers (carrier_name, carrier_type, vertical_id, active)
SELECT 'Crystallux Insurance Network', 'mga_wholesaler', 'insurance', true
WHERE NOT EXISTS (
  SELECT 1 FROM insurance_carriers WHERE carrier_name = 'Crystallux Insurance Network'
);

-- 2. Resolve Mary's actual auth_users row, then provision account + user link
DO $$
DECLARE
  v_user_id    uuid;
  v_user_email text;
  v_carrier_id uuid;
  v_account_id uuid;
BEGIN
  -- Find Mary's user row by trying the most-likely emails in priority order
  SELECT id, email INTO v_user_id, v_user_email
  FROM auth_users
  WHERE email IN (
    'info@crystallux.org',
    'adesholaakintunde@gmail.com',
    'mary@crystallux.org',
    'admin@crystallux.org',
    'mary.akintunde@crystallux.org'
  )
  ORDER BY CASE email
    WHEN 'info@crystallux.org'         THEN 1
    WHEN 'adesholaakintunde@gmail.com' THEN 2
    WHEN 'mary@crystallux.org'         THEN 3
    WHEN 'admin@crystallux.org'        THEN 4
    ELSE 5
  END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No auth_users row matched. Run this to find your email: SELECT email, user_role FROM auth_users ORDER BY created_at DESC LIMIT 20;';
  END IF;

  RAISE NOTICE 'Provisioning insurer access for auth_users.email = %', v_user_email;

  -- Get the carrier id
  SELECT id INTO v_carrier_id
  FROM insurance_carriers
  WHERE carrier_name = 'Crystallux Insurance Network'
  LIMIT 1;

  -- Find or create insurer_account for this email + carrier
  SELECT id INTO v_account_id
  FROM insurer_accounts
  WHERE contact_email = v_user_email AND carrier_id = v_carrier_id
  LIMIT 1;

  IF v_account_id IS NULL THEN
    INSERT INTO insurer_accounts (carrier_id, company_name, contact_email, account_type)
    VALUES (v_carrier_id, 'Crystallux Insurance Network', v_user_email, 'partner')
    RETURNING id INTO v_account_id;
  END IF;

  -- Grant Mary the user link (idempotent via unique constraint)
  INSERT INTO insurer_users (insurer_account_id, user_id, role_at_insurer, is_active)
  VALUES (v_account_id, v_user_id, 'executive', true)
  ON CONFLICT (insurer_account_id, user_id) DO UPDATE
  SET is_active = true, role_at_insurer = 'executive';
END $$;

COMMIT;

-- 3. Verify — should return one row showing the email that was provisioned
SELECT
  iu.role_at_insurer,
  iu.is_active   AS user_active,
  ia.account_status,
  ia.contact_email,
  au.email       AS auth_email,
  ic.carrier_name
FROM insurer_users iu
JOIN insurer_accounts ia  ON iu.insurer_account_id = ia.id
JOIN auth_users au        ON iu.user_id = au.id
JOIN insurance_carriers ic ON ia.carrier_id = ic.id
WHERE ic.carrier_name = 'Crystallux Insurance Network';
