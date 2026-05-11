-- ══════════════════════════════════════════════════════════════════
-- F3 Universal KPI / Goals Framework (Layer 1 — core engine)
-- ══════════════════════════════════════════════════════════════════
-- Closes the F3 gap surfaced by docs/audit/2026-05-11-feature-audit.md.
-- Provides per-user goal targets, achievement tracking, performance
-- snapshots that any vertical's dashboard can render.
--
-- LAYER 1 PURITY:
--   - No vertical_id column.
--   - No insurance / mga / advisor terminology.
--   - 'role' column is freeform text — verticals supply their own role
--     vocabulary (advisor, sub_agent, sales_rep, consultant, etc.).
--
-- Additive, idempotent. Rollback block commented at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. goal_templates — per-client, per-role goal definitions
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS goal_templates (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id           uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  template_name       text NOT NULL,
  role                text,                                 -- target role (text, no enum)
  metric              text NOT NULL,                        -- calls_made | meetings_booked | policies_sold | revenue_cents | conversion_rate | response_time_min | custom
  period              text NOT NULL,                        -- daily | weekly | monthly | quarterly | annual
  target_value        numeric,
  target_value_cents  bigint,                               -- used when metric ends with _cents
  description         text,
  active              boolean DEFAULT true,
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now(),
  UNIQUE (client_id, template_name)
);

