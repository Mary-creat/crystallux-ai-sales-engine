-- Access control flags + helper view for validate_session
-- ============================================================
-- Closes 4 gaps identified after Paul's first signup:
--   1. is_active flag (so Mary can suspend a client immediately if needed)
--   2. email_verified enforcement (already a column; not yet enforced)
--   3. per-product gating (products jsonb already exists from earlier migration)
--   4. subscription-status link (Stripe webhook flips is_active on cancel)
--
-- Strategy:
--   - Add is_active to auth_users (default true so existing accounts stay live)
--   - Create v_auth_users_access view that joins user fields the frontend needs
--   - validate-session workflow queries this view to return the full access
--     profile (is_active, email_verified, products, onboarding_status)
--     alongside the existing user_role / client_id / email
--
-- Idempotent. Applied: 2026-05-29

BEGIN;

ALTER TABLE auth_users
  ADD COLUMN IF NOT EXISTS is_active boolean DEFAULT true NOT NULL;

ALTER TABLE auth_users
  ADD COLUMN IF NOT EXISTS suspended_at timestamptz;

ALTER TABLE auth_users
  ADD COLUMN IF NOT EXISTS suspended_reason text;

-- Quick partial index for "list active users" queries.
CREATE INDEX IF NOT EXISTS auth_users_active_idx
  ON auth_users (is_active)
  WHERE is_active = true;

-- View that bundles every field the dashboard frontend needs to make gating
-- decisions. validate-session workflow joins on user_id to fetch this in one
-- round trip after the SQL function returns.
CREATE OR REPLACE VIEW v_auth_users_access
WITH (security_invoker = on) AS
SELECT
  id                  AS user_id,
  email,
  user_role,
  client_id,
  is_active,
  email_verified,
  email_verified_at,
  COALESCE(products, '[]'::jsonb)  AS products,
  COALESCE(onboarding_status, 'new') AS onboarding_status,
  company_name,
  signup_source,
  failed_login_attempts,
  locked_until,
  last_login_at,
  created_at
FROM auth_users;

-- ------------------------------------------------------------
-- RPC: revoke_sessions_for_client(p_client_id uuid)
-- Called by clx-stripe-webhook-v1 after a customer.subscription.deleted
-- event so any open browser tab for the suspended customer hits the
-- access gate on its next validate-session call.
-- Returns the count of sessions revoked (caller logs it).
-- Idempotent: safe to call with NULL or unknown client_id.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION revoke_sessions_for_client(p_client_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  IF p_client_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE sessions s
     SET expires_at = now()
    FROM auth_users u
   WHERE u.id = s.user_id
     AND u.client_id = p_client_id
     AND s.expires_at > now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION revoke_sessions_for_client(uuid) FROM public;
GRANT EXECUTE ON FUNCTION revoke_sessions_for_client(uuid) TO service_role;

COMMIT;

-- Verify
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'auth_users'
  AND column_name IN ('is_active', 'suspended_at', 'suspended_reason')
ORDER BY column_name;
