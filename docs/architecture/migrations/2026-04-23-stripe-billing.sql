-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX STRIPE BILLING — SCHEMA SCAFFOLDING (Task 3)
-- File: docs/architecture/migrations/2026-04-23-stripe-billing.sql
--
-- Adds the Stripe billing surface the clx-stripe-webhook-v1 and
-- clx-stripe-provision-v1 workflows write into. Schema-only — no live
-- Stripe API calls are wired. Both workflows ship active=false with
-- placeholder credential notes. Activation steps live in
-- OPERATIONS_HANDBOOK §21.
--
-- Idempotent — safe to re-run. All column adds use IF NOT EXISTS,
-- check constraints guarded with DO blocks, policies DROP ... IF EXISTS
-- before CREATE.
--
-- Runs AFTER:
--   * 2026-04-23-apollo-schema.sql
--   * 2026-04-23-multi-channel.sql
--   * 2026-04-23-video-schema.sql
--   * 2026-04-23-b2b-b2c-segmentation.sql
--
-- Rollback SQL at the bottom (commented).
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. CLIENTS — STRIPE BILLING COLUMNS
-- ─────────────────────────────────────────────────────────────────
-- stripe_customer_id      — Stripe Customer object ID (cus_...)
-- stripe_subscription_id  — active Subscription ID (sub_...)
-- subscription_status     — mirrors Stripe subscription.status
--                           (trialing, active, past_due, canceled,
--                           incomplete, paused). NULL = not yet
--                           provisioned.
-- subscription_plan       — our internal plan key (e.g.,
--                           'founding_1997', 'salon_997',
--                           'intelligence_3997', 'construction_1497')
-- next_billing_date       — from Stripe subscription.current_period_end
-- last_payment_amount     — last invoice.paid amount in CAD
-- last_payment_at         — last invoice.paid timestamp
-- trial_ends_at           — subscription.trial_end when trialing

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS stripe_customer_id     text,
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text,
  ADD COLUMN IF NOT EXISTS subscription_status    text,
  ADD COLUMN IF NOT EXISTS subscription_plan      text,
  ADD COLUMN IF NOT EXISTS next_billing_date      date,
  ADD COLUMN IF NOT EXISTS last_payment_amount    numeric(10,2),
  ADD COLUMN IF NOT EXISTS last_payment_at        timestamptz,
  ADD COLUMN IF NOT EXISTS trial_ends_at          timestamptz;

-- Subscription status enum guard. NULL is allowed (client exists but
-- not yet on a subscription — e.g., trialing via free first month).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'clients_subscription_status_check'
  ) THEN
    ALTER TABLE clients
      ADD CONSTRAINT clients_subscription_status_check
      CHECK (subscription_status IS NULL OR subscription_status IN (
        'trialing','active','past_due','canceled','incomplete','paused'
      ));
  END IF;
END $$;

