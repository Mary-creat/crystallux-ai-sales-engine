-- ══════════════════════════════════════════════════════════════════
-- Vendor Health + Outreach Retry — production hardening (Layers 3+4)
-- ══════════════════════════════════════════════════════════════════
-- Two tables that back the failure-aware retry + vendor circuit
-- breaker patterns. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- 1. Per-vendor health snapshots (one row per monitor run per vendor)
CREATE TABLE IF NOT EXISTS sentinel_vendor_health (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor            text NOT NULL,
  channel           text,
  measured_at       timestamptz DEFAULT now(),
  window_minutes    int NOT NULL DEFAULT 60,
  call_count        int NOT NULL DEFAULT 0,
  success_count     int NOT NULL DEFAULT 0,
  failure_count     int NOT NULL DEFAULT 0,
  failure_rate_pct  numeric(5,2),
  circuit_state     text NOT NULL DEFAULT 'closed',
  last_error        text,
  metadata          jsonb DEFAULT '{}'::jsonb
);

DO $$ BEGIN
  ALTER TABLE sentinel_vendor_health
    ADD CONSTRAINT svh_circuit_check
    CHECK (circuit_state IN ('closed','half_open','open'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_svh_recent
  ON sentinel_vendor_health(measured_at DESC, vendor);

CREATE INDEX IF NOT EXISTS idx_svh_open_circuits
  ON sentinel_vendor_health(vendor, measured_at DESC)
  WHERE circuit_state != 'closed';

-- 2. Outreach retry queue — failed sends scheduled for retry
CREATE TABLE IF NOT EXISTS outreach_retry_queue (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_table    text NOT NULL,
  source_id       uuid NOT NULL,
  lead_id         uuid REFERENCES leads(id) ON DELETE CASCADE,
  channel         text,
  recipient       text,
  payload         jsonb,
  retry_count     int NOT NULL DEFAULT 0,
  max_retries     int NOT NULL DEFAULT 3,
  next_retry_at   timestamptz,
  first_failed_at timestamptz DEFAULT now(),
  last_error      text,
  status          text NOT NULL DEFAULT 'pending',
  resolved_at     timestamptz,
  resolution      text,
  created_at      timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE outreach_retry_queue
    ADD CONSTRAINT orq_status_check
    CHECK (status IN ('pending','retrying','succeeded','permanent_failure','abandoned'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE outreach_retry_queue
    ADD CONSTRAINT orq_source_table_check
    CHECK (source_table IN ('outreach_log','email_log','messages_sent'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_orq_pending
  ON outreach_retry_queue(next_retry_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_orq_lead
  ON outreach_retry_queue(lead_id, status);

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS outreach_retry_queue;
-- DROP TABLE IF EXISTS sentinel_vendor_health;
