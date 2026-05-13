-- ══════════════════════════════════════════════════════════════════
-- Sentinel Phase 3 — Security Monitoring
--
-- Adds universal security-event logging + credential rotation tracking
-- + rule-based detection on top of the foundation tables (sentinel_modules
-- / sentinel_alerts / sentinel_actions).
--
-- Phase 3 detects: brute-force / credential stuffing, session anomalies,
-- API abuse (unauth flood), privilege denials, rate-limit breaches,
-- credential rotation overdue. Detection only — auto-lockout / IP block
-- is deferred to Phase 4 auto-remediation.
--
-- Phase 3 reads from TWO event sources:
-- 1) sentinel_security_events — opt-in log other workflows POST to.
-- 2) regulatory_audit_log (Layer 2 insurance audit log, existing) — for
--    audit-driven patterns (admin privilege grants, suitability bypasses).
--
-- Idempotent (IF NOT EXISTS + DO/EXCEPTION + ON CONFLICT DO NOTHING).
-- ══════════════════════════════════════════════════════════════════

-- 1. sentinel_security_events — universal append-only log.
-- Any workflow (or external integration) can POST one row when it
-- observes a security-relevant signal. Auth workflows ARE NOT modified
-- to write here — they keep their existing behavior; we add new
-- workflows that opt in, plus the detector reads adjacent tables.
CREATE TABLE IF NOT EXISTS sentinel_security_events (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type          text NOT NULL,
  severity            text NOT NULL DEFAULT 'info',
  user_id             uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  user_email          text,
  source_ip           text,
  user_agent          text,
  endpoint            text,
  details             jsonb DEFAULT '{}'::jsonb,
  created_at          timestamptz NOT NULL DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_security_events
    ADD CONSTRAINT sse_severity_check
    CHECK (severity IN ('info','warning','critical'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_sse_event_type_recent
  ON sentinel_security_events(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sse_email_recent
  ON sentinel_security_events(user_email, created_at DESC)
  WHERE user_email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sse_source_ip_recent
  ON sentinel_security_events(source_ip, created_at DESC)
  WHERE source_ip IS NOT NULL;

-- 2. sentinel_credential_inventory — tracks every credential the platform
-- holds: Supabase service role key, Stripe secret, Anthropic API key,
-- Twilio token, etc. Mary updates last_rotated_at after rotation; the
-- daily check raises alerts when next_rotation_due approaches or passes.
CREATE TABLE IF NOT EXISTS sentinel_credential_inventory (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  credential_name          text UNIQUE NOT NULL,
  credential_type          text NOT NULL,                    -- api_key | service_role | password | webhook_secret | oauth_refresh
  vendor                   text,                             -- supabase | stripe | anthropic | twilio | vapi | heygen | n8n | postmark | cloudflare | other
  stored_in                text,                             -- 'n8n_credentials' | 'env_var' | 'supabase_secrets' | '1password' | etc.
  last_rotated_at          timestamptz,
  rotation_interval_days   integer NOT NULL DEFAULT 90,      -- target rotation cadence
  warning_threshold_days   integer NOT NULL DEFAULT 14,      -- alert when within N days of due date
  next_rotation_due        timestamptz GENERATED ALWAYS AS (
    COALESCE(last_rotated_at, created_at) + (rotation_interval_days || ' days')::interval
  ) STORED,
  active                   boolean DEFAULT true,
  notes                    text,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sci_due
  ON sentinel_credential_inventory(next_rotation_due ASC)
  WHERE active = true;

-- Seed the credentials Crystallux actually uses today. Mary edits
-- last_rotated_at via the dashboard after each rotation. Rows that are
-- net-new at deploy time get last_rotated_at = created_at, so the first
-- alert fires N days after deploy.
INSERT INTO sentinel_credential_inventory
  (credential_name, credential_type, vendor, stored_in, rotation_interval_days, warning_threshold_days, notes) VALUES
  ('supabase_service_role',    'service_role',   'supabase',   'n8n_credentials',  365, 30, 'Supabase service-role JWT — long-lived; rotate annually.'),
  ('supabase_anon_key',        'api_key',        'supabase',   'env_var',          365, 30, 'Supabase anon key — public-safe but rotate annually for hygiene.'),
  ('mary_master_token',        'api_key',        'crystallux', 'env_var',          180, 14, 'MARY_MASTER_TOKEN — internal-call auth between workflows.'),
  ('internal_email_secret',    'api_key',        'crystallux', 'env_var',          180, 14, 'INTERNAL_EMAIL_SECRET — seed-workflow auth.'),
  ('anthropic_api_key',        'api_key',        'anthropic',  'n8n_credentials',  180, 14, 'Claude API key.'),
  ('openai_admin_api_key',     'api_key',        'openai',     'env_var',          180, 14, 'OpenAI admin key for cost API.'),
  ('twilio_auth_token',        'api_key',        'twilio',     'n8n_credentials',  180, 14, 'Twilio auth token.'),
  ('vapi_api_key',             'api_key',        'vapi',       'n8n_credentials',  180, 14, 'Vapi voice API.'),
  ('heygen_api_key',           'api_key',        'heygen',     'n8n_credentials',  180, 14, 'HeyGen video API.'),
  ('postmark_server_token',    'api_key',        'postmark',   'n8n_credentials',  180, 14, 'Postmark email server token.'),
  ('stripe_secret_key',        'api_key',        'stripe',     'n8n_credentials',   90, 14, 'Stripe live secret — rotate quarterly.'),
  ('stripe_webhook_secret',    'webhook_secret', 'stripe',     'env_var',           90, 14, 'Stripe webhook signing secret.'),
  ('n8n_api_key',              'api_key',        'n8n',        'env_var',          180, 14, 'n8n personal API key for Sentinel Phase 2 health collector.'),
  ('cloudflare_api_token',     'api_key',        'cloudflare', 'env_var',          365, 30, 'Cloudflare Pages deploy / DNS edit.'),
  ('admin_password',           'password',       'crystallux', 'supabase_auth',     90, 14, 'info@crystallux.org admin password — rotate quarterly.')
ON CONFLICT (credential_name) DO NOTHING;

-- 3. sentinel_security_rules — declarative detection rules.
-- The detector workflow reads this table, evaluates each active rule
-- against the configured window, raises alerts when threshold hit.
CREATE TABLE IF NOT EXISTS sentinel_security_rules (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_name           text UNIQUE NOT NULL,
  rule_type           text NOT NULL,                         -- brute_force | session_anomaly | api_abuse | privilege_denied | rate_limit | audit_anomaly
  description         text,
  event_type_filter   text,                                  -- match against sentinel_security_events.event_type
  group_by            text NOT NULL DEFAULT 'user_email',    -- user_email | source_ip | endpoint | user_id
  window_minutes      integer NOT NULL DEFAULT 15,
  threshold_count     integer NOT NULL DEFAULT 5,
  severity            text NOT NULL DEFAULT 'warning',
  active              boolean DEFAULT true,
  notes               text,
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_security_rules
    ADD CONSTRAINT ssr_severity_check
    CHECK (severity IN ('warning','critical','emergency'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE sentinel_security_rules
    ADD CONSTRAINT ssr_group_by_check
    CHECK (group_by IN ('user_email','source_ip','endpoint','user_id'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Seed sensible defaults Mary can tune later via the dashboard.
INSERT INTO sentinel_security_rules
  (rule_name, rule_type, description, event_type_filter, group_by, window_minutes, threshold_count, severity, notes) VALUES
  ('brute_force_login_per_email',  'brute_force',     '5+ failed logins for the same email in 15 min', 'login_failed',      'user_email', 15,  5, 'critical',  'Classic credential-stuffing pattern.'),
  ('brute_force_login_per_ip',     'brute_force',     '20+ failed logins from same IP in 30 min',      'login_failed',      'source_ip',  30, 20, 'critical',  'Distributed credential stuffing.'),
  ('session_reject_burst',         'session_anomaly', '10+ invalid session validations from one IP in 10 min', 'session_rejected', 'source_ip', 10, 10, 'warning', 'Possible token guessing / replay attempts.'),
  ('webhook_auth_failed_burst',    'api_abuse',       '15+ webhook auth failures from same IP in 10 min', 'webhook_auth_failed', 'source_ip', 10, 15, 'critical', 'Internal webhook hammering.'),
  ('privilege_denied_burst',       'privilege_denied','5+ privilege-denied responses for same user in 30 min', 'privilege_denied','user_email', 30,  5, 'warning',  'User probing for admin endpoints.'),
  ('rate_limit_breached',          'rate_limit',      '3+ rate-limit breaches per IP in 1 hour',       'rate_limit_breached','source_ip', 60,  3, 'warning',   'Sustained over-quota client.'),
  ('admin_off_hours',              'audit_anomaly',   '3+ admin privilege-grants by same user in 1 hour', 'admin_action_recorded','user_email', 60,  3, 'warning', 'Admin action burst — investigate.')
ON CONFLICT (rule_name) DO NOTHING;

-- 4. RPC: log_security_event — convenience wrapper for security-aware workflows.
-- Lets a workflow POST to a single endpoint and get back the event id, rather
-- than each callsite needing the full insert shape.
CREATE OR REPLACE FUNCTION log_security_event(
  p_event_type  text,
  p_severity    text,
  p_user_id     uuid,
  p_user_email  text,
  p_source_ip   text,
  p_user_agent  text,
  p_endpoint    text,
  p_details     jsonb
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO sentinel_security_events
    (event_type, severity, user_id, user_email, source_ip, user_agent, endpoint, details)
  VALUES
    (p_event_type, COALESCE(p_severity, 'info'), p_user_id, p_user_email,
     p_source_ip, p_user_agent, p_endpoint, COALESCE(p_details, '{}'::jsonb))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- 5. Mark security_monitoring module as active after this migration ships.
UPDATE sentinel_modules
   SET status = 'active'
 WHERE module_name = 'security_monitoring';

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS log_security_event(text,text,uuid,text,text,text,text,jsonb);
-- DROP TABLE IF EXISTS sentinel_security_rules;
-- DROP TABLE IF EXISTS sentinel_credential_inventory;
-- DROP TABLE IF EXISTS sentinel_security_events;
