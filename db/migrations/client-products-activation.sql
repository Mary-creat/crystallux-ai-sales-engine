-- Client product activation tagging
-- ===================================
-- When a client buys Sales Engine / Sentinel / AVA / LUXI / MAXI etc.,
-- the dashboard needs to know which sections to show. Single JSONB
-- column on auth_users keeps it simple — no join table — and lets the
-- frontend filter sections with a one-line check:
--     if (user.products.includes('sentinel')) showSentinelSection();
--
-- onboarding_status tracks where a new client is in the journey so the
-- dashboard can show the right empty-state guidance.
--
-- Idempotent. Applied: 2026-05-28

BEGIN;

ALTER TABLE auth_users
  ADD COLUMN IF NOT EXISTS products jsonb DEFAULT '[]'::jsonb;

ALTER TABLE auth_users
  ADD COLUMN IF NOT EXISTS onboarding_status text DEFAULT 'new';
-- onboarding_status flow:
--   new -> account_created -> products_activated ->
--   first_login -> first_action -> active

ALTER TABLE auth_users
  ADD COLUMN IF NOT EXISTS company_name text;

ALTER TABLE auth_users
  ADD COLUMN IF NOT EXISTS signup_source text;
-- signup_source flow:
--   'client_self_serve' (filled the join-client form) |
--   'admin_provisioned' (Mary created manually) |
--   'demo_to_paid' (came through book-a-demo + converted) |
--   'partner_referral' (came through an MGA/advisor)

CREATE INDEX IF NOT EXISTS auth_users_products_idx
  ON auth_users USING gin (products);

CREATE INDEX IF NOT EXISTS auth_users_onboarding_status_idx
  ON auth_users (onboarding_status)
  WHERE onboarding_status != 'active';

COMMIT;

-- Verify
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'auth_users'
  AND column_name IN ('products', 'onboarding_status', 'company_name', 'signup_source')
ORDER BY column_name;
