-- ══════════════════════════════════════════════════════════════════
-- Role enum expansion + RLS hardening (Phase 1 foundation)
-- ══════════════════════════════════════════════════════════════════
-- Spec: docs/architecture/ROLES.md
-- Adds 6 new roles to auth_users.user_role for future phases:
--   agent              — AI Sales Agent system actor
--   advisor            — licensed closer (insurance vertical first)
--   supervisor         — oversees advisors in a client tenant
--   mga_principal      — insurance MGA agency principal
--   compliance_officer — regulated-vertical audit role
--   sub_agent          — junior advisor under supervision
--
-- Existing roles preserved: admin, client, team_member.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. Drop and re-create the user_role CHECK constraint
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE auth_users DROP CONSTRAINT IF EXISTS auth_users_user_role_check;

ALTER TABLE auth_users
  ADD CONSTRAINT auth_users_user_role_check
  CHECK (user_role IN (
    'admin',
    'client',
    'team_member',
    'agent',
    'advisor',
    'supervisor',
    'mga_principal',
    'compliance_officer',
    'sub_agent'
  ));

-- ─────────────────────────────────────────────────────────────────
-- 2. Drop and re-create the role/client_id consistency CHECK
-- ─────────────────────────────────────────────────────────────────
-- Original constraint required client_id NULL only for admin. New
-- roles need their own client_id rules:
--   admin              — client_id NULL (platform-wide)
--   agent              — client_id NULL (platform-wide system actor)
--   client             — client_id NOT NULL
--   team_member        — client_id NOT NULL
--   advisor            — client_id NOT NULL
--   supervisor         — client_id NOT NULL
--   mga_principal      — client_id NOT NULL (the MGA tenant)
--   compliance_officer — client_id NOT NULL
--   sub_agent          — client_id NOT NULL

ALTER TABLE auth_users DROP CONSTRAINT IF EXISTS auth_users_role_client_consistency;

ALTER TABLE auth_users
  ADD CONSTRAINT auth_users_role_client_consistency
  CHECK (
    (user_role IN ('admin','agent') AND client_id IS NULL) OR
    (user_role IN ('client','team_member','advisor','supervisor','mga_principal','compliance_officer','sub_agent') AND client_id IS NOT NULL)
  );

-- ─────────────────────────────────────────────────────────────────
-- 3. team_members table extension — link agents/advisors to managers
-- ─────────────────────────────────────────────────────────────────
-- Reporting hierarchy: sub_agent reports_to advisor reports_to supervisor
--                       advisor reports_to mga_principal (in MGA model)
--                       supervisor reports_to client/principal

ALTER TABLE team_members ADD COLUMN IF NOT EXISTS reports_to_user_id uuid REFERENCES auth_users(id);
CREATE INDEX IF NOT EXISTS idx_team_members_reports_to ON team_members(reports_to_user_id);

-- ─────────────────────────────────────────────────────────────────
-- 4. Update validate_session to return the user_role and client_id
-- ─────────────────────────────────────────────────────────────────
-- Existing function already returns these — re-asserting the contract
-- so downstream workflows don't break when new roles arrive. Idempotent.

DO $$
DECLARE
  v_returns text;
BEGIN
  SELECT pg_get_function_result(p.oid)
    INTO v_returns
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'validate_session' AND n.nspname = 'public'
    LIMIT 1;
  -- If the function exists, leave it alone. The new roles are valid
  -- values for the existing user_role TEXT column it returns.
  IF v_returns IS NOT NULL THEN
    RAISE NOTICE 'validate_session exists — no schema change needed for role expansion';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 5. Verification (run manually after migration)
-- ─────────────────────────────────────────────────────────────────

-- SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--   WHERE conname IN ('auth_users_user_role_check','auth_users_role_client_consistency');

-- SELECT user_role, count(*)
--   FROM auth_users
--   GROUP BY user_role
--   ORDER BY user_role;

-- ═════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment + run only to roll back)
-- ═════════════════════════════════════════════════════════════════
-- ALTER TABLE auth_users DROP CONSTRAINT IF EXISTS auth_users_user_role_check;
-- ALTER TABLE auth_users
--   ADD CONSTRAINT auth_users_user_role_check
--   CHECK (user_role IN ('admin','client','team_member'));
-- ALTER TABLE auth_users DROP CONSTRAINT IF EXISTS auth_users_role_client_consistency;
-- ALTER TABLE auth_users
--   ADD CONSTRAINT auth_users_role_client_consistency
--   CHECK (
--     (user_role = 'admin'       AND client_id IS NULL) OR
--     (user_role = 'client'      AND client_id IS NOT NULL) OR
--     (user_role = 'team_member' AND client_id IS NOT NULL)
--   );
-- ALTER TABLE team_members DROP COLUMN IF EXISTS reports_to_user_id;
