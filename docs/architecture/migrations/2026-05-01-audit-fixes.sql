-- ════════════════════════════════════════════════════════════════════
-- Crystallux pre-launch audit — schema fix migration
--   File:    2026-05-01-audit-fixes.sql
--   Purpose: close every schema gap surfaced by the 2026-05-01 audit
--            so the new auth/admin/client webhooks return real data
--            instead of 400/404/empty.
--   Status:  patched 2026-05-01 after first apply attempt failed at
--            section 4 — live scan_log was created ad-hoc earlier
--            with a different shape than the original draft assumed.
--            Section 4 now ALTERs the existing table instead of
--            recreating it; sections 2 and 3 backfills are guarded
--            with DO blocks so missing legacy columns RAISE NOTICE
--            instead of aborting the transaction.
--   Idempotent — safe to re-run.
--
--   Apply BEFORE activating the affected workflows:
--     - clx-client-campaigns          (needs campaigns table)
--     - clx-client-bookings           (needs appointment_log columns)
--     - clx-admin-audit-log           (needs admin_action_log columns
--                                      OR webhook rewrite — see notes)
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. campaigns table
-- ─────────────────────────────────────────────────────────────────────
-- The clx-client-campaigns webhook queries SELECT id, name, channel,
-- status, sent, replies, started_at, updated_at FROM campaigns
-- WHERE client_id = <session>. No prior migration creates this
-- table — the existing 'carousel_campaigns' is a different concept.
-- This is a minimal table that can be enriched later (add description,
-- sequence_steps, end_date, etc.).
CREATE TABLE IF NOT EXISTS campaigns (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id     uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  name          text NOT NULL,
  channel       text NOT NULL CHECK (channel IN ('email','linkedin','whatsapp','sms','voice','video','multi')),
  status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','paused','completed','archived')),
  sent          integer NOT NULL DEFAULT 0,
  replies       integer NOT NULL DEFAULT 0,
  started_at    timestamptz,
  ended_at      timestamptz,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS campaigns_client_idx
  ON campaigns (client_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS campaigns_active_idx
  ON campaigns (client_id) WHERE status = 'active';

ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campaigns service_role" ON campaigns;
CREATE POLICY "campaigns service_role"
  ON campaigns FOR ALL TO service_role USING (true) WITH CHECK (true);

-- updated_at trigger
CREATE OR REPLACE FUNCTION campaigns_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS campaigns_updated_at ON campaigns;
CREATE TRIGGER campaigns_updated_at
  BEFORE UPDATE ON campaigns
  FOR EACH ROW EXECUTE FUNCTION campaigns_set_updated_at();

-- ─────────────────────────────────────────────────────────────────────
-- 2. appointment_log additions for client-bookings webhook
-- ─────────────────────────────────────────────────────────────────────
-- The webhook SELECTS company, attendee_name, event_type — none exist
-- on the original table. Add them as nullable text so existing rows
-- aren't disturbed; the calendar workflows can populate them going
-- forward.
ALTER TABLE appointment_log
  ADD COLUMN IF NOT EXISTS company         text,
  ADD COLUMN IF NOT EXISTS attendee_name   text,
  ADD COLUMN IF NOT EXISTS event_type      text;

COMMENT ON COLUMN appointment_log.company        IS 'Company name surfaced to client/bookings panel. Populate from leads.company on insert.';
COMMENT ON COLUMN appointment_log.attendee_name  IS 'Attendee name surfaced to client/bookings panel. Populate from leads or Calendly invitee.';
COMMENT ON COLUMN appointment_log.event_type     IS 'Human label (e.g. "Discovery call (30 min)"). Maps to appointment_type for legacy rows.';

-- Optional backfill — copy appointment_type into event_type so existing
-- rows have something to display before the workflows are updated.
-- Guarded for schema drift: appointment_type may not exist in every
-- environment. Skipped (with NOTICE) rather than aborting the txn.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'appointment_log'
       AND column_name  = 'appointment_type'
  ) THEN
    UPDATE appointment_log
       SET event_type = appointment_type
     WHERE event_type IS NULL
       AND appointment_type IS NOT NULL;
  ELSE
    RAISE NOTICE 'appointment_log: appointment_type column missing — backfill skipped';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. admin_action_log alignment
-- ─────────────────────────────────────────────────────────────────────
-- The clx-admin-audit-log webhook selects actor_email, action,
-- target_type, target_id, occurred_at — all of which are missing.
-- Add them as new columns; keep the original Copilot columns intact
-- so the existing copilot workflow keeps writing without changes.
-- New audit-emitting code (Phase 4 client-settings, password-reset)
-- writes the new columns. The two schemas coexist in one table.
ALTER TABLE admin_action_log
  ADD COLUMN IF NOT EXISTS actor_email   text,
  ADD COLUMN IF NOT EXISTS action        text,
  ADD COLUMN IF NOT EXISTS target_type   text,
  ADD COLUMN IF NOT EXISTS target_id     text,
  ADD COLUMN IF NOT EXISTS occurred_at   timestamptz;

-- Backfill: project the existing copilot rows onto the new shape so
-- the audit-log webhook returns a useful history immediately. Guarded
-- for schema drift — if any of the legacy columns are missing the
-- backfill is skipped with a NOTICE; the new columns and the
-- occurred_at index are still created.
DO $$
DECLARE
  has_legacy boolean;
BEGIN
  SELECT
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admin_action_log' AND column_name='admin_user')     AND
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admin_action_log' AND column_name='action_type')   AND
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admin_action_log' AND column_name='panel_context') AND
    EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='admin_action_log' AND column_name='created_at')
  INTO has_legacy;

  IF has_legacy THEN
    UPDATE admin_action_log
       SET actor_email = COALESCE(actor_email, admin_user || '@crystallux.org'),
           action      = COALESCE(action,      action_type),
           target_type = COALESCE(target_type, panel_context),
           occurred_at = COALESCE(occurred_at, created_at)
     WHERE actor_email IS NULL OR action IS NULL OR occurred_at IS NULL;
  ELSE
    RAISE NOTICE 'admin_action_log: one or more legacy columns missing — backfill skipped';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS admin_action_log_occurred_idx
  ON admin_action_log (occurred_at DESC NULLS LAST);

