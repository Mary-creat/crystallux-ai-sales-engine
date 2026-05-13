-- ══════════════════════════════════════════════════════════════════
-- Sentinel Phase 2 — Platform Health Monitoring
--
-- Adds workflow-level + endpoint-level health tracking on top of the
-- foundation tables (sentinel_modules / sentinel_alerts / sentinel_actions /
-- sentinel_workflow_breakers).
--
-- Phase 2 detects: workflow silence, error-rate spikes, latency spikes,
-- external-endpoint outages. Auto-remediation (auto-restart, smart resume)
-- is deferred to Phase 4 — Phase 2 only emits alerts + populates the
-- Sentinel Health tab.
--
-- Idempotent (IF NOT EXISTS + DO/EXCEPTION + ON CONFLICT DO NOTHING).
-- ══════════════════════════════════════════════════════════════════

-- 1. sentinel_workflow_health — one row per workflow per 5-min window.
-- The health collector aggregates n8n /api/v1/executions output into
-- these rows; the analyzer reads them, the dashboard renders them.
CREATE TABLE IF NOT EXISTS sentinel_workflow_health (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id           text NOT NULL,
  workflow_name         text,
  window_start          timestamptz NOT NULL,
  window_end            timestamptz NOT NULL,
  execution_count       integer DEFAULT 0,
  success_count         integer DEFAULT 0,
  error_count           integer DEFAULT 0,
  waiting_count         integer DEFAULT 0,
  error_rate_pct        numeric(5,2) GENERATED ALWAYS AS (
    CASE WHEN execution_count > 0
         THEN (error_count * 100.0 / execution_count)
         ELSE 0 END
  ) STORED,
  avg_duration_ms       integer DEFAULT 0,
  p95_duration_ms       integer DEFAULT 0,
  last_execution_at     timestamptz,
  status                text NOT NULL DEFAULT 'unknown',
  created_at            timestamptz DEFAULT now(),
  UNIQUE (workflow_id, window_start)
);

