-- ══════════════════════════════════════════════════════════════════
-- Sentinel Foundation Schema (Layer 1 — universal platform guardian)
-- ══════════════════════════════════════════════════════════════════
-- Phase 1 (now): cost monitoring + circuit breakers.
-- Phases 2–5 (future): health monitoring, security detection, auto-
-- remediation, standalone product. Schema is modular: each phase adds
-- its own sentinel_<module>_* tables without touching the foundation.
--
-- LAYER 1 PURITY:
--   - No vertical_id. Sentinel is infrastructure, not vertical logic.
--   - No insurance / mga / advisor terminology.
--
-- Additive, idempotent. Rollback block at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- FOUNDATION (universal — used by every phase)
-- ─────────────────────────────────────────────────────────────────

-- 1. sentinel_modules — registry of every Sentinel capability
CREATE TABLE IF NOT EXISTS sentinel_modules (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_name     text UNIQUE NOT NULL,
  module_type     text NOT NULL,            -- monitoring | action | reporting
  description     text,
  status          text DEFAULT 'active',     -- active | disabled | planned
  created_at      timestamptz DEFAULT now()
);

INSERT INTO sentinel_modules (module_name, module_type, description, status) VALUES
  ('cost_monitoring',     'monitoring', 'Tracks cloud spend across services',     'active'),
  ('health_monitoring',   'monitoring', 'Platform health (Phase 2)',              'planned'),
  ('security_monitoring', 'monitoring', 'Security threats (Phase 3)',             'planned'),
  ('auto_remediation',    'action',     'Autonomous fixes (Phase 4)',             'planned')
ON CONFLICT (module_name) DO NOTHING;

-- 2. sentinel_alerts — every alert from every module
CREATE TABLE IF NOT EXISTS sentinel_alerts (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_name         text NOT NULL,                          -- which module raised it
  alert_type          text NOT NULL,                          -- cost_threshold | cost_anomaly | health_down | security_breach | etc.
  severity            text NOT NULL,                          -- info | warning | critical | emergency
  title               text NOT NULL,
  message             text,
  details             jsonb DEFAULT '{}'::jsonb,
  status              text NOT NULL DEFAULT 'open',           -- open | acknowledged | resolved | suppressed
  triggered_at        timestamptz DEFAULT now(),
  acknowledged_at     timestamptz,
  acknowledged_by     uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  resolved_at         timestamptz,
  resolution_notes    text,
  aggregation_key     text                                    -- for dedup; alerts with same key in same hour merge
);

