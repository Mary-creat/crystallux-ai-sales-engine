-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX MARKET INTELLIGENCE — SCHEMA (Phase B.9a)
-- File: docs/architecture/migrations/2026-04-24-market-intelligence.sql
--
-- Backs the Market Intelligence Engine: external-signal ingestion,
-- Claude-driven analysis, dynamic routing, client preferences, and a
-- separately-priced Intelligence tier on top of the base subscription.
--
-- Tables created:
--   market_signals_raw         — ingested from external APIs/feeds
--   market_signals_processed   — Claude-analyzed, routable
--   signal_routing_log         — audit + future ML training data
--   client_signal_preferences  — per-client opt-in + overrides
--
-- Columns added to clients:
--   intelligence_tier_enabled   (boolean)
--   intelligence_subscription_at (timestamptz)
--   intelligence_tier_price     (numeric)
--
-- RPC created:
--   enable_intelligence_tier(client_id, price)
--
-- Monitoring thresholds seeded:
--   SIGNAL_INGESTION_FAILED, SIGNAL_PROCESSING_FAILED,
--   SIGNAL_API_QUOTA_EXCEEDED, SIGNAL_HALLUCINATION_DETECTED,
--   HIGH_IMPACT_SIGNAL_DETECTED
--
-- Idempotent — safe to re-run. Rollback SQL trailing.
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. MARKET_SIGNALS_RAW (ingested from external sources)
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS market_signals_raw (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source            text NOT NULL,
  external_id       text,
  raw_payload       jsonb NOT NULL,
  raw_url           text,
  fetched_at        timestamptz DEFAULT now(),
  processed         boolean DEFAULT false,
  processing_error  text,
  UNIQUE (source, external_id)
);

CREATE INDEX IF NOT EXISTS idx_signals_raw_processed
  ON market_signals_raw(processed, fetched_at DESC);
CREATE INDEX IF NOT EXISTS idx_signals_raw_source
  ON market_signals_raw(source);

ALTER TABLE market_signals_raw ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS market_signals_raw_service_role_all ON market_signals_raw;
CREATE POLICY market_signals_raw_service_role_all ON market_signals_raw
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 2. MARKET_SIGNALS_PROCESSED (Claude-analyzed)
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS market_signals_processed (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_signal_id            uuid REFERENCES market_signals_raw(id) ON DELETE CASCADE,
  signal_type              text NOT NULL,
  headline                 text NOT NULL,
  summary                  text,
  affected_regions         jsonb DEFAULT '[]'::jsonb,
  affected_verticals       jsonb DEFAULT '[]'::jsonb,
  messaging_angle          text,
  suggested_pain_signals   jsonb DEFAULT '[]'::jsonb,
  decay_time_days          integer DEFAULT 30,
  confidence               text,
  active                   boolean DEFAULT true,
  processed_at             timestamptz DEFAULT now(),
  expires_at               timestamptz,
  source_url               text,
  claude_model_used        text,
  tokens_consumed          integer
);

