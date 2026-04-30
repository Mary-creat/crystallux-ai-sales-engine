-- ════════════════════════════════════════════════════════════════════
-- Crystallux Authentication — schema + RLS + seeds
--   File:    2026-04-28-authentication.sql
--   Phase:   Tier-2 foundation for admin.crystallux.org / app.crystallux.org
--   Author:  Mary Akintunde (architecture: 2026-04-29)
--
-- Purpose
--   Replace the current "paste service-role key in browser" model with a
--   real session-token system. Authentication is enforced in n8n
--   webhooks; the browser only ever sees an opaque session token.
--
-- Tables
--   auth_users           — login identity + role
--   auth_sessions        — issued session tokens
--   auth_magic_links     — single-use email-link tokens
--   auth_password_resets — single-use reset tokens
--
-- Security
--   Every table is RLS-enabled with service_role full access only. The
--   auth webhooks run server-side (n8n) with the service-role key; no
--   anon-role policy is granted because the dashboards never query
--   these tables directly.
--
-- Co-existence
--   This migration is purely additive. It does not alter clients,
--   leads, scan_log, or any pre-existing object. The Mary master-token
--   path (URL ?token=...) keeps working until Phase 4 retires it.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. auth_users — login identity
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth_users (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email                 TEXT UNIQUE NOT NULL,
  password_hash         TEXT,                   -- bcrypt cost 12; NULL = magic-link only
  user_role             TEXT NOT NULL CHECK (user_role IN ('admin','client','team_member')),
  client_id             UUID REFERENCES clients(id) ON DELETE SET NULL,
  email_verified        BOOLEAN NOT NULL DEFAULT false,
  email_verified_at     TIMESTAMPTZ,
  last_login_at         TIMESTAMPTZ,
  failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until          TIMESTAMPTZ,            -- when set + future, login is refused
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Lower-cased lookup ensures Login@Crystallux.org === login@crystallux.org
CREATE UNIQUE INDEX IF NOT EXISTS auth_users_email_lower_idx
  ON auth_users (lower(email));

CREATE INDEX IF NOT EXISTS auth_users_client_id_idx
  ON auth_users (client_id) WHERE client_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS auth_users_role_idx
  ON auth_users (user_role);

-- Admin row may not have a client_id; client/team rows must. Enforce.
ALTER TABLE auth_users
  DROP CONSTRAINT IF EXISTS auth_users_client_role_chk;
ALTER TABLE auth_users
  ADD CONSTRAINT auth_users_client_role_chk
  CHECK (
    (user_role = 'admin'       AND client_id IS NULL) OR
    (user_role = 'client'      AND client_id IS NOT NULL) OR
    (user_role = 'team_member' AND client_id IS NOT NULL)
  );

-- updated_at maintenance
CREATE OR REPLACE FUNCTION auth_users_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auth_users_updated_at ON auth_users;
CREATE TRIGGER auth_users_updated_at
  BEFORE UPDATE ON auth_users
  FOR EACH ROW EXECUTE FUNCTION auth_users_set_updated_at();

-- ─────────────────────────────────────────────────────────────────────
-- 2. auth_sessions — issued session tokens
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth_sessions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  session_token    TEXT UNIQUE NOT NULL,    -- 64-char base64url; opaque to browser
  expires_at       TIMESTAMPTZ NOT NULL,
  ip_address       INET,
  user_agent       TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at       TIMESTAMPTZ              -- non-null = invalidated
);

CREATE INDEX IF NOT EXISTS auth_sessions_user_idx
  ON auth_sessions (user_id);

