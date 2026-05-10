-- ══════════════════════════════════════════════════════════════════
-- Insurance MGA Operations schema (Layer 2 Part B)
-- ══════════════════════════════════════════════════════════════════
-- Spec: Layer 2 Part B brief + docs/insurance-mga/MGA_OPERATIONS_VISION.md
--
-- Continues vertical_id tagging discipline from Part A (commit b4f5ec0).
-- Every table has vertical_id NOT NULL DEFAULT 'insurance' + idx_*_vertical.
--
-- Tables:
--   1. mga_hierarchy            - principal/parent/child advisor relationships
--   2. advisor_licenses         - license tracking + CE hours per jurisdiction
--   3. advisor_eo_insurance     - E&O coverage per advisor
--   4. carrier_appointments     - per-advisor carrier authorizations + commission splits
--   5. commission_ledger        - per-policy commission allocation
--   6. advisor_onboarding       - structured onboarding lifecycle
--   7. policy_reviews           - 7 review types (annual / renewal / triggered_event /
--                                 claim / complaint / pre_issuance / compliance_audit)
--   8. review_tasks             - sub-tasks per review
--   9. video_review_templates   - 12 trigger-event-specific video script templates
--
-- ALTERs:
--   - leads: assigned_advisor_id
--   - policy_applications: commission_ledger_id, last_review_date,
--     next_annual_review_date, renewal_date, in_force_status
--
-- Sensitive columns marked _encrypted are stored encrypted at app layer
-- (the n8n workflow encrypts before INSERT and decrypts on read for
-- authorized roles only). Companion _last4 columns hold the truncated
-- value for advisor-facing display.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. mga_hierarchy — principal/parent/child relationships
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS mga_hierarchy (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id         text NOT NULL DEFAULT 'insurance',
  mga_principal_id    uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  parent_advisor_id   uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  child_advisor_id    uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  hierarchy_level     integer NOT NULL,                  -- 0=principal, 1=advisor, 2=sub_agent
  effective_date      date DEFAULT CURRENT_DATE,
  end_date            date,
  status              text NOT NULL DEFAULT 'active',    -- active | inactive | terminated
  created_at          timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE mga_hierarchy ADD CONSTRAINT mh_status_check
    CHECK (status IN ('active','inactive','terminated'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_mga_hierarchy_vertical    ON mga_hierarchy(vertical_id);
CREATE INDEX IF NOT EXISTS idx_mga_hierarchy_principal   ON mga_hierarchy(mga_principal_id);
CREATE INDEX IF NOT EXISTS idx_mga_hierarchy_parent      ON mga_hierarchy(parent_advisor_id);
CREATE INDEX IF NOT EXISTS idx_mga_hierarchy_child       ON mga_hierarchy(child_advisor_id);
CREATE INDEX IF NOT EXISTS idx_mga_hierarchy_active      ON mga_hierarchy(vertical_id, status) WHERE status = 'active';

-- ─────────────────────────────────────────────────────────────────
-- 2. advisor_licenses — license + CE tracking
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS advisor_licenses (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  advisor_id               uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  license_type             text NOT NULL,                       -- 'LLQP' | 'OLHI' | 'RIBO' | etc.
  license_number_encrypted text NOT NULL,                       -- app-layer encrypted
  license_number_last4     text NOT NULL,                       -- display-safe truncation
  jurisdiction             text NOT NULL,                       -- 'ON' | 'BC' | 'AB' | 'QC' | etc.
  issued_date              date NOT NULL,
  expires_date             date NOT NULL,
  renewal_status           text NOT NULL DEFAULT 'current',     -- current | expiring_60d | expiring_30d | expiring_14d | expiring_7d | expired
  ce_hours_required        integer,
  ce_hours_completed       integer DEFAULT 0,
  ce_period_start          date,
  ce_period_end            date,
  documentation_url        text,                                -- R2 URL of uploaded license PDF (private)
  verified_at              timestamptz,
  verified_by              uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  created_at               timestamptz DEFAULT now(),
  updated_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE advisor_licenses ADD CONSTRAINT al_renewal_check
    CHECK (renewal_status IN ('current','expiring_60d','expiring_30d','expiring_14d','expiring_7d','expired'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_licenses_vertical   ON advisor_licenses(vertical_id);
CREATE INDEX IF NOT EXISTS idx_licenses_advisor    ON advisor_licenses(advisor_id);
CREATE INDEX IF NOT EXISTS idx_licenses_expires    ON advisor_licenses(expires_date);
CREATE INDEX IF NOT EXISTS idx_licenses_renewal    ON advisor_licenses(vertical_id, renewal_status) WHERE renewal_status != 'current';

-- ─────────────────────────────────────────────────────────────────
-- 3. advisor_eo_insurance — E&O coverage
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS advisor_eo_insurance (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  advisor_id               uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  carrier_name             text NOT NULL,
  policy_number_encrypted  text NOT NULL,
  policy_number_last4      text,
  coverage_amount          integer NOT NULL,                    -- in cents
  effective_date           date NOT NULL,
  expires_date             date NOT NULL,
  documentation_url        text,
  verified_at              timestamptz,
  status                   text NOT NULL DEFAULT 'active',      -- active | lapsed | replaced
  created_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE advisor_eo_insurance ADD CONSTRAINT eo_status_check
    CHECK (status IN ('active','lapsed','replaced'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_eo_vertical   ON advisor_eo_insurance(vertical_id);
CREATE INDEX IF NOT EXISTS idx_eo_advisor    ON advisor_eo_insurance(advisor_id);
CREATE INDEX IF NOT EXISTS idx_eo_expires    ON advisor_eo_insurance(expires_date);

-- ─────────────────────────────────────────────────────────────────
-- 4. carrier_appointments — per-advisor carrier authorizations
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS carrier_appointments (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                   text NOT NULL DEFAULT 'insurance',
  mga_principal_id              uuid NOT NULL REFERENCES auth_users(id) ON DELETE SET NULL,
  advisor_id                    uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  carrier_name                  text NOT NULL,
  carrier_appointment_number    text,
  product_lines                 text[] DEFAULT ARRAY[]::text[],   -- ['term_life','whole_life','disability']
  effective_date                date NOT NULL,
  expires_date                  date,
  commission_split_carrier      numeric(5,2),                     -- % of total to carrier
  commission_split_mga          numeric(5,2),                     -- % of total to MGA
  commission_split_advisor      numeric(5,2),                     -- % of total to advisor
  status                        text NOT NULL DEFAULT 'active',
  documentation_url             text,
  created_at                    timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE carrier_appointments ADD CONSTRAINT ca_status_check
    CHECK (status IN ('active','suspended','terminated'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_appointments_vertical  ON carrier_appointments(vertical_id);
CREATE INDEX IF NOT EXISTS idx_appointments_advisor   ON carrier_appointments(advisor_id);
CREATE INDEX IF NOT EXISTS idx_appointments_carrier   ON carrier_appointments(carrier_name);
CREATE INDEX IF NOT EXISTS idx_appointments_active    ON carrier_appointments(vertical_id, status) WHERE status = 'active';

-- ─────────────────────────────────────────────────────────────────
-- 5. commission_ledger — per-policy commission allocation
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS commission_ledger (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  policy_application_id    uuid REFERENCES policy_applications(id) ON DELETE SET NULL,
  carrier_appointment_id   uuid REFERENCES carrier_appointments(id) ON DELETE SET NULL,
  advisor_id               uuid NOT NULL REFERENCES auth_users(id) ON DELETE SET NULL,
  mga_principal_id         uuid NOT NULL REFERENCES auth_users(id) ON DELETE SET NULL,
  policy_number            text,
  carrier_name             text,
  product_type             text,
  premium_amount           integer NOT NULL,                    -- in cents
  total_commission         integer NOT NULL,                    -- in cents
  carrier_commission       integer,                             -- carrier retention
  mga_commission           integer,                             -- MGA cut
  advisor_commission       integer,                             -- advisor cut
  sub_agent_commission     integer DEFAULT 0,                   -- sub-agent split if applicable
  override_commission      integer DEFAULT 0,                   -- principal override commission
  payout_status            text NOT NULL DEFAULT 'pending',     -- pending | processing | paid | held | reversed
  payout_date              date,
  payout_reference         text,
  created_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE commission_ledger ADD CONSTRAINT cl_payout_check
    CHECK (payout_status IN ('pending','processing','paid','held','reversed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_commission_vertical  ON commission_ledger(vertical_id);
CREATE INDEX IF NOT EXISTS idx_commission_advisor   ON commission_ledger(advisor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_commission_principal ON commission_ledger(mga_principal_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_commission_payout    ON commission_ledger(vertical_id, payout_status);
CREATE INDEX IF NOT EXISTS idx_commission_app       ON commission_ledger(policy_application_id) WHERE policy_application_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 6. advisor_onboarding — structured onboarding lifecycle
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS advisor_onboarding (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                     text NOT NULL DEFAULT 'insurance',
  advisor_id                      uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  mga_principal_id                uuid NOT NULL REFERENCES auth_users(id) ON DELETE SET NULL,
  status                          text NOT NULL DEFAULT 'pending',        -- pending | in_progress | approved | rejected
  steps_completed                 jsonb DEFAULT '{}'::jsonb,
  application_data                jsonb,
  background_check_status         text DEFAULT 'pending',                 -- pending | in_progress | clear | flagged | failed
  background_check_provider       text DEFAULT 'certn',
  background_check_id             text,
  background_check_completed_at   timestamptz,
  license_verified                boolean DEFAULT false,
  eo_insurance_verified           boolean DEFAULT false,
  carrier_appointments_initiated  boolean DEFAULT false,
  training_completed              boolean DEFAULT false,
  contract_signed_at              timestamptz,
  contract_esignature_id          text,
  approved_at                     timestamptz,
  approved_by                     uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  rejection_reason                text,
  started_at                      timestamptz DEFAULT now(),
  completed_at                    timestamptz
);

DO $$ BEGIN
  ALTER TABLE advisor_onboarding ADD CONSTRAINT ao_status_check
    CHECK (status IN ('pending','in_progress','approved','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_onboarding_vertical  ON advisor_onboarding(vertical_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_advisor   ON advisor_onboarding(advisor_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_principal ON advisor_onboarding(mga_principal_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_pending   ON advisor_onboarding(vertical_id, status) WHERE status IN ('pending','in_progress');

-- ─────────────────────────────────────────────────────────────────
-- 7. policy_reviews — 7 review types
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS policy_reviews (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                 text NOT NULL DEFAULT 'insurance',
  policy_application_id       uuid REFERENCES policy_applications(id) ON DELETE SET NULL,
  client_id                   uuid REFERENCES clients(id) ON DELETE SET NULL,
  lead_id                     uuid REFERENCES leads(id) ON DELETE SET NULL,
  advisor_id                  uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  review_type                 text NOT NULL,    -- pre_issuance | annual | triggered_event | renewal | claim | compliance_audit | complaint
  trigger_source              text,             -- scheduled | behavioral_signal | market_signal | client_request | carrier_request | regulator_request
  trigger_signal_id           uuid,             -- soft FK to behavioral_signals.id
  trigger_signal_type         text,             -- birthday | new_job | marriage | baby | home_purchase | business_expansion | job_loss | etc.
  scheduled_date              date,
  due_date                    date NOT NULL,
  conducted_date              date,
  conducted_via               text,             -- video | phone | whatsapp | sms | email | in_person
  client_situation_changes    jsonb,
  coverage_still_adequate     boolean,
  recommendations             jsonb,
  outcome                     text,             -- coverage_unchanged | coverage_increased | coverage_decreased | new_policy_added | policy_replaced | client_no_response | escalated
  ai_suggested_questions      jsonb,
  ai_risk_assessment          jsonb,
  documentation_url           text,
  client_acknowledgment_at    timestamptz,
  client_signature_id         text,
  priority                    text NOT NULL DEFAULT 'medium',     -- urgent | high | medium | low
  status                      text NOT NULL DEFAULT 'scheduled',  -- scheduled | in_progress | completed | overdue | escalated | cancelled
  video_render_id             uuid,             -- soft FK to video_renders.id (avoid cross-domain hard FK)
  video_engagement_status     text DEFAULT 'not_sent',            -- not_sent | sent | viewed | replied | meeting_booked
  created_at                  timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE policy_reviews ADD CONSTRAINT pr_review_type_check
    CHECK (review_type IN ('pre_issuance','annual','triggered_event','renewal','claim','compliance_audit','complaint'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE policy_reviews ADD CONSTRAINT pr_priority_check
    CHECK (priority IN ('urgent','high','medium','low'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE policy_reviews ADD CONSTRAINT pr_status_check
    CHECK (status IN ('scheduled','in_progress','completed','overdue','escalated','cancelled'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE policy_reviews ADD CONSTRAINT pr_video_engagement_check
    CHECK (video_engagement_status IN ('not_sent','sent','viewed','replied','meeting_booked'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_reviews_vertical        ON policy_reviews(vertical_id);
CREATE INDEX IF NOT EXISTS idx_reviews_advisor         ON policy_reviews(advisor_id, due_date);
CREATE INDEX IF NOT EXISTS idx_reviews_due_date        ON policy_reviews(due_date);
CREATE INDEX IF NOT EXISTS idx_reviews_status          ON policy_reviews(vertical_id, status);
CREATE INDEX IF NOT EXISTS idx_reviews_priority        ON policy_reviews(vertical_id, priority);
CREATE INDEX IF NOT EXISTS idx_reviews_type            ON policy_reviews(vertical_id, review_type);
CREATE INDEX IF NOT EXISTS idx_reviews_trigger_signal  ON policy_reviews(trigger_signal_id) WHERE trigger_signal_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reviews_overdue         ON policy_reviews(vertical_id, due_date) WHERE status IN ('scheduled','in_progress');
CREATE INDEX IF NOT EXISTS idx_reviews_video           ON policy_reviews(video_render_id) WHERE video_render_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 8. review_tasks — sub-tasks per review
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS review_tasks (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id         text NOT NULL DEFAULT 'insurance',
  policy_review_id    uuid REFERENCES policy_reviews(id) ON DELETE CASCADE,
  task_type           text NOT NULL,
  description         text,
  status              text NOT NULL DEFAULT 'pending',
  completed_at        timestamptz,
  notes               text
);

DO $$ BEGIN
  ALTER TABLE review_tasks ADD CONSTRAINT rt_status_check
    CHECK (status IN ('pending','in_progress','completed','cancelled'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_review_tasks_vertical ON review_tasks(vertical_id);
CREATE INDEX IF NOT EXISTS idx_review_tasks_review   ON review_tasks(policy_review_id);

-- ─────────────────────────────────────────────────────────────────
-- 9. video_review_templates — trigger-event-specific scripts
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS video_review_templates (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  trigger_event            text NOT NULL,                       -- birthday | new_job | marriage | baby | home_purchase | business_expansion | job_loss | annual_review_due | renewal_due | claim_filed | retirement_planning_age | child_milestone
  script_template          text NOT NULL,                       -- with {{variables}}
  tone                     text,                                -- celebratory | congratulatory | supportive | informative | urgent
  cta_text                 text,
  recommended_persona_id   text,
  recommended_look_id      text,
  duration_seconds         integer DEFAULT 60,
  active                   boolean DEFAULT true,
  created_at               timestamptz DEFAULT now(),
  UNIQUE (vertical_id, trigger_event)
);

CREATE INDEX IF NOT EXISTS idx_video_templates_vertical ON video_review_templates(vertical_id);
CREATE INDEX IF NOT EXISTS idx_video_templates_trigger  ON video_review_templates(trigger_event) WHERE active = true;

-- ─────────────────────────────────────────────────────────────────
-- 10. ALTERs on existing tables
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE leads ADD COLUMN IF NOT EXISTS assigned_advisor_id uuid REFERENCES auth_users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_leads_assigned_advisor ON leads(assigned_advisor_id) WHERE assigned_advisor_id IS NOT NULL;

ALTER TABLE policy_applications ADD COLUMN IF NOT EXISTS commission_ledger_id uuid REFERENCES commission_ledger(id) ON DELETE SET NULL;
ALTER TABLE policy_applications ADD COLUMN IF NOT EXISTS last_review_date date;
ALTER TABLE policy_applications ADD COLUMN IF NOT EXISTS next_annual_review_date date;
ALTER TABLE policy_applications ADD COLUMN IF NOT EXISTS renewal_date date;
ALTER TABLE policy_applications ADD COLUMN IF NOT EXISTS in_force_status text DEFAULT 'pending';

DO $$ BEGIN
  ALTER TABLE policy_applications ADD CONSTRAINT pa_in_force_check
    CHECK (in_force_status IS NULL OR in_force_status IN ('pending','in_force','lapsed','cancelled','expired'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_policy_app_renewal      ON policy_applications(renewal_date) WHERE renewal_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_policy_app_next_review  ON policy_applications(next_annual_review_date) WHERE next_annual_review_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_policy_app_in_force     ON policy_applications(vertical_id, in_force_status);

-- ─────────────────────────────────────────────────────────────────
-- 11. RLS — service_role-only on every new table
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE mga_hierarchy            ENABLE ROW LEVEL SECURITY;
ALTER TABLE advisor_licenses         ENABLE ROW LEVEL SECURITY;
ALTER TABLE advisor_eo_insurance     ENABLE ROW LEVEL SECURITY;
ALTER TABLE carrier_appointments     ENABLE ROW LEVEL SECURITY;
ALTER TABLE commission_ledger        ENABLE ROW LEVEL SECURITY;
ALTER TABLE advisor_onboarding       ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_reviews           ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_tasks             ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_review_templates   ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN CREATE POLICY mh_service   ON mga_hierarchy           FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY al_service   ON advisor_licenses        FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY eo_service   ON advisor_eo_insurance    FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ca_service   ON carrier_appointments    FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY cl_service   ON commission_ledger       FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ao_service   ON advisor_onboarding      FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY pr_service   ON policy_reviews          FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY rt_service   ON review_tasks            FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY vrt_service  ON video_review_templates  FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 12. Verification queries
-- ─────────────────────────────────────────────────────────────────

-- SELECT tablename FROM pg_tables WHERE tablename IN ('mga_hierarchy','advisor_licenses','advisor_eo_insurance','carrier_appointments','commission_ledger','advisor_onboarding','policy_reviews','review_tasks','video_review_templates') ORDER BY tablename;
-- SELECT column_name FROM information_schema.columns WHERE table_name='leads' AND column_name='assigned_advisor_id';
-- SELECT column_name FROM information_schema.columns WHERE table_name='policy_applications' AND column_name IN ('commission_ledger_id','last_review_date','next_annual_review_date','renewal_date','in_force_status');

-- ═════════════════════════════════════════════════════════════════
-- ROLLBACK (commented — uncomment + run only to roll back)
-- ═════════════════════════════════════════════════════════════════
-- ALTER TABLE policy_applications DROP COLUMN IF EXISTS in_force_status;
-- ALTER TABLE policy_applications DROP COLUMN IF EXISTS renewal_date;
-- ALTER TABLE policy_applications DROP COLUMN IF EXISTS next_annual_review_date;
-- ALTER TABLE policy_applications DROP COLUMN IF EXISTS last_review_date;
-- ALTER TABLE policy_applications DROP COLUMN IF EXISTS commission_ledger_id;
-- ALTER TABLE leads DROP COLUMN IF EXISTS assigned_advisor_id;
-- DROP TABLE IF EXISTS video_review_templates;
-- DROP TABLE IF EXISTS review_tasks;
-- DROP TABLE IF EXISTS policy_reviews;
-- DROP TABLE IF EXISTS advisor_onboarding;
-- DROP TABLE IF EXISTS commission_ledger;
-- DROP TABLE IF EXISTS carrier_appointments;
-- DROP TABLE IF EXISTS advisor_eo_insurance;
-- DROP TABLE IF EXISTS advisor_licenses;
-- DROP TABLE IF EXISTS mga_hierarchy;
