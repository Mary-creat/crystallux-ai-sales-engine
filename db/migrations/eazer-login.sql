-- Eazer's login. Admin-provisioned, not a Stripe purchase.
--
-- Eazer is tenant_type = 'venture' -- a Crystallux Group business, not a
-- customer. Routing it through Stripe would create a customer record and a
-- payment obligation for something Crystallux already owns. Real customers
-- take the Stripe path (clx_provision_paid_checkout); a venture takes this one.
--
-- THE PASSWORD IS DELIBERATELY UNKNOWN.
--
-- password_hash below is bcrypt cost-12 over 48 random bytes that were
-- generated, hashed and discarded in the same breath. Nobody has the
-- plaintext, including whoever wrote this file, so no one can sign in with
-- it. The column is NOT NULL-shaped in practice and the login path expects a
-- hash, so it needs a value; it does not need to be a usable one.
--
-- The account holder sets their own password through the existing reset
-- flow at crystallux.org/forgot-password, which looks the user up by email
-- and works for any active account. That way a real password never travels
-- through this repository.
--
-- Scope: sales_engine only, on Eazer -- Merchants. They will see their own
-- 1,094 merchants at app.crystallux.org and nothing belonging to Blonai,
-- Crystallux Insurance Network, or the house pool.

BEGIN;

INSERT INTO auth_users (
  email, client_id, products, user_role, is_active, email_verified,
  email_verified_at, company_name, onboarding_status, signup_source,
  password_hash)
SELECT
  'info@eazer.com',
  c.id,
  '["sales_engine"]'::jsonb,
  'client',
  true,
  true,
  now(),
  'Eazer',
  'new',
  'admin_provisioned',
  '$2b$12$CWNxljEH59vgq787CW/fuOREFlgICHZbPJ4Z/iahhglLP8P2EZMTK'
FROM clients c
WHERE c.client_name = 'Eazer — Merchants'
  AND NOT EXISTS (SELECT 1 FROM auth_users WHERE email = 'info@eazer.com');

COMMIT;

-- Verify -- expect one row, scoped to Eazer, entitled to sales_engine:
--   SELECT u.email, u.products, u.is_active, c.client_name
--     FROM auth_users u JOIN clients c ON c.id = u.client_id
--    WHERE u.email = 'info@eazer.com';
--
-- Then, to set the password: crystallux.org/forgot-password, enter
-- info@eazer.com, follow the emailed link. Nobody can sign in until that is
-- done, which is the intended state.
