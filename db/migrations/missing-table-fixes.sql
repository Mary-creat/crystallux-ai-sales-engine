-- ══════════════════════════════════════════════════════════════════
-- Missing-Table Consolidation (Layer 1 — core engine)
-- ══════════════════════════════════════════════════════════════════
-- Background:
-- The 2026-05-11 feature-completeness audit flagged four tables
-- (closing_scripts, agent_daily_plans, agent_daily_summary,
-- agent_calendar_prefs) as referenced by universal workflows but
-- not declared in db/migrations/. The audit only scanned that one
-- folder.
--
-- Reality: all four ARE defined — in docs/architecture/migrations/
-- (the parallel pre-scale-sprint migrations folder), but were never
-- moved into the canonical db/migrations/ location. The table called
-- "agent_daily_plans" by the audit is actually named "daily_task_plan"
-- in the legacy schema (the RPC upsert_daily_plan writes to it).
--
-- This file consolidates those table definitions into db/migrations/
-- so the canonical location is complete. CREATE TABLE IF NOT EXISTS
-- means this file is safe to apply whether or not the legacy
-- migrations were applied — it is a no-op if they were.
--
-- Source-of-truth legacy migrations:
--   - docs/architecture/migrations/2026-04-18-closing-intelligence.sql
--   - docs/architecture/migrations/2026-04-24-calendar-restructuring.sql
--   - docs/architecture/migrations/2026-04-24-morning-priority-ordering.sql
--   - docs/architecture/migrations/2026-04-25-productivity-client-facing.sql
--
-- LAYER 1 PURITY: All tables here are universal. niche_name is
-- freeform (vertical supplies its own niche label).
--
-- Additive, idempotent. No rollback (these tables underpin §29-§34
-- functionality already in use).
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. closing_scripts (originally in 2026-04-18-closing-intelligence.sql)
-- ─────────────────────────────────────────────────────────────────
-- Used by: clx-script-matcher-v1, clx-realtime-script-suggester-v1,
-- clx-script-learning-loop-v1.
-- RPC dependents (defined in legacy migrations): match_script_to_state,
-- get_scripts_for_lead.

