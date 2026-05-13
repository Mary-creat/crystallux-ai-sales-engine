-- ══════════════════════════════════════════════════════════════════
-- Sentinel Phase 4 — Auto-Remediation
--
-- Adds declarative playbook execution on top of Phases 1-3 detections.
-- Phase 4 takes the alerts that Phases 1-3 raise and either:
--   (a) auto-executes a safe remediation (pause workflow, resume
--       workflow, block IP) with cooldowns, or
--   (b) writes a PENDING sentinel_actions row for destructive actions
--       (account lockout, credential revocation) that Mary must
--       approve before they execute.
--
-- Key safety rails:
-- - Every action runs through sentinel_actions (existing audit table)
--   with triggered_by / human_approved / approved_by columns.
-- - Cooldowns prevent flap loops (one playbook can't re-fire on the
--   same target within `cooldown_minutes`).
-- - Essential workflows (sentinel_workflow_breakers.is_essential=true)
--   are still NEVER paused, even via Phase 4 playbooks. Phase 1's
--   `trip_workflow_breaker` RPC enforces this.
-- - Destructive actions require human approval — Phase 4 NEVER
--   auto-locks accounts or auto-revokes credentials.
--
-- Idempotent (IF NOT EXISTS + ON CONFLICT DO NOTHING).
-- ══════════════════════════════════════════════════════════════════

