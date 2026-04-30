-- ════════════════════════════════════════════════════════════════════
-- Crystallux Client Settings — notification preference columns
--   File:    2026-04-30-client-settings-columns.sql
--   Purpose: add the two opt-in flags the client-dashboard settings
--            panel writes via /webhook/client/settings.
--            (notification_email already exists on the clients table.)
--   Idempotent — safe to re-run.
--
--   Apply BEFORE activating workflows/api/client/clx-client-settings.json.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Columns ----------------------------------------------------------
--    Default to FALSE so existing clients are NOT auto-enrolled in
--    new comms; they have to opt in via the settings panel.
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS daily_digest_opt_in    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS booking_alerts_opt_in  BOOLEAN NOT NULL DEFAULT false;

-- 2. Indexes ---------------------------------------------------------
--    Partial indexes — most rows will be FALSE, so a partial keeps the
--    indexes small and the digest/alerts senders fast.
CREATE INDEX IF NOT EXISTS clients_daily_digest_idx
  ON clients (id) WHERE daily_digest_opt_in = true;

CREATE INDEX IF NOT EXISTS clients_booking_alerts_idx
  ON clients (id) WHERE booking_alerts_opt_in = true;

-- 3. Comments --------------------------------------------------------
COMMENT ON COLUMN clients.daily_digest_opt_in
  IS 'Send the 8am ET daily summary email to notification_email. Set via /webhook/client/settings (client role only).';
COMMENT ON COLUMN clients.booking_alerts_opt_in
  IS 'Send a real-time email to notification_email when an appointment is booked. Set via /webhook/client/settings.';

COMMIT;

-- Rollback (manual, single transaction):
--   BEGIN;
--   DROP INDEX IF EXISTS clients_booking_alerts_idx;
--   DROP INDEX IF EXISTS clients_daily_digest_idx;
--   ALTER TABLE clients
--     DROP COLUMN IF EXISTS booking_alerts_opt_in,
--     DROP COLUMN IF EXISTS daily_digest_opt_in;
--   COMMIT;