-- ─────────────────────────────────────────────────────────────────────
-- 4. scan_log additions for admin dashboard panels
-- ─────────────────────────────────────────────────────────────────────
-- The live scan_log was created ad-hoc earlier for lead-scanning with
-- a different shape than the original draft of this migration assumed.
-- Live columns: id, workflow_name, search_query, city, industry,
--               product_type, results_found, new_leads_inserted,
--               duplicates_skipped, errors, scanned_at.
--
-- The original draft did `CREATE TABLE IF NOT EXISTS scan_log (...)`
-- which silently no-op'd against the live table, then created a
-- partial index referencing a non-existent column (`error_count`),
-- aborting the transaction.
--
-- Patched approach: do not touch the live table or its data. ADD the
-- columns the admin dashboards need (status, duration_ms, payload),
-- create indexes against the actual `errors` column, and ensure RLS
-- + service_role policy. The clx-admin-system-health and
-- clx-admin-workflow-status webhooks have been updated in the same
-- commit to read `errors` (live name) instead of `error_count`.
ALTER TABLE scan_log
  ADD COLUMN IF NOT EXISTS status       text,
  ADD COLUMN IF NOT EXISTS duration_ms  integer,
  ADD COLUMN IF NOT EXISTS payload      jsonb;

COMMENT ON COLUMN scan_log.status      IS 'Webhook-set rollup label: ok | error | partial. Legacy rows are NULL; webhook falls back to errors > 0.';
COMMENT ON COLUMN scan_log.duration_ms IS 'Workflow run duration in ms; aggregated into avg_ms by clx-admin-workflow-status.';
COMMENT ON COLUMN scan_log.payload     IS 'Optional JSON blob for run-specific context. No current reader; reserved for future per-run drill-down.';

CREATE INDEX IF NOT EXISTS scan_log_scanned_idx
  ON scan_log (scanned_at DESC);
CREATE INDEX IF NOT EXISTS scan_log_workflow_idx
  ON scan_log (workflow_name, scanned_at DESC);
CREATE INDEX IF NOT EXISTS scan_log_errors_idx
  ON scan_log (scanned_at DESC) WHERE errors > 0;

ALTER TABLE scan_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "scan_log service_role" ON scan_log;
CREATE POLICY "scan_log service_role"
  ON scan_log FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- Rollback (manual, single transaction):
--   BEGIN;
--   DROP TABLE IF EXISTS campaigns;
--   DROP FUNCTION IF EXISTS campaigns_set_updated_at();
--   ALTER TABLE appointment_log
--     DROP COLUMN IF EXISTS event_type,
--     DROP COLUMN IF EXISTS attendee_name,
--     DROP COLUMN IF EXISTS company;
--   ALTER TABLE admin_action_log
--     DROP COLUMN IF EXISTS occurred_at,
--     DROP COLUMN IF EXISTS target_id,
--     DROP COLUMN IF EXISTS target_type,
--     DROP COLUMN IF EXISTS action,
--     DROP COLUMN IF EXISTS actor_email;
--   DROP INDEX IF EXISTS admin_action_log_occurred_idx;
--   ALTER TABLE scan_log
--     DROP COLUMN IF EXISTS payload,
--     DROP COLUMN IF EXISTS duration_ms,
--     DROP COLUMN IF EXISTS status;
--   DROP INDEX IF EXISTS scan_log_errors_idx;
--   DROP INDEX IF EXISTS scan_log_workflow_idx;
--   DROP INDEX IF EXISTS scan_log_scanned_idx;
--   -- DO NOT drop scan_log itself — it holds live lead-scanning history.
--   COMMIT;
-- ════════════════════════════════════════════════════════════════════