-- 1. sentinel_remediation_playbooks — declarative playbook registry.
-- Adding a new remediation = INSERT row + tweak orchestrator if a new
-- action_type is introduced. Existing action_types: pause_workflow,
-- resume_workflow, block_ip, propose_account_lockout,
-- propose_credential_revocation, notify_only.
CREATE TABLE IF NOT EXISTS sentinel_remediation_playbooks (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  playbook_name            text UNIQUE NOT NULL,
  description              text,
  trigger_module           text NOT NULL,                  -- cost_monitoring | health_monitoring | security_monitoring
  trigger_alert_type       text,                           -- exact alert_type match, or NULL = any alert in module
  trigger_severity_min     text NOT NULL DEFAULT 'warning',-- warning | critical | emergency
  action_type              text NOT NULL,                  -- see header comment
  action_config            jsonb NOT NULL DEFAULT '{}'::jsonb,
  requires_approval        boolean NOT NULL DEFAULT false,
  cooldown_minutes         integer NOT NULL DEFAULT 60,
  active                   boolean DEFAULT true,
  notes                    text,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE sentinel_remediation_playbooks
    ADD CONSTRAINT srp_module_check
    CHECK (trigger_module IN ('cost_monitoring','health_monitoring','security_monitoring'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE sentinel_remediation_playbooks
    ADD CONSTRAINT srp_sev_check
    CHECK (trigger_severity_min IN ('warning','critical','emergency'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE sentinel_remediation_playbooks
    ADD CONSTRAINT srp_action_check
    CHECK (action_type IN ('pause_workflow','resume_workflow','block_ip','propose_account_lockout','propose_credential_revocation','notify_only'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Seed 6 default playbooks. Mary tunes via the dashboard.
INSERT INTO sentinel_remediation_playbooks
  (playbook_name, description, trigger_module, trigger_alert_type, trigger_severity_min, action_type, action_config, requires_approval, cooldown_minutes, notes) VALUES
  ('auto_pause_workflow_silent',
   'Pause a workflow that has been silent past its SLO threshold.',
   'health_monitoring', 'health_workflow_silent', 'critical',
   'pause_workflow', '{"reason_prefix":"Sentinel: silent workflow"}'::jsonb,
   false, 120,
   'Auto. The breaker stays paused until manually resumed OR until auto_resume_when_healthy fires. is_essential=true workflows are still skipped by trip_workflow_breaker RPC.'),

  ('auto_pause_workflow_error_spike',
   'Pause a workflow whose error rate hit critical threshold.',
   'health_monitoring', 'health_error_spike', 'critical',
   'pause_workflow', '{"reason_prefix":"Sentinel: error-rate critical"}'::jsonb,
   false, 120,
   'Auto. 2-hour cooldown so a brief blip doesn''t cause flap.'),

  ('auto_resume_when_healthy',
   'Resume a paused workflow when its last 3 health windows are healthy.',
   'health_monitoring', NULL, 'warning',
   'resume_workflow', '{"min_consecutive_healthy_windows":3}'::jsonb,
   false, 60,
   'Auto. Runs every orchestrator tick; only acts if a paused breaker has 3 consecutive healthy 5-min windows (15 min healthy upstream).'),

  ('auto_block_ip_brute_force',
   'Block source IP for 60 minutes on critical brute-force alerts.',
   'security_monitoring', 'security_brute_force', 'critical',
   'block_ip', '{"block_duration_minutes":60,"reason_prefix":"Sentinel: brute force"}'::jsonb,
   false, 30,
   'Auto. Per-IP cooldown 30 min — if same IP keeps trying after unblock, alerts re-fire and we re-block. Blocklist is Crystallux-side (sentinel_ip_blocklist + is_ip_blocked RPC); add Cloudflare WAF later for edge enforcement.'),

  ('propose_account_lockout_repeated_brute_force',
   'Propose locking an account after repeated brute-force alerts for the same email.',
   'security_monitoring', 'security_brute_force', 'critical',
   'propose_account_lockout', '{"min_alerts_in_24h":3,"lockout_duration_hours":24}'::jsonb,
   true, 360,
   'HUMAN APPROVED. Orchestrator writes pending sentinel_actions row; Mary approves via the dashboard before lockout takes effect.'),

  ('propose_credential_revocation_overdue_with_threat',
   'Propose revoking a credential past its rotation deadline when security alerts are active.',
   'security_monitoring', 'credential_rotation_due', 'critical',
   'propose_credential_revocation', '{"min_overdue_days":30}'::jsonb,
   true, 1440,
   'HUMAN APPROVED. Combines two signals: credential overdue + active threat. Mary reviews before revocation.')
ON CONFLICT (playbook_name) DO NOTHING;

-- 2. sentinel_ip_blocklist — active blocked source IPs with optional expiry.
-- Webhook entry points (Phase 5+ wiring) consult is_ip_blocked() at the
-- top of session-validation steps. NULL expires_at = permanent block.
CREATE TABLE IF NOT EXISTS sentinel_ip_blocklist (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ip_address          text NOT NULL,
  blocked_at          timestamptz NOT NULL DEFAULT now(),
  expires_at          timestamptz,
  reason              text,
  blocked_by          text,                              -- 'auto:<playbook>' or 'human:<user_id>'
  alert_id            uuid REFERENCES sentinel_alerts(id) ON DELETE SET NULL,
  action_id           uuid REFERENCES sentinel_actions(id) ON DELETE SET NULL,
  active              boolean NOT NULL DEFAULT true,
  unblocked_at        timestamptz,
  unblock_reason      text,
  created_at          timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sib_active_unique
  ON sentinel_ip_blocklist(ip_address)
  WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_sib_expires_active
  ON sentinel_ip_blocklist(expires_at)
  WHERE active = true AND expires_at IS NOT NULL;

-- 3. is_ip_blocked RPC — cheap boolean check for webhook entry points.
-- Used by auth / webhook-validation workflows: if (is_ip_blocked(source_ip)) reject.
-- Adds an OR clause to existing auth flows when Mary opts new ones in.
CREATE OR REPLACE FUNCTION is_ip_blocked(p_ip text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM sentinel_ip_blocklist
     WHERE ip_address = p_ip
       AND active = true
       AND (expires_at IS NULL OR expires_at > now())
  );
$$;

-- 4. Mark auto_remediation module as active.
UPDATE sentinel_modules
   SET status = 'active'
 WHERE module_name = 'auto_remediation';

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS is_ip_blocked(text);
-- DROP TABLE IF EXISTS sentinel_ip_blocklist;
-- DROP TABLE IF EXISTS sentinel_remediation_playbooks;
