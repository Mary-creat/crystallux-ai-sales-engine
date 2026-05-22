-- ══════════════════════════════════════════════════════════════════
-- Market Intelligence (Part B.9) — external signal ingestion schema
-- ══════════════════════════════════════════════════════════════════
-- Backs the existing clx-signal-ingestion-v1 + clx-signal-intelligence-v1
-- workflows. Four tables:
--   1. market_signals_raw       — Layer 1, one row per polled event
--   2. market_signals_processed — Layer 2, classified + scored signals
--   3. signal_routing_log       — Layer 3, every routing decision a
--                                  signal influenced (revenue attribution)
--   4. client_signal_preferences — per-client opt-in / overrides
--
-- Schema mirrors the column names the existing workflows already use.
-- Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- 1. Raw layer (unclassified events, deduped by source + external_id) ─
CREATE TABLE IF NOT EXISTS market_signals_raw (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source        text NOT NULL,
  external_id   text,
  raw_payload   jsonb NOT NULL,
  raw_url       text,
  fetched_at    timestamptz DEFAULT now(),
  processed     boolean DEFAULT false,
  needs_review  boolean DEFAULT false,
  parse_error   text,
  created_at    timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE market_signals_raw
    ADD CONSTRAINT msr_source_external_unique UNIQUE (source, external_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_msr_unprocessed
  ON market_signals_raw(processed, fetched_at)
  WHERE processed = false;

CREATE INDEX IF NOT EXISTS idx_msr_source_recent
  ON market_signals_raw(source, fetched_at DESC);

-- 2. Processed layer (classified, scored, vertical-tagged) ───────────
CREATE TABLE IF NOT EXISTS market_signals_processed (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_signal_id            uuid REFERENCES market_signals_raw(id) ON DELETE SET NULL,
  signal_type              text NOT NULL,
  headline                 text NOT NULL,
  summary                  text,
  affected_regions         jsonb DEFAULT '[]'::jsonb,
  affected_verticals       jsonb DEFAULT '[]'::jsonb,
  messaging_angle          text,
  suggested_pain_signals   jsonb DEFAULT '[]'::jsonb,
  decay_time_days          int DEFAULT 30,
  confidence               text DEFAULT 'low',
  source_url               text,
  claude_model_used        text,
  tokens_consumed          int DEFAULT 0,
  needs_review             boolean DEFAULT false,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE market_signals_processed
    ADD CONSTRAINT msp_signal_type_check
    CHECK (signal_type IN (
      'natural_disaster','economic','regulatory','seasonal',
      'news_event','trend','political','technological'
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE market_signals_processed
    ADD CONSTRAINT msp_confidence_check
    CHECK (confidence IN ('high','medium','low'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_msp_active
  ON market_signals_processed(created_at DESC)
  WHERE needs_review = false;

CREATE INDEX IF NOT EXISTS idx_msp_signal_type
  ON market_signals_processed(signal_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_msp_verticals_gin
  ON market_signals_processed USING gin (affected_verticals jsonb_path_ops);

-- 3. Routing log (which signal influenced which outreach) ─────────────
CREATE TABLE IF NOT EXISTS signal_routing_log (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id             uuid REFERENCES market_signals_processed(id) ON DELETE SET NULL,
  lead_id               uuid REFERENCES leads(id) ON DELETE SET NULL,
  client_id             uuid REFERENCES clients(id) ON DELETE SET NULL,
  campaign_name         text,
  outreach_multiplier   numeric(4,2),
  decision_type         text,
  applied_at            timestamptz DEFAULT now(),
  outreach_id           uuid,
  metadata              jsonb DEFAULT '{}'::jsonb
);

DO $$ BEGIN
  ALTER TABLE signal_routing_log
    ADD CONSTRAINT srl_decision_check
    CHECK (decision_type IN ('scale_up','scale_down','message_swap','channel_boost','skip'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_srl_signal_recent
  ON signal_routing_log(signal_id, applied_at DESC);

CREATE INDEX IF NOT EXISTS idx_srl_client_recent
  ON signal_routing_log(client_id, applied_at DESC);

CREATE INDEX IF NOT EXISTS idx_srl_lead
  ON signal_routing_log(lead_id);

-- 4. Per-client signal preferences ───────────────────────────────────
CREATE TABLE IF NOT EXISTS client_signal_preferences (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  signal_type                 text NOT NULL,
  enabled                     boolean DEFAULT true,
  custom_outreach_multiplier  numeric(4,2),
  custom_messaging_overlay    text,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now(),
  UNIQUE (client_id, signal_type)
);

CREATE INDEX IF NOT EXISTS idx_csp_client
  ON client_signal_preferences(client_id, enabled);

-- ══════════════════════════════════════════════════════════════════
-- Convenience view: active signals (not decayed, not needs_review) ──
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW v_active_market_signals AS
SELECT
  msp.*,
  (msp.created_at + (msp.decay_time_days || ' days')::interval) AS expires_at,
  EXTRACT(EPOCH FROM (now() - msp.created_at)) / 3600 AS age_hours
FROM market_signals_processed msp
WHERE msp.needs_review = false
  AND now() < (msp.created_at + (msp.decay_time_days || ' days')::interval)
ORDER BY msp.created_at DESC;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP VIEW  IF EXISTS v_active_market_signals;
-- DROP TABLE IF EXISTS client_signal_preferences;
-- DROP TABLE IF EXISTS signal_routing_log;
-- DROP TABLE IF EXISTS market_signals_processed;
-- DROP TABLE IF EXISTS market_signals_raw;