DO $$ BEGIN
  ALTER TABLE sentinel_workflow_health
    ADD CONSTRAINT swh_status_check
    CHECK (status IN ('healthy','degraded','critical','silent','unknown'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_swh_workflow_recent
  ON sentinel_workflow_health(workflow_id, window_start DESC);

CREATE INDEX IF NOT EXISTS idx_swh_status_window
  ON sentinel_workflow_health(status, window_start DESC)
  WHERE status IN ('degraded','critical','silent');

-- 2. sentinel_endpoint_health — external endpoint ping history.
CREATE TABLE IF NOT EXISTS sentinel_endpoint_health (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_name         text NOT NULL,
  endpoint_url          text NOT NULL,
  endpoint_category     text NOT NULL,
  checked_at            timestamptz NOT NULL DEFAULT now(),
  status_code           integer,
  response_time_ms      integer,
  status                text NOT NULL,
  consecutive_failures  integer DEFAULT 0,
  last_error            text,
  created_at            timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_endpoint_health
    ADD CONSTRAINT seh_status_check
    CHECK (status IN ('up','down','degraded','unknown'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_seh_endpoint_recent
  ON sentinel_endpoint_health(endpoint_name, checked_at DESC);

CREATE INDEX IF NOT EXISTS idx_seh_down
  ON sentinel_endpoint_health(checked_at DESC)
  WHERE status = 'down';

-- 3. sentinel_endpoints — registry of what to ping.
CREATE TABLE IF NOT EXISTS sentinel_endpoints (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_name         text UNIQUE NOT NULL,
  endpoint_url          text NOT NULL,
  endpoint_category     text NOT NULL,           -- supabase | n8n | dashboard | external
  expected_status_code  integer DEFAULT 200,
  timeout_ms            integer DEFAULT 5000,
  active                boolean DEFAULT true,
  notes                 text,
  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now()
);

INSERT INTO sentinel_endpoints (endpoint_name, endpoint_url, endpoint_category, expected_status_code, timeout_ms, notes) VALUES
  ('supabase_rest',    'https://zqwatouqmqgkmaslydbr.supabase.co/rest/v1/', 'supabase',  200, 5000, 'Supabase REST root.'),
  ('n8n_health',       'https://automation.crystallux.org/healthz',         'n8n',       200, 5000, 'n8n self-hosted health endpoint.'),
  ('admin_dashboard',  'https://admin.crystallux.org/',                     'dashboard', 200, 5000, 'Admin Cloudflare Pages.'),
  ('client_dashboard', 'https://app.crystallux.org/',                       'dashboard', 200, 5000, 'Client Cloudflare Pages.'),
  ('marketing_site',   'https://crystallux.org/',                           'dashboard', 200, 5000, 'Marketing Cloudflare Pages.')
ON CONFLICT (endpoint_name) DO NOTHING;

-- 4. sentinel_health_thresholds — per-workflow / per-endpoint / default SLOs.
-- The analyzer looks up the most specific row (workflow → default).
CREATE TABLE IF NOT EXISTS sentinel_health_thresholds (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope                    text NOT NULL,                       -- workflow | endpoint | default
  target_name              text,                                -- workflow_name or endpoint_name; NULL for default
  error_rate_warning_pct   integer DEFAULT 10,
  error_rate_critical_pct  integer DEFAULT 25,
  max_silence_minutes      integer DEFAULT 60,
  max_p95_ms               integer DEFAULT 30000,
  max_consecutive_down     integer DEFAULT 3,
  active                   boolean DEFAULT true,
  notes                    text,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_health_thresholds
    ADD CONSTRAINT sht_scope_check
    CHECK (scope IN ('workflow','endpoint','default'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE sentinel_health_thresholds
    ADD CONSTRAINT sht_pct_order_check
    CHECK (error_rate_warning_pct < error_rate_critical_pct);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sht_scope_target
  ON sentinel_health_thresholds(scope, COALESCE(target_name, ''));

-- Seed: defaults for every workflow + every endpoint.
INSERT INTO sentinel_health_thresholds
  (scope, target_name, error_rate_warning_pct, error_rate_critical_pct, max_silence_minutes, max_p95_ms, max_consecutive_down, notes) VALUES
  ('default', NULL, 10, 25,  60, 30000, 3, 'Default SLO. Workflows without an explicit row fall back to this.'),
  ('workflow', 'CLX - Lead Research v2',         5,  15,  30, 60000, 3, 'Production-critical. Tighter error-rate floor.'),
  ('workflow', 'CLX - Campaign Router v2',       5,  15,  30, 30000, 3, 'Production-critical.'),
  ('workflow', 'CLX - Outreach Generation v2',   5,  15,  60, 60000, 3, 'Production-critical.'),
  ('workflow', 'CLX - Outreach Sender v2',       5,  15,  60, 60000, 3, 'Production-critical.'),
  ('workflow', 'CLX - Pipeline Update v2',       5,  15,  60, 30000, 3, 'Production-critical.'),
  ('workflow', 'CLX - Reply Ingestion v1',       5,  15,  30, 30000, 3, 'Production-critical.'),
  ('workflow', 'CLX - Booking v2',               5,  15,  60, 30000, 3, 'Production-critical.'),
  ('workflow', 'CLX - Auth Login v1',            2,   5,  10, 5000,  2, 'Auth pathway — strictest SLO.'),
  ('workflow', 'CLX - Auth Session Validate v1', 2,   5,  10, 5000,  2, 'Auth pathway — strictest SLO.')
ON CONFLICT (scope, COALESCE(target_name, '')) DO NOTHING;

-- 5. RPC: record_endpoint_check — atomic write + consecutive_failures roll-up.
-- The endpoint collector calls this once per endpoint per cycle. It carries
-- forward the consecutive_failures counter from the previous check so the
-- analyzer can detect 3-in-a-row outages cheaply.
CREATE OR REPLACE FUNCTION record_endpoint_check(
  p_endpoint_name    text,
  p_endpoint_url     text,
  p_endpoint_category text,
  p_status_code      integer,
  p_response_time_ms integer,
  p_status           text,
  p_last_error       text
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_prev_failures integer;
  v_new_failures  integer;
  v_id            uuid;
BEGIN
  SELECT consecutive_failures
    INTO v_prev_failures
    FROM sentinel_endpoint_health
   WHERE endpoint_name = p_endpoint_name
   ORDER BY checked_at DESC
   LIMIT 1;

  IF p_status = 'down' THEN
    v_new_failures := COALESCE(v_prev_failures, 0) + 1;
  ELSE
    v_new_failures := 0;
  END IF;

  INSERT INTO sentinel_endpoint_health
    (endpoint_name, endpoint_url, endpoint_category, status_code, response_time_ms,
     status, consecutive_failures, last_error)
  VALUES
    (p_endpoint_name, p_endpoint_url, p_endpoint_category, p_status_code, p_response_time_ms,
     p_status, v_new_failures, p_last_error)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 6. Mark health_monitoring as 'active' once this migration ships.
UPDATE sentinel_modules
   SET status = 'active'
 WHERE module_name = 'health_monitoring';

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS record_endpoint_check(text,text,text,integer,integer,text,text);
-- DROP TABLE IF EXISTS sentinel_health_thresholds;
-- DROP TABLE IF EXISTS sentinel_endpoints;
-- DROP TABLE IF EXISTS sentinel_endpoint_health;
-- DROP TABLE IF EXISTS sentinel_workflow_health;
