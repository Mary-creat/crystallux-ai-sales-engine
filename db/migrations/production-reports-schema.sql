-- ══════════════════════════════════════════════════════════════════
-- Production Reports Framework (Layer 1 — core engine, universal)
-- ══════════════════════════════════════════════════════════════════
-- Universal reporting framework. Templates can be universal
-- (vertical_id NULL) or vertical-specific (vertical_id set, e.g.
-- 'insurance'). Generated reports are per-recipient + per-period.
--
-- LAYER 1 PURITY:
--   - production_report_templates.vertical_id is NULLABLE — universal-
--     with-filter pattern. NULL means the template applies to any
--     vertical.
--   - production_reports.vertical_id is NULLABLE for the same reason
--     (a "monthly_production" report is universal in structure even
--     though its data may be vertical-tagged).
--   - No insurance / mga / advisor terminology in column names.
--
-- Additive, idempotent.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. production_report_templates — definitions
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS production_report_templates (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id            text,                                      -- NULL = universal default
  template_name          text NOT NULL,
  template_type          text NOT NULL,                             -- monthly_production | quarterly_summary | annual_review | commission_breakdown | advisor_performance | compliance_health | custom
  description            text,
  recipient_role         text NOT NULL,                             -- insurer | mga_principal | admin | client | supervisor
  metrics_included       jsonb DEFAULT '[]'::jsonb,
  visualization_config   jsonb DEFAULT '{}'::jsonb,
  schedule_pattern       text DEFAULT 'manual',                     -- manual | monthly | quarterly | annual | on_demand
  delivery_methods       text[] DEFAULT ARRAY['dashboard']::text[], -- email | dashboard | api_webhook
  is_active              boolean DEFAULT true,
  created_at             timestamptz DEFAULT now(),
  updated_at             timestamptz DEFAULT now(),
  UNIQUE (vertical_id, template_name)
);

DO $$ BEGIN
  ALTER TABLE production_report_templates
    ADD CONSTRAINT prt_schedule_check
    CHECK (schedule_pattern IN ('manual','monthly','quarterly','annual','on_demand'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_prt_lookup
  ON production_report_templates(template_type, vertical_id)
  WHERE is_active = true;

-- ─────────────────────────────────────────────────────────────────
-- 2. production_reports — generated instances
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS production_reports (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text,                                    -- copied from template; NULL allowed
  template_id              uuid REFERENCES production_report_templates(id) ON DELETE SET NULL,
  recipient_id             uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  recipient_account_id     uuid,                                    -- soft FK — insurer_account_id, client_id, etc.
  recipient_account_type   text,                                    -- 'insurer' | 'client' | 'internal'
  reporting_period_start   date NOT NULL,
  reporting_period_end     date NOT NULL,
  report_data              jsonb NOT NULL DEFAULT '{}'::jsonb,
  generated_at             timestamptz DEFAULT now(),
  delivered_at             timestamptz,
  viewed_at                timestamptz,
  exported_count           integer DEFAULT 0,
  last_exported_at         timestamptz,
  status                   text NOT NULL DEFAULT 'generated',       -- generated | delivered | viewed | archived
  created_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE production_reports
    ADD CONSTRAINT pr_status_check
    CHECK (status IN ('generated','delivered','viewed','archived'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_pr_recipient
  ON production_reports(recipient_id, generated_at DESC);

CREATE INDEX IF NOT EXISTS idx_pr_recipient_account
  ON production_reports(recipient_account_id, recipient_account_type, generated_at DESC);

CREATE INDEX IF NOT EXISTS idx_pr_period
  ON production_reports(reporting_period_start, reporting_period_end);

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS production_reports;
-- DROP TABLE IF EXISTS production_report_templates;