CREATE TABLE IF NOT EXISTS closing_scripts (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  niche_name          text NOT NULL,
  close_type          text NOT NULL,                   -- assumptive | urgency | choice | summary | risk_reversal | testimonial
  trigger_condition   text,
  script_text         text NOT NULL,
  expected_response   text,
  follow_up_action    text,
  fallback_action     text,
  is_active           boolean DEFAULT true,
  created_at          timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_closing_scripts_niche
  ON closing_scripts(niche_name, close_type)
  WHERE is_active = true;

-- ─────────────────────────────────────────────────────────────────
-- 2. agent_calendar_prefs (originally in 2026-04-24-calendar-restructuring.sql
-- and extended by 2026-04-24-morning-priority-ordering.sql)
-- ─────────────────────────────────────────────────────────────────
-- Used by: clx-no-show-sms-recovery-v1 (template override, future
-- phase), clx-daily-plan-generator-v1 (focus block, daily cap).

CREATE TABLE IF NOT EXISTS agent_calendar_prefs (
  agent_id              uuid PRIMARY KEY,
  client_id             uuid REFERENCES clients(id) ON DELETE CASCADE,
  timezone              text DEFAULT 'America/Toronto',
  agent_name            text,
  agent_email           text,
  morning_focus_block   text DEFAULT 'replies_then_hot',  -- replies_then_hot | hot_then_replies | calls_first | custom
  daily_task_cap        integer DEFAULT 25,
  prefer_batch_similar  boolean DEFAULT true,
  reply_sla_hours       integer DEFAULT 4,
  hot_lead_threshold    integer DEFAULT 80,
  custom_order          jsonb DEFAULT '[]'::jsonb,
  notification_email    text,
  no_show_sms_template  text,                              -- per-agent override (referenced by recovery workflow comment)
  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE agent_calendar_prefs
    ADD CONSTRAINT agent_calendar_prefs_focus_check
    CHECK (morning_focus_block IN ('replies_then_hot','hot_then_replies','calls_first','custom'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Ensure columns exist even if a stub version of the table predates this file.
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS agent_name            text;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS agent_email           text;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS morning_focus_block   text DEFAULT 'replies_then_hot';
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS daily_task_cap        integer DEFAULT 25;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS prefer_batch_similar  boolean DEFAULT true;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS reply_sla_hours       integer DEFAULT 4;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS hot_lead_threshold    integer DEFAULT 80;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS custom_order          jsonb DEFAULT '[]'::jsonb;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS notification_email    text;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS no_show_sms_template  text;

-- ─────────────────────────────────────────────────────────────────
-- 3. daily_task_plan (originally in 2026-04-24-morning-priority-ordering.sql)
-- ─────────────────────────────────────────────────────────────────
-- NOTE: This is the table the audit referred to as "agent_daily_plans".
-- The actual schema name is daily_task_plan; the RPC upsert_daily_plan
-- writes here.
-- Used by: clx-daily-plan-generator-v1.

CREATE TABLE IF NOT EXISTS daily_task_plan (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id          uuid,
  client_id         uuid REFERENCES clients(id) ON DELETE CASCADE,
  plan_date         date NOT NULL,
  generated_at      timestamptz DEFAULT now(),
  generator_source  text,                                  -- rpc | claude | manual
  task_count        integer,
  tasks             jsonb NOT NULL DEFAULT '[]'::jsonb,
  summary_line      text,
  completed_counts  jsonb DEFAULT '{}'::jsonb,
  expires_at        timestamptz,
  UNIQUE(agent_id, client_id, plan_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_task_plan_agent_date
  ON daily_task_plan(agent_id, plan_date);
CREATE INDEX IF NOT EXISTS idx_daily_task_plan_client_date
  ON daily_task_plan(client_id, plan_date);

-- ─────────────────────────────────────────────────────────────────
-- 4. agent_daily_summary (originally in 2026-04-25-productivity-client-facing.sql)
-- ─────────────────────────────────────────────────────────────────
-- Used by: clx-daily-summary-generator-v1, clx-activity-tracker-v1,
-- clx-activity-classifier-v1.
-- RPC dependent: calculate_daily_summary (in legacy migration).

CREATE TABLE IF NOT EXISTS agent_daily_summary (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id               uuid NOT NULL,
  client_id              uuid REFERENCES clients(id) ON DELETE CASCADE,
  summary_date           date NOT NULL,
  total_minutes_tracked  integer DEFAULT 0,
  productive_minutes     integer DEFAULT 0,
  neutral_minutes        integer DEFAULT 0,
  unproductive_minutes   integer DEFAULT 0,
  productivity_score     numeric(5,2),
  calls_made             integer DEFAULT 0,
  emails_sent            integer DEFAULT 0,
  meetings_held          integer DEFAULT 0,
  follow_ups_sent        integer DEFAULT 0,
  leads_qualified        integer DEFAULT 0,
  deals_closed           integer DEFAULT 0,
  trend                  text DEFAULT 'insufficient_data',
  coaching_flags         jsonb DEFAULT '[]'::jsonb,
  generated_at           timestamptz DEFAULT now(),
  UNIQUE(agent_id, summary_date)
);

DO $$ BEGIN
  ALTER TABLE agent_daily_summary
    ADD CONSTRAINT agent_daily_summary_trend_check
    CHECK (trend IN ('improving','stable','declining','insufficient_data'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_summary_agent_date
  ON agent_daily_summary(agent_id, summary_date DESC);
CREATE INDEX IF NOT EXISTS idx_summary_client_date
  ON agent_daily_summary(client_id, summary_date DESC);

-- ══════════════════════════════════════════════════════════════════
-- Verification notes for Mary
-- ══════════════════════════════════════════════════════════════════
-- The dependent RPCs live in docs/architecture/migrations/:
--   upsert_daily_plan          → 2026-04-24-morning-priority-ordering.sql
--   compute_daily_tasks        → 2026-04-24-morning-priority-ordering.sql
--   record_task_completion     → 2026-04-24-morning-priority-ordering.sql
--   match_script_to_state      → 2026-04-25-realtime-script-suggestions.sql
--   get_scripts_for_lead       → (closing-intelligence migrations)
--   calculate_daily_summary    → 2026-04-25-productivity-client-facing.sql
--   record_agent_activity      → 2026-04-25-productivity-client-facing.sql
--   classify_activity_heuristic→ 2026-04-25-productivity-client-facing.sql
--   record_route_optimization  → 2026-04-24-geographic-optimization.sql
--   update_appointment_geocode → 2026-04-24-geographic-optimization.sql
--   get_daily_geo_appointments → 2026-04-24-geographic-optimization.sql
--
-- If these RPCs are missing from production Supabase, apply the
-- listed legacy migration. To check, run:
--   SELECT proname FROM pg_proc WHERE proname IN
--     ('upsert_daily_plan','match_script_to_state','get_scripts_for_lead',
--      'calculate_daily_summary','record_agent_activity',
--      'classify_activity_heuristic','record_route_optimization',
--      'update_appointment_geocode','get_daily_geo_appointments');
