-- Test client account for QA + automated audit
--
-- Creates a client-role login bound to Crystallux Insurance Network so
-- the dashboard-audit harness (tests/audit/dashboard-audit.js) can sign
-- into the client UI and exercise every page + tenant isolation.
--
-- Credentials are documented in docs/testing/test-accounts.md (Mary's
-- private notes). Do not commit the plaintext password to a public log.
--
-- Hash: bcrypt (pgcrypto's gen_salt('bf')). Safe with the existing
-- verify_password() flow.

-- Make sure pgcrypto is available (idempotent — schema-level)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- NOTE: auth_users has no `active` column. The gating column is `email_verified`
-- (see docs/architecture/migrations/2026-04-28-authentication.sql). Setting it
-- true so the test login is not bounced to the verify-email screen.
INSERT INTO auth_users (
  email,
  password_hash,
  user_role,
  client_id,
  email_verified,
  created_at
) VALUES (
  'testclient@crystallux.org',
  crypt('TestPass2026#', gen_salt('bf')),
  'client',
  '6edc687d-07b0-4478-bb4b-820dc4eebf5d',
  true,
  NOW()
)
ON CONFLICT (email) DO UPDATE
  SET password_hash  = EXCLUDED.password_hash,
      user_role      = EXCLUDED.user_role,
      client_id      = EXCLUDED.client_id,
      email_verified = EXCLUDED.email_verified;

-- Verify
SELECT
  email,
  user_role,
  client_id,
  email_verified,
  created_at,
  -- Confirm the bcrypt hash verifies the chosen password
  (password_hash = crypt('TestPass2026#', password_hash)) AS password_verifies
FROM auth_users
WHERE email = 'testclient@crystallux.org';