-- Check constraints (guarded for idempotency)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_signals_processed_signal_type_check'
  ) THEN
    ALTER TABLE market_signals_processed
      ADD CONSTRAINT market_signals_processed_signal_type_check
      CHECK (signal_type IN (
        'natural_disaster','economic','regulatory','seasonal',
        'news_event','trend','political','technological'
      ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'market_signals_processed_confidence_check'
  ) THEN
    ALTER TABLE market_signals_processed
      ADD CONSTRAINT market_signals_processed_confidence_check
      CHECK (confidence IN ('high','medium','low'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_signals_processed_active
  ON market_signals_processed(active, expires_at);
CREATE INDEX IF NOT EXISTS idx_signals_processed_verticals
  ON market_signals_processed USING gin(affected_verticals);
CREATE INDEX IF NOT EXISTS idx_signals_processed_regions
  ON market_signals_processed USING gin(affected_regions);

ALTER TABLE market_signals_processed ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS market_signals_processed_service_role_all ON market_signals_processed;
CREATE POLICY market_signals_processed_service_role_all ON market_signals_processed
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 3. SIGNAL_ROUTING_LOG (per-decision audit trail)
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS signal_routing_log (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id                    uuid REFERENCES market_signals_processed(id) ON DELETE SET NULL,
  client_id                    uuid REFERENCES clients(id) ON DELETE SET NULL,
  vertical                     text,
  original_outreach_volume     integer,
  adjusted_outreach_volume     integer,
  multiplier_applied           numeric(4,2),
  messaging_angle_used         text,
  lead_count_affected          integer,
  decision_made_at             timestamptz DEFAULT now(),
  conversion_outcomes          jsonb
);

CREATE INDEX IF NOT EXISTS idx_signal_routing_signal
  ON signal_routing_log(signal_id, decision_made_at);
CREATE INDEX IF NOT EXISTS idx_signal_routing_client
  ON signal_routing_log(client_id, decision_made_at);

ALTER TABLE signal_routing_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS signal_routing_log_service_role_all ON signal_routing_log;
CREATE POLICY signal_routing_log_service_role_all ON signal_routing_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ─────────────────────────────────────────────────────────────────
-- 4. CLIENT_SIGNAL_PREFERENCES
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS client_signal_preferences (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid REFERENCES clients(id) ON DELETE CASCADE,
  vertical                    text,
  auto_scale_enabled          boolean DEFAULT true,
  manual_multiplier_override  numeric(4,2),
  notification_preference     text DEFAULT 'high_impact_only',
  excluded_signal_types       jsonb DEFAULT '[]'::jsonb,
  max_multiplier_cap          numeric(4,2) DEFAULT 3.0,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now(),
  UNIQUE (client_id, vertical)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'client_signal_preferences_notification_check'
  ) THEN
    ALTER TABLE client_signal_preferences
      ADD CONSTRAINT client_signal_preferences_notification_check
      CHECK (notification_preference IN ('all','high_impact_only','none'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_csp_client
  ON client_signal_preferences(client_id);

ALTER TABLE client_signal_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS client_signal_preferences_service_role_all ON client_signal_preferences;
CREATE POLICY client_signal_preferences_service_role_all ON client_signal_preferences
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Touch updated_at on every change
CREATE OR REPLACE FUNCTION touch_client_signal_preferences_updated()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_csp_updated_at ON client_signal_preferences;
CREATE TRIGGER trg_csp_updated_at
  BEFORE UPDATE ON client_signal_preferences
  FOR EACH ROW
  EXECUTE FUNCTION touch_client_signal_preferences_updated();


-- ─────────────────────────────────────────────────────────────────
-- 5. CLIENTS — INTELLIGENCE TIER COLUMNS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS intelligence_tier_enabled    boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS intelligence_subscription_at timestamptz,
  ADD COLUMN IF NOT EXISTS intelligence_tier_price      numeric(10,2);

CREATE INDEX IF NOT EXISTS idx_clients_intelligence_tier
  ON clients(intelligence_tier_enabled)
  WHERE intelligence_tier_enabled = true;


-- ─────────────────────────────────────────────────────────────────
-- 6. MONITORING THRESHOLDS
-- ─────────────────────────────────────────────────────────────────
-- The monitoring_thresholds table in this project uses column names
-- (error_code, count_threshold, window_minutes, severity). We mirror
-- the existing pattern from 2026-04-23-multi-channel.sql seeds.

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('SIGNAL_INGESTION_FAILED',       60,   3, 'warning'),
  ('SIGNAL_PROCESSING_FAILED',      60,   3, 'warning'),
  ('SIGNAL_API_QUOTA_EXCEEDED',     60,   1, 'critical'),
  ('SIGNAL_HALLUCINATION_DETECTED', 1440, 2, 'warning'),
  ('HIGH_IMPACT_SIGNAL_DETECTED',   60,   1, 'warning')
ON CONFLICT (error_code) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 7. RPC — ENABLE_INTELLIGENCE_TIER
-- ─────────────────────────────────────────────────────────────────
-- Turn on the Intelligence tier for a client + auto-create preferences
-- for every active vertical overlay. Idempotent: re-running on a client
-- who's already on the tier updates the price and ensures preference
-- rows exist for any newly-added verticals.

CREATE OR REPLACE FUNCTION enable_intelligence_tier(
  p_client_id uuid,
  p_price     numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'p_client_id required';
  END IF;

  UPDATE clients
  SET intelligence_tier_enabled    = true,
      intelligence_subscription_at = COALESCE(intelligence_subscription_at, now()),
      intelligence_tier_price      = p_price
  WHERE id = p_client_id;

  -- Auto-create a preferences row per active vertical overlay.
  -- niche_overlays uses (vertical, is_active) since the vertical-batch
  -- migration; fall back to niche_name if vertical column missing on
  -- older schemas.
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'niche_overlays' AND column_name = 'vertical'
  ) THEN
    INSERT INTO client_signal_preferences (client_id, vertical, auto_scale_enabled)
    SELECT p_client_id, vertical, true
    FROM niche_overlays
    WHERE COALESCE(is_active, true) = true
    ON CONFLICT (client_id, vertical) DO NOTHING;
  ELSE
    INSERT INTO client_signal_preferences (client_id, vertical, auto_scale_enabled)
    SELECT p_client_id, niche_name, true
    FROM niche_overlays
    ON CONFLICT (client_id, vertical) DO NOTHING;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION enable_intelligence_tier(uuid, numeric) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 8. RPC — DISABLE_INTELLIGENCE_TIER (symmetry + quick decommission)
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION disable_intelligence_tier(p_client_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE clients
  SET intelligence_tier_enabled = false
  WHERE id = p_client_id;

  UPDATE client_signal_preferences
  SET auto_scale_enabled = false
  WHERE client_id = p_client_id;
END;
$$;

GRANT EXECUTE ON FUNCTION disable_intelligence_tier(uuid) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 9. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 4 rows
SELECT 'market intelligence tables' AS check_name, COUNT(*) AS present
FROM information_schema.tables
WHERE table_name IN (
  'market_signals_raw','market_signals_processed',
  'signal_routing_log','client_signal_preferences'
);

-- Expect 3
SELECT 'clients intelligence columns' AS check_name, COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'clients'
  AND column_name IN (
    'intelligence_tier_enabled','intelligence_subscription_at','intelligence_tier_price'
  );

-- Expect 2 (enable_ + disable_intelligence_tier)
SELECT 'intelligence RPCs' AS check_name, COUNT(*) AS present
FROM information_schema.routines
WHERE routine_name IN ('enable_intelligence_tier','disable_intelligence_tier');

-- Expect 5 new monitoring thresholds
SELECT COUNT(*) AS signal_thresholds_seeded
FROM monitoring_thresholds
WHERE error_code IN (
  'SIGNAL_INGESTION_FAILED','SIGNAL_PROCESSING_FAILED',
  'SIGNAL_API_QUOTA_EXCEEDED','SIGNAL_HALLUCINATION_DETECTED',
  'HIGH_IMPACT_SIGNAL_DETECTED'
);


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 8 + 7. Drop intelligence-tier RPCs
-- DROP FUNCTION IF EXISTS disable_intelligence_tier(uuid);
-- DROP FUNCTION IF EXISTS enable_intelligence_tier(uuid, numeric);
--
-- -- 6. Remove monitoring thresholds seeded here
-- DELETE FROM monitoring_thresholds
-- WHERE error_code IN (
--   'SIGNAL_INGESTION_FAILED','SIGNAL_PROCESSING_FAILED',
--   'SIGNAL_API_QUOTA_EXCEEDED','SIGNAL_HALLUCINATION_DETECTED',
--   'HIGH_IMPACT_SIGNAL_DETECTED'
-- );
--
-- -- 5. Clients intelligence columns
-- DROP INDEX IF EXISTS idx_clients_intelligence_tier;
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS intelligence_tier_price,
--   DROP COLUMN IF EXISTS intelligence_subscription_at,
--   DROP COLUMN IF EXISTS intelligence_tier_enabled;
--
-- -- 4. Client signal preferences
-- DROP TRIGGER IF EXISTS trg_csp_updated_at ON client_signal_preferences;
-- DROP FUNCTION IF EXISTS touch_client_signal_preferences_updated();
-- DROP TABLE IF EXISTS client_signal_preferences CASCADE;
--
-- -- 3. Signal routing log
-- DROP TABLE IF EXISTS signal_routing_log CASCADE;
--
-- -- 2. Market signals processed
-- DROP TABLE IF EXISTS market_signals_processed CASCADE;
--
-- -- 1. Market signals raw
-- DROP TABLE IF EXISTS market_signals_raw CASCADE;