DO $$ BEGIN
  ALTER TABLE sentinel_alerts
    ADD CONSTRAINT sa_severity_check
    CHECK (severity IN ('info','warning','critical','emergency'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE sentinel_alerts
    ADD CONSTRAINT sa_status_check
    CHECK (status IN ('open','acknowledged','resolved','suppressed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_sentinel_alerts_open
  ON sentinel_alerts(severity, triggered_at DESC)
  WHERE status = 'open';

CREATE INDEX IF NOT EXISTS idx_sentinel_alerts_aggregation
  ON sentinel_alerts(aggregation_key, triggered_at DESC)
  WHERE aggregation_key IS NOT NULL;

-- 3. sentinel_actions — every action Sentinel takes (or proposes)
CREATE TABLE IF NOT EXISTS sentinel_actions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_name         text NOT NULL,
  action_type         text NOT NULL,                          -- pause_workflow | resume_workflow | rotate_credential | restart_service | etc.
  target_resource     text,                                   -- workflow_id | service_name | etc.
  action_data         jsonb DEFAULT '{}'::jsonb,
  triggered_by        text,                                   -- 'auto' | 'human:<user_id>' | 'cron:<workflow>'
  status              text NOT NULL DEFAULT 'pending',        -- pending | executing | succeeded | failed | rolled_back
  executed_at         timestamptz,
  result_data         jsonb,
  human_approved      boolean DEFAULT false,
  approved_by         uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  approved_at         timestamptz,
  created_at          timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_actions
    ADD CONSTRAINT sact_status_check
    CHECK (status IN ('pending','executing','succeeded','failed','rolled_back'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_sentinel_actions_recent
  ON sentinel_actions(module_name, created_at DESC);

-- ─────────────────────────────────────────────────────────────────
-- PHASE 1 — COST MONITORING
-- ─────────────────────────────────────────────────────────────────

-- 4. sentinel_cost_tracking — daily spend by service
CREATE TABLE IF NOT EXISTS sentinel_cost_tracking (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tracking_date       date NOT NULL,
  service_name        text NOT NULL,                          -- anthropic | openai | twilio | vapi | heygen | supabase | cloudflare | postmark | stripe
  spend_cents         bigint NOT NULL DEFAULT 0,
  usage_metrics       jsonb DEFAULT '{}'::jsonb,              -- { tokens, requests, minutes, gb, ... } service-specific
  data_source         text NOT NULL DEFAULT 'internal_log',   -- internal_log | vendor_api | manual
  notes               text,
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now(),
  UNIQUE (tracking_date, service_name)
);

DO $$ BEGIN
  ALTER TABLE sentinel_cost_tracking
    ADD CONSTRAINT sct_source_check
    CHECK (data_source IN ('internal_log','vendor_api','manual'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_sct_date_desc
  ON sentinel_cost_tracking(tracking_date DESC, service_name);

-- 5. sentinel_cost_budgets — per-service budget definitions + threshold rules
CREATE TABLE IF NOT EXISTS sentinel_cost_budgets (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name             text UNIQUE NOT NULL,
  monthly_limit_cents      bigint NOT NULL,
  daily_limit_cents        bigint,                             -- optional rolling daily cap
  warning_pct              integer DEFAULT 50,                 -- % of monthly that triggers a warning alert
  critical_pct             integer DEFAULT 75,                 -- % that triggers a critical alert
  auto_pause_pct           integer DEFAULT 90,                 -- % that auto-pauses non-essential workflows
  active                   boolean DEFAULT true,
  notes                    text,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_cost_budgets
    ADD CONSTRAINT scb_pct_order_check
    CHECK (warning_pct < critical_pct AND critical_pct < auto_pause_pct);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Seed defaults per founder spec. Includes daily_limit_cents + a total_platform
-- aggregate row that the threshold-check workflow handles specially (sums all
-- per-service spend against the total row). Mary tunes after baseline established.
INSERT INTO sentinel_cost_budgets (service_name, monthly_limit_cents, daily_limit_cents, warning_pct, critical_pct, auto_pause_pct, notes) VALUES
  ('anthropic',        20000,  1000,  50,  75,  90, 'Claude API ($200/mo cap).'),
  ('openai',           10000,   500,  50,  75,  90, 'Whisper transcription ($100/mo cap).'),
  ('twilio',           10000,   500,  50,  75,  90, 'SMS + WhatsApp + Voice ($100/mo cap).'),
  ('vapi',             20000,  1000,  50,  75,  90, 'AI voice calls ($200/mo cap).'),
  ('heygen',            3000,   200,  75,  90, 100, 'Video renders ($30/mo cap — base plan).'),
  ('supabase',          2500,   100,  50,  75,  90, 'Database + storage ($25/mo Pro plan).'),
  ('postmark',          1500,   100,  50,  75, 100, 'Email ($15/mo).'),
  ('total_platform',  100000,  5000,  50,  75,  90, 'Aggregate cap across all services. Threshold check sums all per-service spend against this row.')
ON CONFLICT (service_name) DO NOTHING;

-- 6. sentinel_workflow_breakers — circuit-breaker state per workflow
CREATE TABLE IF NOT EXISTS sentinel_workflow_breakers (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id              text UNIQUE NOT NULL,               -- n8n workflow id
  workflow_name            text,
  max_iterations           integer DEFAULT 1000,               -- max executions/day before tripping
  max_daily_cost_cents     bigint,                             -- optional cost-based trip
  current_status           text DEFAULT 'active',              -- active | tripped | paused | quarantined
  paused_at                timestamptz,
  paused_reason            text,
  total_executions_today   integer DEFAULT 0,
  total_cost_today_cents   bigint DEFAULT 0,
  reset_at                 timestamptz,                        -- when the daily counter was last reset
  is_essential             boolean DEFAULT false,              -- essential workflows are never auto-paused (eg auth)
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_workflow_breakers
    ADD CONSTRAINT swb_status_check
    CHECK (current_status IN ('active','tripped','paused','quarantined'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_swb_paused
  ON sentinel_workflow_breakers(paused_at DESC)
  WHERE current_status IN ('tripped','paused','quarantined');

-- ─────────────────────────────────────────────────────────────────
-- RPC: trip_workflow_breaker — atomic pause + alert record
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION trip_workflow_breaker(
  p_workflow_id   text,
  p_reason        text,
  p_triggered_by  text DEFAULT 'auto'
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_alert_id    uuid;
  v_action_id   uuid;
BEGIN
  UPDATE sentinel_workflow_breakers
     SET current_status = 'paused',
         paused_at      = now(),
         paused_reason  = p_reason,
         updated_at     = now()
   WHERE workflow_id = p_workflow_id
     AND is_essential = false;

  IF NOT FOUND THEN RETURN NULL; END IF;

  INSERT INTO sentinel_actions (module_name, action_type, target_resource, action_data, triggered_by, status, executed_at)
       VALUES ('cost_monitoring','pause_workflow', p_workflow_id, jsonb_build_object('reason', p_reason),
               p_triggered_by, 'succeeded', now())
    RETURNING id INTO v_action_id;

  INSERT INTO sentinel_alerts (module_name, alert_type, severity, title, message, details, aggregation_key)
       VALUES ('cost_monitoring','circuit_breaker_tripped','warning',
               'Workflow paused by Sentinel: ' || p_workflow_id,
               p_reason,
               jsonb_build_object('workflow_id', p_workflow_id, 'action_id', v_action_id),
               'breaker:' || p_workflow_id)
    RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS trip_workflow_breaker(text, text, text);
-- DROP TABLE IF EXISTS sentinel_workflow_breakers;
-- DROP TABLE IF EXISTS sentinel_cost_budgets;
-- DROP TABLE IF EXISTS sentinel_cost_tracking;
-- DROP TABLE IF EXISTS sentinel_actions;
-- DROP TABLE IF EXISTS sentinel_alerts;
-- DROP TABLE IF EXISTS sentinel_modules;
