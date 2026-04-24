-- ══════════════════════════════════════════════════════════════════
-- Morning Priority Task Ordering (B.12a-3)
-- ══════════════════════════════════════════════════════════════════
-- Agents (Mary + future reps) open the dashboard and get an ordered
-- list of what to do next: replies → hot leads → no-show rebooks →
-- discovery calls → follow-ups. The ordering respects per-agent
-- preferences (timezone, morning-vs-afternoon block) plus a shared
-- scoring heuristic that weights lead_score, recency, and SLA age.
--
-- Additive only. Extends `agent_calendar_prefs` (created by the
-- calendar-restructuring migration). Creates `daily_task_plan` as
-- a materialised per-day plan so the Claude generator is called
-- once per morning, not per panel render.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. Extend agent_calendar_prefs with task-ordering preferences
-- ─────────────────────────────────────────────────────────────────
-- If the calendar-restructuring migration has not run yet, create
-- a stub so this file is independently applicable (idempotent).

CREATE TABLE IF NOT EXISTS agent_calendar_prefs (
  agent_id       uuid PRIMARY KEY,
  client_id      uuid REFERENCES clients(id) ON DELETE CASCADE,
  timezone       text DEFAULT 'America/Toronto',
  created_at     timestamptz DEFAULT now(),
  updated_at     timestamptz DEFAULT now()
);

ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS agent_name               text;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS agent_email              text;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS morning_focus_block      text
  DEFAULT 'replies_then_hot';
  -- values: 'replies_then_hot' | 'hot_then_replies' | 'calls_first' | 'custom'
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS daily_task_cap           integer DEFAULT 25;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS prefer_batch_similar     boolean DEFAULT true;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS reply_sla_hours          integer DEFAULT 4;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS hot_lead_threshold       integer DEFAULT 80;
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS custom_order             jsonb DEFAULT '[]'::jsonb;
  -- [{ task_category, weight }] — only used when morning_focus_block='custom'
ALTER TABLE agent_calendar_prefs ADD COLUMN IF NOT EXISTS notification_email       text;