DO $$ BEGIN
  ALTER TABLE goal_templates
    ADD CONSTRAINT gt_period_check
    CHECK (period IN ('daily','weekly','monthly','quarterly','annual'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_gt_client_active
  ON goal_templates(client_id)
  WHERE active = true;

-- ─────────────────────────────────────────────────────────────────
-- 2. user_goals — instantiated targets per user per period
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS user_goals (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES team_members(id) ON DELETE CASCADE,
  template_id              uuid NOT NULL REFERENCES goal_templates(id),
  period_start             date NOT NULL,
  period_end               date NOT NULL,
  target_value             numeric NOT NULL,
  current_value            numeric DEFAULT 0,
  achievement_percentage   numeric(7,2) GENERATED ALWAYS AS (
                             CASE WHEN target_value > 0
                                  THEN (current_value * 100.0 / target_value)
                                  ELSE 0 END
                           ) STORED,
  status                   text NOT NULL DEFAULT 'in_progress',
  last_updated             timestamptz DEFAULT now(),
  created_at               timestamptz DEFAULT now(),
  UNIQUE (user_id, template_id, period_start)
);

DO $$ BEGIN
  ALTER TABLE user_goals
    ADD CONSTRAINT ug_status_check
    CHECK (status IN ('in_progress','achieved','missed','abandoned'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ug_user_active
  ON user_goals(user_id, period_end DESC)
  WHERE status = 'in_progress';

CREATE INDEX IF NOT EXISTS idx_ug_template_period
  ON user_goals(template_id, period_start);

-- ─────────────────────────────────────────────────────────────────
-- 3. performance_snapshots — periodic materialized rollups
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS performance_snapshots (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES team_members(id) ON DELETE CASCADE,
  snapshot_date       date NOT NULL,
  snapshot_period     text NOT NULL,                       -- weekly | monthly | quarterly | annual
  metrics             jsonb NOT NULL DEFAULT '{}'::jsonb,  -- { metric_name: { current, target, achievement_pct } }
  rank_within_team    integer,
  trend               text DEFAULT 'stable',               -- improving | stable | declining
  created_at          timestamptz DEFAULT now(),
  UNIQUE (user_id, snapshot_date, snapshot_period)
);

DO $$ BEGIN
  ALTER TABLE performance_snapshots
    ADD CONSTRAINT ps_period_check
    CHECK (snapshot_period IN ('weekly','monthly','quarterly','annual'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE performance_snapshots
    ADD CONSTRAINT ps_trend_check
    CHECK (trend IN ('improving','stable','declining'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ps_user_date
  ON performance_snapshots(user_id, snapshot_date DESC);

-- ─────────────────────────────────────────────────────────────────
-- 4. RPC: upsert_user_goal_progress — used by aggregator workflow
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION upsert_user_goal_progress(
  p_user_goal_id   uuid,
  p_current_value  numeric
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_target  numeric;
BEGIN
  UPDATE user_goals
     SET current_value = p_current_value,
         last_updated  = now(),
         status        = CASE
                           WHEN p_current_value >= target_value THEN 'achieved'
                           WHEN period_end < current_date AND p_current_value < target_value THEN 'missed'
                           ELSE status
                         END
   WHERE id = p_user_goal_id;
  RETURN FOUND;
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 5. RPC: recompute_goal_progress — derive current_value from
--    universal source tables and update the user_goals row.
-- ─────────────────────────────────────────────────────────────────
-- Supported metrics (Layer 1 only — universal counts):
--   meetings_booked  → bookings table
--   calls_made       → messages_sent where channel='call'
--   emails_sent      → messages_sent where channel='email'
--   sms_sent         → messages_sent where channel='sms'
--   leads_assigned   → lead_assignments
--   revenue_cents    → bookings.fee_per_booking (sum)
-- Unknown metrics: returns false (caller responsible for vertical-
-- specific aggregation).
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION recompute_goal_progress(
  p_user_goal_id   uuid
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_ug          user_goals%ROWTYPE;
  v_tpl         goal_templates%ROWTYPE;
  v_current     numeric := 0;
BEGIN
  SELECT * INTO v_ug FROM user_goals WHERE id = p_user_goal_id;
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT * INTO v_tpl FROM goal_templates WHERE id = v_ug.template_id;
  IF NOT FOUND THEN RETURN false; END IF;

  IF v_tpl.metric = 'meetings_booked' THEN
    SELECT COUNT(*)::numeric INTO v_current
      FROM bookings
     WHERE assigned_advisor_id = v_ug.user_id
       AND created_at::date BETWEEN v_ug.period_start AND v_ug.period_end;

  ELSIF v_tpl.metric IN ('calls_made','emails_sent','sms_sent') THEN
    SELECT COUNT(*)::numeric INTO v_current
      FROM messages_sent
     WHERE from_user_id = v_ug.user_id
       AND channel = CASE v_tpl.metric WHEN 'calls_made' THEN 'call'
                                       WHEN 'emails_sent' THEN 'email'
                                       WHEN 'sms_sent'   THEN 'sms' END
       AND sent_at::date BETWEEN v_ug.period_start AND v_ug.period_end;

  ELSIF v_tpl.metric = 'leads_assigned' THEN
    SELECT COUNT(*)::numeric INTO v_current
      FROM lead_assignments
     WHERE assigned_user_id = v_ug.user_id
       AND assigned_at::date BETWEEN v_ug.period_start AND v_ug.period_end
       AND assignment_method <> 'reshuffle';

  ELSIF v_tpl.metric = 'revenue_cents' THEN
    SELECT COALESCE(SUM(fee_per_booking_cents), 0)::numeric INTO v_current
      FROM bookings
     WHERE assigned_advisor_id = v_ug.user_id
       AND created_at::date BETWEEN v_ug.period_start AND v_ug.period_end;

  ELSE
    -- Unknown metric — caller (or a vertical-specific workflow) is
    -- responsible for setting current_value directly.
    RETURN false;
  END IF;

  PERFORM upsert_user_goal_progress(p_user_goal_id, v_current);
  RETURN true;
END;
$$;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented — uncomment to revert)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS recompute_goal_progress(uuid);
-- DROP FUNCTION IF EXISTS upsert_user_goal_progress(uuid, numeric);
-- DROP TABLE IF EXISTS performance_snapshots;
-- DROP TABLE IF EXISTS user_goals;
-- DROP TABLE IF EXISTS goal_templates;
