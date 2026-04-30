-- ════════════════════════════════════════════════════════════════════
-- Crystallux Admin Dashboard — supplemental client columns
--   File:    2026-04-30-admin-dashboard-columns.sql
--   Purpose: add the three columns the admin onboarding-pipeline webhook
--            references (onboarding_stage / onboarding_started_at /
--            onboarding_next_action). Idempotent — safe to re-run.
--
--   Apply BEFORE activating the workflows in workflows/api/admin/.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Columns ----------------------------------------------------------
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS onboarding_stage        TEXT,
  ADD COLUMN IF NOT EXISTS onboarding_started_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS onboarding_next_action  TEXT;

-- 2. CHECK constraint on stage values --------------------------------
--    Drop-then-create lets the migration re-run safely.
ALTER TABLE clients
  DROP CONSTRAINT IF EXISTS clients_onboarding_stage_chk;

ALTER TABLE clients
  ADD CONSTRAINT clients_onboarding_stage_chk
  CHECK (
    onboarding_stage IS NULL OR onboarding_stage IN
      ('intake','provisioning','content_setup','first_send','active')
  );

-- 3. Index for the admin-onboarding-pipeline webhook ------------------
--    Filters by `onboarding_stage <> 'active'` and orders by
--    onboarding_started_at, so a partial index on the not-yet-active
--    rows pays off as the client base grows.
CREATE INDEX IF NOT EXISTS clients_onboarding_open_idx
  ON clients (onboarding_started_at)
  WHERE onboarding_stage IS DISTINCT FROM 'active';

-- 4. Backfill ---------------------------------------------------------
--    Mark existing active clients as 'active' so the onboarding
--    webhook's `onboarding_stage <> 'active'` filter excludes them.
--    Inactive rows (active=false) get NULL — they're not in onboarding
--    and not active either; the webhook doesn't surface them.
UPDATE clients
   SET onboarding_stage = 'active'
 WHERE onboarding_stage IS NULL
   AND active = true;

COMMIT;

-- Rollback (manual, single transaction):
--   BEGIN;
--   DROP INDEX IF EXISTS clients_onboarding_open_idx;
--   ALTER TABLE clients DROP CONSTRAINT IF EXISTS clients_onboarding_stage_chk;
--   ALTER TABLE clients
--     DROP COLUMN IF EXISTS onboarding_next_action,
--     DROP COLUMN IF EXISTS onboarding_started_at,
--     DROP COLUMN IF EXISTS onboarding_stage;
--   COMMIT;