CREATE INDEX IF NOT EXISTS auth_sessions_active_idx
  ON auth_sessions (session_token)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS auth_sessions_expiry_idx
  ON auth_sessions (expires_at)
  WHERE revoked_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 3. auth_magic_links — single-use email links
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth_magic_links (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email      TEXT NOT NULL,
  token      TEXT UNIQUE NOT NULL,           -- 32-byte base64url
  expires_at TIMESTAMPTZ NOT NULL,           -- typical 15 min from issue
  used_at    TIMESTAMPTZ,                    -- non-null = consumed
  ip_address INET,                           -- where the request originated
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS auth_magic_links_email_idx
  ON auth_magic_links (lower(email))
  WHERE used_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 4. auth_password_resets — single-use reset links
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth_password_resets (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  token      TEXT UNIQUE NOT NULL,           -- 32-byte base64url
  expires_at TIMESTAMPTZ NOT NULL,           -- typical 1 hour from issue
  used_at    TIMESTAMPTZ,
  ip_address INET,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS auth_password_resets_user_idx
  ON auth_password_resets (user_id)
  WHERE used_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 5. RLS — service_role only
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE auth_users           ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_sessions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_magic_links     ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_password_resets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_users service_role"           ON auth_users;
DROP POLICY IF EXISTS "auth_sessions service_role"        ON auth_sessions;
DROP POLICY IF EXISTS "auth_magic_links service_role"     ON auth_magic_links;
DROP POLICY IF EXISTS "auth_password_resets service_role" ON auth_password_resets;

CREATE POLICY "auth_users service_role"           ON auth_users           FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "auth_sessions service_role"        ON auth_sessions        FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "auth_magic_links service_role"     ON auth_magic_links     FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "auth_password_resets service_role" ON auth_password_resets FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────
-- 6. RPC: validate_session — central session check used by every webhook
--    Returns one row when token is valid (not revoked, not expired);
--    no rows otherwise. Sliding-window expiry is the caller's job
--    (post-validation UPDATE on last_activity_at + expires_at).
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION validate_session(p_token TEXT)
RETURNS TABLE (
  user_id    UUID,
  email      TEXT,
  user_role  TEXT,
  client_id  UUID,
  expires_at TIMESTAMPTZ
) LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT u.id, u.email, u.user_role, u.client_id, s.expires_at
  FROM   auth_sessions s
  JOIN   auth_users    u ON u.id = s.user_id
  WHERE  s.session_token = p_token
    AND  s.revoked_at IS NULL
    AND  s.expires_at > now()
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION validate_session(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION validate_session(TEXT) TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 7. RPC: touch_session — sliding-window extend + activity stamp
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION touch_session(p_token TEXT, p_extend_seconds INT DEFAULT 604800)
RETURNS VOID LANGUAGE sql VOLATILE SECURITY DEFINER AS $$
  UPDATE auth_sessions
     SET last_activity_at = now(),
         expires_at       = GREATEST(expires_at, now() + (p_extend_seconds || ' seconds')::INTERVAL)
   WHERE session_token = p_token
     AND revoked_at IS NULL
     AND expires_at > now();
$$;

REVOKE ALL ON FUNCTION touch_session(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION touch_session(TEXT, INT) TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 8. RPC: revoke_session — for /logout and forced revocation
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION revoke_session(p_token TEXT)
RETURNS VOID LANGUAGE sql VOLATILE SECURITY DEFINER AS $$
  UPDATE auth_sessions
     SET revoked_at = now()
   WHERE session_token = p_token
     AND revoked_at IS NULL;
$$;

REVOKE ALL ON FUNCTION revoke_session(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION revoke_session(TEXT) TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 9. RPC: register_failed_login — increments counter, locks at 5
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION register_failed_login(p_email TEXT)
RETURNS TABLE (locked BOOLEAN, locked_until TIMESTAMPTZ)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER AS $$
DECLARE
  v_attempts INT;
  v_locked_until TIMESTAMPTZ;
BEGIN
  UPDATE auth_users
     SET failed_login_attempts = failed_login_attempts + 1,
         locked_until = CASE
            WHEN failed_login_attempts + 1 >= 5 THEN now() + INTERVAL '15 minutes'
            ELSE locked_until
         END
   WHERE lower(email) = lower(p_email)
   RETURNING failed_login_attempts, locked_until INTO v_attempts, v_locked_until;

  RETURN QUERY SELECT (v_attempts >= 5), v_locked_until;
END;
$$;

REVOKE ALL ON FUNCTION register_failed_login(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION register_failed_login(TEXT) TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 10. RPC: register_successful_login — clears counters, stamps timestamp
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION register_successful_login(p_user_id UUID)
RETURNS VOID LANGUAGE sql VOLATILE SECURITY DEFINER AS $$
  UPDATE auth_users
     SET failed_login_attempts = 0,
         locked_until = NULL,
         last_login_at = now()
   WHERE id = p_user_id;
$$;

REVOKE ALL ON FUNCTION register_successful_login(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION register_successful_login(UUID) TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 11. Mary admin seed
--     The bcrypt hash below is a real cost-12 hash of a placeholder
--     password ("ChangeMeOnFirstLogin!") generated by
--     scripts/auth-bcrypt.js. Mary should run the password-reset flow
--     immediately on first login and the placeholder will be retired.
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO auth_users (email, password_hash, user_role, email_verified, email_verified_at)
VALUES (
  'info@crystallux.org',
  '$2b$12$8wM0vG5bH2EjRq4gQ3p1wexnJv1zE/6cJZk3SZFq4tD8aT9nGvq8K',
  'admin',
  true,
  now()
)
ON CONFLICT (email) DO NOTHING;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────
-- Rollback (manual, single transaction):
--   BEGIN;
--   DROP FUNCTION IF EXISTS register_successful_login(UUID);
--   DROP FUNCTION IF EXISTS register_failed_login(TEXT);
--   DROP FUNCTION IF EXISTS revoke_session(TEXT);
--   DROP FUNCTION IF EXISTS touch_session(TEXT, INT);
--   DROP FUNCTION IF EXISTS validate_session(TEXT);
--   DROP TABLE IF EXISTS auth_password_resets;
--   DROP TABLE IF EXISTS auth_magic_links;
--   DROP TABLE IF EXISTS auth_sessions;
--   DROP TABLE IF EXISTS auth_users;
--   DROP FUNCTION IF EXISTS auth_users_set_updated_at();
--   COMMIT;
