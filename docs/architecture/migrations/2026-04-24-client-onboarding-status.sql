-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX CLIENT ONBOARDING STATUS (Phase 6 of multi-role dashboard)
-- File: docs/architecture/migrations/2026-04-24-client-onboarding-status.sql
--
-- Backing table for the "Onboarding" dashboard panel (admin view) and
-- "Getting Started" (client view). Per-client milestone tracking:
-- contract signed, Stripe active, sender configured, Calendly connected,
-- overlay assigned, leads imported, first campaign approved, first
-- outreach sent, first reply received, first appointment booked.
--
-- Writes come from:
--   * Onboarding coordinator (Mary or VA) via manual UPDATE
--   * clx-stripe-webhook-v1 on customer.subscription.created
--   * clx-campaign-router-v2 on first campaign activation
--   * clx-outreach-sender-v2 on first send per client
--   * clx-reply-ingestion-v1 on first reply per client
--   * clx-booking-v2 on first booking per client
--
-- Idempotent — safe to re-run. Rollback SQL trailing.
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. CLIENT_ONBOARDING_STATUS TABLE
-- ─────────────────────────────────────────────────────────────────
-- One row per client. Each column tracks a specific milestone
-- timestamp. NULL = not yet reached. Non-NULL = reached on that
-- timestamp. Derived progress percentage is computed in the
-- dashboard, not the DB — timestamps stay cleanly authoritative.

CREATE TABLE IF NOT EXISTS client_onboarding_status (
  client_id                       uuid PRIMARY KEY REFERENCES clients(id) ON DELETE CASCADE,
  contract_signed_at              timestamptz,
  stripe_active_at                timestamptz,
  sender_configured_at            timestamptz,
  calendly_connected_at           timestamptz,
  overlay_assigned_at             timestamptz,
  leads_imported_at               timestamptz,
  first_campaign_approved_at      timestamptz,
  first_outreach_sent_at          timestamptz,
  first_reply_received_at         timestamptz,
  first_appointment_booked_at     timestamptz,
  -- Operator notes for VA / Mary to track blockers
  current_blocker                 text,
  blocker_since                   timestamptz,
  notes                           text,
  created_at                      timestamptz DEFAULT now(),
  updated_at                      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coi_contract_signed
  ON client_onboarding_status(contract_signed_at)
  WHERE contract_signed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_coi_first_outreach
  ON client_onboarding_status(first_outreach_sent_at)
  WHERE first_outreach_sent_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_coi_blocker
  ON client_onboarding_status(blocker_since)
  WHERE current_blocker IS NOT NULL;

ALTER TABLE client_onboarding_status ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS client_onboarding_status_service_role_all ON client_onboarding_status;
CREATE POLICY client_onboarding_status_service_role_all ON client_onboarding_status
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 2. UPDATED_AT TRIGGER
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION touch_client_onboarding_status_updated()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_coi_updated_at ON client_onboarding_status;
CREATE TRIGGER trg_coi_updated_at
  BEFORE UPDATE ON client_onboarding_status
  FOR EACH ROW
  EXECUTE FUNCTION touch_client_onboarding_status_updated();


-- ─────────────────────────────────────────────────────────────────
-- 3. SEED ROWS FOR EXISTING CLIENTS
-- ─────────────────────────────────────────────────────────────────
-- Backfill one row per existing active client so the dashboard has
-- something to render on activation day. Onboarding coordinator
-- updates specific timestamp fields as milestones land.

INSERT INTO client_onboarding_status (client_id)
SELECT id FROM clients
WHERE active = true
ON CONFLICT (client_id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 4. RPC: BUMP MILESTONE
-- ─────────────────────────────────────────────────────────────────
-- Safe-setter RPC for workflows to mark a milestone. Idempotent:
-- if the milestone is already set, the call is a no-op (preserves
-- the earliest timestamp rather than overwriting with the latest).

CREATE OR REPLACE FUNCTION bump_onboarding_milestone(
  p_client_id uuid,
  p_milestone text  -- one of: contract_signed, stripe_active,
                    -- sender_configured, calendly_connected,
                    -- overlay_assigned, leads_imported,
                    -- first_campaign_approved, first_outreach_sent,
                    -- first_reply_received, first_appointment_booked
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  col_name text;
BEGIN
  col_name := CASE p_milestone
    WHEN 'contract_signed'           THEN 'contract_signed_at'
    WHEN 'stripe_active'             THEN 'stripe_active_at'
    WHEN 'sender_configured'         THEN 'sender_configured_at'
    WHEN 'calendly_connected'        THEN 'calendly_connected_at'
    WHEN 'overlay_assigned'          THEN 'overlay_assigned_at'
    WHEN 'leads_imported'            THEN 'leads_imported_at'
    WHEN 'first_campaign_approved'   THEN 'first_campaign_approved_at'
    WHEN 'first_outreach_sent'       THEN 'first_outreach_sent_at'
    WHEN 'first_reply_received'      THEN 'first_reply_received_at'
    WHEN 'first_appointment_booked'  THEN 'first_appointment_booked_at'
    ELSE NULL
  END;

  IF col_name IS NULL THEN
    RAISE EXCEPTION 'Unknown onboarding milestone: %', p_milestone;
  END IF;

  -- Ensure the row exists
  INSERT INTO client_onboarding_status (client_id)
  VALUES (p_client_id)
  ON CONFLICT (client_id) DO NOTHING;

  -- Only set if currently NULL (preserves earliest-wins semantics)
  EXECUTE format(
    'UPDATE client_onboarding_status SET %I = COALESCE(%I, now()) WHERE client_id = $1',
    col_name, col_name
  ) USING p_client_id;
END;
$$;

GRANT EXECUTE ON FUNCTION bump_onboarding_milestone(uuid, text) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 5. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 1 row
SELECT 'client_onboarding_status table' AS check_name, COUNT(*) AS present
FROM information_schema.tables WHERE table_name = 'client_onboarding_status';

-- Expect 3 indexes
SELECT 'client_onboarding_status indexes' AS check_name, COUNT(*) AS present
FROM pg_indexes WHERE indexname IN (
  'idx_coi_contract_signed','idx_coi_first_outreach','idx_coi_blocker'
);

-- Expect 1 RPC
SELECT 'bump_onboarding_milestone RPC' AS check_name, COUNT(*) AS present
FROM information_schema.routines WHERE routine_name = 'bump_onboarding_milestone';

-- Expect N rows (one per active client) — backfill verification
SELECT 'onboarding rows vs active clients' AS check_name,
  (SELECT COUNT(*) FROM client_onboarding_status) AS onboarding_rows,
  (SELECT COUNT(*) FROM clients WHERE active = true) AS active_clients;


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ═══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS bump_onboarding_milestone(uuid, text);
-- DROP TRIGGER IF EXISTS trg_coi_updated_at ON client_onboarding_status;
-- DROP FUNCTION IF EXISTS touch_client_onboarding_status_updated();
-- DROP INDEX IF EXISTS idx_coi_blocker;
-- DROP INDEX IF EXISTS idx_coi_first_outreach;
-- DROP INDEX IF EXISTS idx_coi_contract_signed;
-- DROP TABLE IF EXISTS client_onboarding_status;