DO $$ BEGIN
  ALTER TABLE agent_calendar_prefs
    ADD CONSTRAINT agent_calendar_prefs_focus_check
    CHECK (morning_focus_block IN ('replies_then_hot','hot_then_replies','calls_first','custom'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 2. daily_task_plan — one row per agent per day
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS daily_task_plan (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id          uuid,
  client_id         uuid REFERENCES clients(id) ON DELETE CASCADE,
  plan_date         date NOT NULL,
  generated_at      timestamptz DEFAULT now(),
  generator_source  text,                            -- 'rpc' | 'claude' | 'manual'
  task_count        integer,
  tasks             jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- tasks shape: [{ rank, category, lead_id|appointment_id, label, due_by,
  --                 score, reason, sla_breached (bool) }]
  summary_line      text,
  completed_counts  jsonb DEFAULT '{}'::jsonb,      -- { replies: 3, hot_leads: 2, ... }
  expires_at        timestamptz,
  UNIQUE(agent_id, client_id, plan_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_task_plan_agent_date
  ON daily_task_plan(agent_id, plan_date);
CREATE INDEX IF NOT EXISTS idx_daily_task_plan_client_date
  ON daily_task_plan(client_id, plan_date);

-- ─────────────────────────────────────────────────────────────────
-- 3. task_completion_log — agent marks items done
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS task_completion_log (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id           uuid REFERENCES daily_task_plan(id) ON DELETE CASCADE,
  agent_id          uuid,
  task_rank         integer,
  task_category     text,
  lead_id           uuid REFERENCES leads(id) ON DELETE SET NULL,
  appointment_id    uuid,
  completed_at      timestamptz DEFAULT now(),
  outcome           text,                            -- 'done' | 'skipped' | 'deferred'
  notes             text
);

DO $$ BEGIN
  ALTER TABLE task_completion_log
    ADD CONSTRAINT task_completion_log_outcome_check
    CHECK (outcome IS NULL OR outcome IN ('done','skipped','deferred'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_task_completion_plan ON task_completion_log(plan_id);
CREATE INDEX IF NOT EXISTS idx_task_completion_agent_date ON task_completion_log(agent_id, completed_at);

-- ─────────────────────────────────────────────────────────────────
-- 4. RLS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE daily_task_plan        ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_completion_log    ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY daily_task_plan_service_role_all ON daily_task_plan
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY task_completion_log_service_role_all ON task_completion_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 5. RPCs
-- ─────────────────────────────────────────────────────────────────

-- 5.1 Compute the raw-ranked task list for a client (the heuristic
-- baseline; Claude can re-rank on top of this via the generator
-- workflow). Returns an ordered list across five categories.
CREATE OR REPLACE FUNCTION compute_daily_tasks(
  p_client_id uuid,
  p_limit     integer DEFAULT 25
)
RETURNS TABLE(
  rank          integer,
  category      text,
  lead_id       uuid,
  appointment_id uuid,
  label         text,
  score         numeric,
  due_by        timestamptz,
  sla_breached  boolean,
  reason        text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_hot_threshold integer;
  v_sla_hours     integer;
BEGIN
  -- Defaults; per-agent overrides kick in once a Claude plan is generated.
  v_hot_threshold := 80;
  v_sla_hours     := 4;

  RETURN QUERY
    WITH base AS (
      -- Category 1: unreplied inbound replies past SLA (category_weight 100)
      SELECT
        1::integer             AS cat_idx,
        'reply'::text          AS category,
        l.id                   AS lead_id,
        NULL::uuid             AS appointment_id,
        ('Reply from ' || COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,''))::text AS label,
        (100 + COALESCE(l.lead_score, 0) +
          CASE WHEN l.last_reply_at < now() - (v_sla_hours * interval '1 hour')
               THEN 20 ELSE 0 END
        )::numeric             AS score,
        (l.last_reply_at + (v_sla_hours * interval '1 hour')) AS due_by,
        (l.last_reply_at < now() - (v_sla_hours * interval '1 hour')) AS sla_breached,
        ('Inbound reply ' ||
          CASE WHEN l.last_reply_at < now() - (v_sla_hours * interval '1 hour')
               THEN 'SLA BREACHED' ELSE 'within SLA' END)::text AS reason
      FROM leads l
      WHERE l.client_id = p_client_id
        AND l.reply_received = true
        AND (l.reply_handled IS NULL OR l.reply_handled = false)
        AND COALESCE(l.do_not_contact, false) = false

      UNION ALL

      -- Category 2: hot leads awaiting outreach (score >= threshold, not contacted today)
      SELECT
        2::integer, 'hot_lead'::text,
        l.id, NULL::uuid,
        ('Hot lead (' || COALESCE(l.lead_score::text,'?') || '): ' ||
          COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,'') ||
          CASE WHEN l.company IS NOT NULL THEN ' · ' || l.company ELSE '' END)::text,
        (70 + COALESCE(l.lead_score, 0))::numeric,
        (now() + interval '2 hours'),
        false,
        ('score=' || l.lead_score || ' · status=' || COALESCE(l.lead_status,'?'))::text
      FROM leads l
      WHERE l.client_id = p_client_id
        AND COALESCE(l.lead_score, 0) >= v_hot_threshold
        AND COALESCE(l.do_not_contact, false) = false
        AND (l.outreach_sent_at IS NULL OR l.outreach_sent_at::date < CURRENT_DATE)
        AND COALESCE(l.reply_received, false) = false

      UNION ALL

      -- Category 3: no-show rebooks (no recovery SMS yet, or no rebook yet)
      SELECT
        3::integer, 'no_show_rebook'::text,
        a.lead_id, a.id,
        ('Rebook no-show: ' || COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,''))::text,
        (60 + COALESCE(l.lead_score, 0))::numeric,
        (a.scheduled_end + interval '24 hours'),
        (a.scheduled_end < now() - interval '24 hours'),
        ('no-show on ' || to_char(a.scheduled_start,'YYYY-MM-DD HH24:MI'))::text
      FROM appointment_log a
      JOIN leads l ON l.id = a.lead_id
      WHERE a.client_id = p_client_id
        AND a.no_show_flag = true
        AND a.rebooked_at IS NULL
        AND COALESCE(l.do_not_contact, false) = false

      UNION ALL

      -- Category 4: upcoming discovery / closing calls in next 24h
      SELECT
        4::integer, 'upcoming_call'::text,
        a.lead_id, a.id,
        ('Upcoming ' || COALESCE(a.appointment_type,'call') || ': ' ||
          COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,''))::text,
        (50 + COALESCE(l.lead_score, 0))::numeric,
        a.scheduled_start,
        false,
        ('at ' || to_char(a.scheduled_start,'HH24:MI'))::text
      FROM appointment_log a
      JOIN leads l ON l.id = a.lead_id
      WHERE a.client_id = p_client_id
        AND a.outcome IS NULL
        AND a.scheduled_start BETWEEN now() AND now() + interval '24 hours'

      UNION ALL

      -- Category 5: due follow-ups (sent outreach, no reply, >= 3 days ago)
      SELECT
        5::integer, 'follow_up'::text,
        l.id, NULL::uuid,
        ('Follow-up: ' || COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,''))::text,
        (30 + COALESCE(l.lead_score, 0))::numeric,
        (l.outreach_sent_at + interval '5 days'),
        (l.outreach_sent_at < now() - interval '5 days'),
        ('no reply since ' || to_char(l.outreach_sent_at,'YYYY-MM-DD'))::text
      FROM leads l
      WHERE l.client_id = p_client_id
        AND l.outreach_sent_at IS NOT NULL
        AND COALESCE(l.reply_received, false) = false
        AND l.outreach_sent_at < now() - interval '3 days'
        AND COALESCE(l.do_not_contact, false) = false
    )
    SELECT  row_number() OVER (ORDER BY score DESC, cat_idx ASC)::integer,
            category, lead_id, appointment_id, label, score, due_by,
            sla_breached, reason
      FROM  base
     ORDER BY score DESC, cat_idx ASC
     LIMIT  p_limit;
END;
$$;

REVOKE ALL ON FUNCTION compute_daily_tasks(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION compute_daily_tasks(uuid, integer) TO service_role;

-- 5.2 Upsert a daily plan row (used by the generator workflow after
-- Claude re-ranks). Idempotent on (agent_id, client_id, plan_date).
CREATE OR REPLACE FUNCTION upsert_daily_plan(
  p_agent_id         uuid,
  p_client_id        uuid,
  p_plan_date        date,
  p_tasks            jsonb,
  p_summary_line     text,
  p_generator_source text DEFAULT 'rpc'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO daily_task_plan (
    agent_id, client_id, plan_date, generator_source, task_count,
    tasks, summary_line, expires_at
  )
  VALUES (
    p_agent_id, p_client_id, p_plan_date, p_generator_source,
    COALESCE(jsonb_array_length(p_tasks), 0),
    COALESCE(p_tasks, '[]'::jsonb),
    p_summary_line,
    (p_plan_date + interval '1 day')
  )
  ON CONFLICT (agent_id, client_id, plan_date) DO UPDATE SET
    generator_source = EXCLUDED.generator_source,
    task_count       = EXCLUDED.task_count,
    tasks            = EXCLUDED.tasks,
    summary_line     = EXCLUDED.summary_line,
    generated_at     = now()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION upsert_daily_plan(uuid, uuid, date, jsonb, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION upsert_daily_plan(uuid, uuid, date, jsonb, text, text) TO service_role;

-- 5.3 Record a task completion (called from dashboard checkbox or
-- from any workflow that knows a task just finished).
CREATE OR REPLACE FUNCTION record_task_completion(
  p_plan_id        uuid,
  p_agent_id       uuid,
  p_task_rank      integer,
  p_task_category  text,
  p_lead_id        uuid,
  p_appointment_id uuid,
  p_outcome        text DEFAULT 'done',
  p_notes          text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO task_completion_log (
    plan_id, agent_id, task_rank, task_category,
    lead_id, appointment_id, outcome, notes
  )
  VALUES (
    p_plan_id, p_agent_id, p_task_rank, p_task_category,
    p_lead_id, p_appointment_id, COALESCE(p_outcome,'done'), p_notes
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION record_task_completion(uuid, uuid, integer, text, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION record_task_completion(uuid, uuid, integer, text, uuid, uuid, text, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 6. scan_errors seeds
-- ─────────────────────────────────────────────────────────────────

INSERT INTO scan_errors (error_code, severity, category, description, suggested_action, created_at)
SELECT 'DAILY_PLAN_GENERATION_FAILED', 'warning', 'tasks',
       'Claude call failed while generating a morning task plan.',
       'Plan falls back to compute_daily_tasks heuristic order.', now()
WHERE NOT EXISTS (SELECT 1 FROM scan_errors WHERE error_code='DAILY_PLAN_GENERATION_FAILED');

INSERT INTO scan_errors (error_code, severity, category, description, suggested_action, created_at)
SELECT 'TASK_CLASSIFIER_SKIPPED', 'info', 'tasks',
       'Lead was enqueued to clx-task-classifier-v1 but no category resolved.',
       'Inspect lead fields; may be missing first_name or lead_score.', now()
WHERE NOT EXISTS (SELECT 1 FROM scan_errors WHERE error_code='TASK_CLASSIFIER_SKIPPED');

-- ─────────────────────────────────────────────────────────────────
-- 7. Verification queries
-- ─────────────────────────────────────────────────────────────────
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='agent_calendar_prefs' AND column_name IN (
--     'morning_focus_block','daily_task_cap','hot_lead_threshold','custom_order'
--   );
-- SELECT proname FROM pg_proc
--   WHERE proname IN ('compute_daily_tasks','upsert_daily_plan','record_task_completion');
-- SELECT * FROM compute_daily_tasks('<client-uuid>', 10);

-- ─────────────────────────────────────────────────────────────────
-- 8. ROLLBACK (uncomment + run if you need to revert)
-- ─────────────────────────────────────────────────────────────────
-- DROP FUNCTION IF EXISTS record_task_completion(uuid, uuid, integer, text, uuid, uuid, text, text);
-- DROP FUNCTION IF EXISTS upsert_daily_plan(uuid, uuid, date, jsonb, text, text);
-- DROP FUNCTION IF EXISTS compute_daily_tasks(uuid, integer);
-- DROP TABLE IF EXISTS task_completion_log;
-- DROP TABLE IF EXISTS daily_task_plan;
-- ALTER TABLE agent_calendar_prefs
--   DROP COLUMN IF EXISTS agent_name,
--   DROP COLUMN IF EXISTS agent_email,
--   DROP COLUMN IF EXISTS morning_focus_block,
--   DROP COLUMN IF EXISTS daily_task_cap,
--   DROP COLUMN IF EXISTS prefer_batch_similar,
--   DROP COLUMN IF EXISTS reply_sla_hours,
--   DROP COLUMN IF EXISTS hot_lead_threshold,
--   DROP COLUMN IF EXISTS custom_order,
--   DROP COLUMN IF EXISTS notification_email;
-- -- NOTE: agent_calendar_prefs itself is shared with calendar-restructuring;
-- -- do not drop the table.
