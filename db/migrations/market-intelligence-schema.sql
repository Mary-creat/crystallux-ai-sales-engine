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

-- Defensive ADD COLUMN for tables that may already exist from earlier
-- partial migrations. IF NOT EXISTS on CREATE TABLE only protects the
-- first creation — subsequent column additions need ALTER.
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS raw_signal_id          uuid;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS signal_type            text;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS headline               text;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS summary                text;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS affected_regions       jsonb DEFAULT '[]'::jsonb;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS affected_verticals     jsonb DEFAULT '[]'::jsonb;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS messaging_angle        text;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS suggested_pain_signals jsonb DEFAULT '[]'::jsonb;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS decay_time_days        int DEFAULT 30;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS confidence             text DEFAULT 'low';
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS source_url             text;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS claude_model_used      text;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS tokens_consumed        int DEFAULT 0;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS needs_review           boolean DEFAULT false;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS created_at             timestamptz DEFAULT now();
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS updated_at             timestamptz DEFAULT now();

-- Columns the existing clx-campaign-router-v2 + clx-outreach-generation-v2
-- workflows already query against. `active` is a soft retire flag; the
-- workflows use it to filter to currently-influencing signals. `processed_at`
-- is the timestamp Claude classified the signal (kept distinct from
-- created_at so analytics can separate the two). `expires_at` is computed
-- automatically from created_at + decay_time_days.
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS active        boolean     DEFAULT true;
ALTER TABLE market_signals_processed ADD COLUMN IF NOT EXISTS processed_at  timestamptz DEFAULT now();

DO $$ BEGIN
  ALTER TABLE market_signals_processed
    ADD COLUMN expires_at timestamptz
    GENERATED ALWAYS AS (created_at + (decay_time_days || ' days')::interval) STORED;
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_msp_active_expires
  ON market_signals_processed(active, expires_at)
  WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_msp_processed_at
  ON market_signals_processed(processed_at DESC);

ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS source       text;
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS external_id  text;
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS raw_payload  jsonb;
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS raw_url      text;
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS fetched_at   timestamptz DEFAULT now();
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS processed    boolean DEFAULT false;
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS needs_review boolean DEFAULT false;
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS parse_error  text;
ALTER TABLE market_signals_raw       ADD COLUMN IF NOT EXISTS created_at   timestamptz DEFAULT now();

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

-- Defensive ADD COLUMN for tables that may pre-exist
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS signal_id           uuid;
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS lead_id             uuid;
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS client_id           uuid;
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS campaign_name       text;
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS outreach_multiplier numeric(4,2);
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS decision_type       text;
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS applied_at          timestamptz DEFAULT now();
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS outreach_id         uuid;
ALTER TABLE signal_routing_log ADD COLUMN IF NOT EXISTS metadata            jsonb DEFAULT '{}'::jsonb;

DO $$ BEGIN
  ALTER TABLE signal_routing_log
    ADD CONSTRAINT srl_decision_check
    CHECK (decision_type IS NULL OR decision_type IN ('scale_up','scale_down','message_swap','channel_boost','skip'));
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

-- Defensive ADD COLUMN for tables that may pre-exist
ALTER TABLE client_signal_preferences ADD COLUMN IF NOT EXISTS client_id                  uuid;
ALTER TABLE client_signal_preferences ADD COLUMN IF NOT EXISTS signal_type                text;
ALTER TABLE client_signal_preferences ADD COLUMN IF NOT EXISTS enabled                    boolean DEFAULT true;
ALTER TABLE client_signal_preferences ADD COLUMN IF NOT EXISTS custom_outreach_multiplier numeric(4,2);
ALTER TABLE client_signal_preferences ADD COLUMN IF NOT EXISTS custom_messaging_overlay   text;
ALTER TABLE client_signal_preferences ADD COLUMN IF NOT EXISTS created_at                 timestamptz DEFAULT now();
ALTER TABLE client_signal_preferences ADD COLUMN IF NOT EXISTS updated_at                 timestamptz DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_csp_client
  ON client_signal_preferences(client_id, enabled);

-- ══════════════════════════════════════════════════════════════════
-- Convenience view: active signals (not decayed, not needs_review) ──
-- ══════════════════════════════════════════════════════════════════
DROP VIEW IF EXISTS v_active_market_signals;
CREATE VIEW v_active_market_signals AS
SELECT
  msp.*,
  EXTRACT(EPOCH FROM (now() - msp.created_at)) / 3600 AS age_hours
FROM market_signals_processed msp
WHERE msp.needs_review = false
  AND msp.active = true
  AND now() < msp.expires_at
ORDER BY msp.created_at DESC;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP VIEW  IF EXISTS v_active_market_signals;
-- DROP TABLE IF EXISTS client_signal_preferences;
-- DROP TABLE IF EXISTS signal_routing_log;
-- DROP TABLE IF EXISTS market_signals_processed;
-- DROP TABLE IF EXISTS market_signals_raw;