-- Indexes for common admin-dashboard queries:
--   * lookup by Stripe customer ID during webhook processing
--   * filter by status for MRR and dunning reports
CREATE INDEX IF NOT EXISTS idx_clients_stripe_customer
  ON clients(stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_clients_subscription_status
  ON clients(subscription_status)
  WHERE subscription_status IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────
-- 2. STRIPE_EVENTS_LOG (NEW — audit trail for every webhook event)
-- ─────────────────────────────────────────────────────────────────
-- One row per Stripe webhook. Dedup by stripe_event_id (Stripe
-- guarantees uniqueness per delivery but resends on retry). processed
-- is set to true only after the webhook handler has successfully
-- applied the event. Unprocessed rows are candidates for a manual
-- retry if the handler failed mid-flight.

CREATE TABLE IF NOT EXISTS stripe_events_log (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stripe_event_id   text UNIQUE NOT NULL,
  event_type        text NOT NULL,
  payload           jsonb NOT NULL,
  client_id         uuid REFERENCES clients(id) ON DELETE SET NULL,
  processed         boolean DEFAULT false,
  processed_at      timestamptz,
  received_at       timestamptz DEFAULT now(),
  error_message     text,
  metadata          jsonb,
  created_at        timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stripe_events_type
  ON stripe_events_log(event_type, received_at);
CREATE INDEX IF NOT EXISTS idx_stripe_events_unprocessed
  ON stripe_events_log(processed, received_at)
  WHERE processed = false;
CREATE INDEX IF NOT EXISTS idx_stripe_events_client
  ON stripe_events_log(client_id, received_at);

ALTER TABLE stripe_events_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS stripe_events_log_service_role_all ON stripe_events_log;
CREATE POLICY stripe_events_log_service_role_all ON stripe_events_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 3. MONITORING THRESHOLDS
-- ─────────────────────────────────────────────────────────────────
-- Error codes the webhook and provisioning workflows emit to
-- scan_errors. ON CONFLICT DO NOTHING so re-runs don't clobber
-- thresholds Mary has tuned in the dashboard.

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('STRIPE_PAYMENT_FAILED',          60, 1, 'critical'),
  ('STRIPE_SUBSCRIPTION_CANCELED',   60, 1, 'warning'),
  ('STRIPE_WEBHOOK_UNVERIFIED',      10, 1, 'critical'),
  ('STRIPE_WEBHOOK_HANDLER_FAILED',  10, 3, 'warning'),
  ('STRIPE_PROVISION_FAILED',        60, 1, 'warning')
ON CONFLICT (error_code) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 4. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 8
SELECT 'clients stripe columns' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'clients'
  AND column_name IN (
    'stripe_customer_id','stripe_subscription_id',
    'subscription_status','subscription_plan',
    'next_billing_date','last_payment_amount',
    'last_payment_at','trial_ends_at'
  );

-- Expect 1
SELECT 'clients.subscription_status check constraint' AS check_name,
       COUNT(*) AS present
FROM pg_constraint
WHERE conname = 'clients_subscription_status_check';

-- Expect 1
SELECT 'stripe_events_log table' AS check_name,
       COUNT(*) AS present
FROM information_schema.tables
WHERE table_name = 'stripe_events_log';

-- Expect 2 (clients stripe + subscription_status indexes)
SELECT 'clients stripe indexes' AS check_name,
       COUNT(*) AS present
FROM pg_indexes
WHERE indexname IN (
  'idx_clients_stripe_customer',
  'idx_clients_subscription_status'
);

-- Expect 3 (stripe_events_log indexes)
SELECT 'stripe_events_log indexes' AS check_name,
       COUNT(*) AS present
FROM pg_indexes
WHERE indexname IN (
  'idx_stripe_events_type',
  'idx_stripe_events_unprocessed',
  'idx_stripe_events_client'
);

-- Expect 5 Stripe-related monitoring thresholds
SELECT COUNT(*) AS stripe_thresholds_seeded
FROM monitoring_thresholds
WHERE error_code LIKE 'STRIPE_%';


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo — test on staging first)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 3. Monitoring thresholds
-- DELETE FROM monitoring_thresholds WHERE error_code LIKE 'STRIPE_%';
--
-- -- 2. Stripe events log
-- DROP TABLE IF EXISTS stripe_events_log CASCADE;
--
-- -- 1. Clients stripe columns
-- DROP INDEX IF EXISTS idx_clients_subscription_status;
-- DROP INDEX IF EXISTS idx_clients_stripe_customer;
-- ALTER TABLE clients DROP CONSTRAINT IF EXISTS clients_subscription_status_check;
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS trial_ends_at,
--   DROP COLUMN IF EXISTS last_payment_at,
--   DROP COLUMN IF EXISTS last_payment_amount,
--   DROP COLUMN IF EXISTS next_billing_date,
--   DROP COLUMN IF EXISTS subscription_plan,
--   DROP COLUMN IF EXISTS subscription_status,
--   DROP COLUMN IF EXISTS stripe_subscription_id,
--   DROP COLUMN IF EXISTS stripe_customer_id;
