-- ══════════════════════════════════════════════════════════════════
-- Insurance MGA schema (Layer 2 Part A — AI Compliance Engine)
-- ══════════════════════════════════════════════════════════════════
-- Spec: Phase 5 build brief (Layer 2 Part A) + docs/insurance-mga/AI_COMPLIANCE_VISION.md.
--
-- ARCHITECTURE NOTE: vertical_id tagging
-- Crystallux is a multi-vertical platform. This migration introduces
-- the INSURANCE vertical of Layer 2 (MGA module). Every table here
-- carries `vertical_id text DEFAULT 'insurance' NOT NULL` so future
-- Layer 2 verticals (mortgage, real estate, group benefits, etc.)
-- plug into the SAME tables without schema migration pain. Each
-- vertical has its own regulator (FSRA, FINTRAC, RECO, MFDA), its
-- own KYC/suitability/disclosure surface, and its own audit
-- requirements — all expressed via the vertical_id partition.
--
-- Valid vertical_id values (foundation):
--   'insurance'           — this migration (Phase 5)
--   'mortgage'            — Phase 7 future
--   'real_estate'         — Phase 8 future
--   'investment'          — Phase 9 future (separate licensing)
--   'group_benefits'      — Phase 10 future
--   'commercial_insurance'— Phase 11 future (distinct from personal)
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. compliance_reviews — every AI compliance check + human override
-- ─────────────────────────────────────────────────────────────────
-- policy_application_id is a soft FK (no REFERENCES) to avoid forward
-- reference; policy_applications is created later in this script.
-- Application code is responsible for referential integrity.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS compliance_reviews (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  policy_application_id    uuid,                                 -- soft FK to policy_applications.id
  client_id                uuid REFERENCES clients(id) ON DELETE SET NULL,
  advisor_id               uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  review_type              text NOT NULL,    -- 'kyc' | 'suitability' | 'disclosure' | 'final_compliance'
  ai_score                 integer,          -- 0-100 confidence
  ai_decision              text,             -- 'approved' | 'flagged' | 'rejected' | 'requires_human_review'
  ai_reasoning             text,
  ai_flags                 jsonb DEFAULT '[]'::jsonb,
  human_reviewer_id        uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  human_decision           text,             -- 'approved' | 'rejected' | 'override_ai'
  human_notes              text,
  reviewed_at              timestamptz,
  status                   text NOT NULL DEFAULT 'pending',      -- pending | ai_reviewed | human_review_required | approved | rejected
  created_at               timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE compliance_reviews
    ADD CONSTRAINT cr_review_type_check
    CHECK (review_type IN ('kyc','suitability','disclosure','final_compliance'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE compliance_reviews
    ADD CONSTRAINT cr_status_check
    CHECK (status IN ('pending','ai_reviewed','human_review_required','approved','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE compliance_reviews
    ADD CONSTRAINT cr_ai_decision_check
    CHECK (ai_decision IS NULL OR ai_decision IN ('approved','flagged','rejected','requires_human_review'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_compliance_reviews_vertical    ON compliance_reviews(vertical_id);
CREATE INDEX IF NOT EXISTS idx_compliance_reviews_status      ON compliance_reviews(vertical_id, status);
CREATE INDEX IF NOT EXISTS idx_compliance_reviews_advisor     ON compliance_reviews(advisor_id) WHERE advisor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_compliance_reviews_app         ON compliance_reviews(policy_application_id) WHERE policy_application_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_compliance_reviews_pending     ON compliance_reviews(vertical_id, created_at DESC) WHERE status IN ('pending','human_review_required');

-- ─────────────────────────────────────────────────────────────────
-- 2. kyc_verifications — Stripe Identity verification lifecycle
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS kyc_verifications (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  client_id                uuid REFERENCES clients(id) ON DELETE SET NULL,
  lead_id                  uuid REFERENCES leads(id) ON DELETE SET NULL,
  verification_provider    text NOT NULL DEFAULT 'stripe_identity',
  external_session_id      text UNIQUE,
  verification_url         text,
  status                   text NOT NULL DEFAULT 'pending',      -- pending | in_progress | verified | failed | expired
  identity_data            jsonb,                                -- encrypted at app-layer when persisting (PII)
  document_images          jsonb,                                -- pointers to encrypted blobs (not raw)
  selfie_match_score       numeric(5,2),
  pep_screening_result     jsonb,                                -- 'manual_review_pending' until Phase 6 automation
  aml_risk_score           integer,                              -- 0-100; > 75 = manual review
  expires_at               timestamptz,
  created_at               timestamptz DEFAULT now(),
  verified_at              timestamptz
);

DO $$ BEGIN
  ALTER TABLE kyc_verifications
    ADD CONSTRAINT kv_provider_check
    CHECK (verification_provider IN ('stripe_identity','manual','onfido','jumio'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE kyc_verifications
    ADD CONSTRAINT kv_status_check
    CHECK (status IN ('pending','in_progress','verified','failed','expired'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_kyc_vertical   ON kyc_verifications(vertical_id);
CREATE INDEX IF NOT EXISTS idx_kyc_lead       ON kyc_verifications(lead_id) WHERE lead_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_kyc_client     ON kyc_verifications(client_id) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_kyc_status     ON kyc_verifications(vertical_id, status);
CREATE INDEX IF NOT EXISTS idx_kyc_session    ON kyc_verifications(external_session_id) WHERE external_session_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 3. suitability_assessments — AI conversational needs analysis
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS suitability_assessments (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                 text NOT NULL DEFAULT 'insurance',
  client_id                   uuid REFERENCES clients(id) ON DELETE SET NULL,
  lead_id                     uuid REFERENCES leads(id) ON DELETE SET NULL,
  advisor_id                  uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  product_type                text NOT NULL,                       -- insurance: 'term_life' | 'whole_life' | 'critical_illness' | 'disability' | 'auto' | 'home' | 'commercial'
  channel                     text,                                -- 'whatsapp' | 'sms' | 'email' | 'web' (how interview is conducted)
  client_situation            jsonb DEFAULT '{}'::jsonb,           -- evolving Q&A capture
  needs_analysis              jsonb,                               -- AI-derived gap analysis
  risk_tolerance              text,                                -- 'low' | 'moderate' | 'high'
  ai_recommended_products     jsonb,
  ai_recommended_coverage_amount integer,                          -- in cents
  ai_recommended_term_years   integer,
  ai_reasoning                text,
  client_acknowledged         boolean DEFAULT false,
  client_acknowledgment_at    timestamptz,
  status                      text NOT NULL DEFAULT 'in_progress', -- in_progress | client_review | acknowledged | rejected
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE suitability_assessments
    ADD CONSTRAINT sa_status_check
    CHECK (status IN ('in_progress','client_review','acknowledged','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE suitability_assessments
    ADD CONSTRAINT sa_risk_check
    CHECK (risk_tolerance IS NULL OR risk_tolerance IN ('low','moderate','high'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_suitability_vertical   ON suitability_assessments(vertical_id);
CREATE INDEX IF NOT EXISTS idx_suitability_lead       ON suitability_assessments(lead_id) WHERE lead_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_suitability_advisor    ON suitability_assessments(advisor_id) WHERE advisor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_suitability_status     ON suitability_assessments(vertical_id, status);

-- ─────────────────────────────────────────────────────────────────
-- 4. policy_recommendations — AI-ranked carrier products per assessment
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS policy_recommendations (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                 text NOT NULL DEFAULT 'insurance',
  suitability_assessment_id   uuid REFERENCES suitability_assessments(id) ON DELETE CASCADE,
  carrier_name                text NOT NULL,
  product_name                text,
  product_type                text,                                -- mirrors suitability_assessments.product_type
  coverage_amount             integer,                             -- in cents
  premium_monthly             integer,                             -- in cents
  premium_annual              integer,                             -- in cents
  term_years                  integer,
  features                    jsonb DEFAULT '{}'::jsonb,
  ai_match_score              integer,                             -- 0-100
  ai_ranking                  integer,                             -- 1 = top
  ai_reasoning                text,
  status                      text NOT NULL DEFAULT 'recommended', -- recommended | selected | rejected
  created_at                  timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE policy_recommendations
    ADD CONSTRAINT pr_status_check
    CHECK (status IN ('recommended','selected','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_policy_rec_vertical    ON policy_recommendations(vertical_id);
CREATE INDEX IF NOT EXISTS idx_policy_rec_assessment  ON policy_recommendations(suitability_assessment_id, ai_ranking);

-- ─────────────────────────────────────────────────────────────────
-- 5. compliance_disclosures — required disclosures + e-signature trail
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS compliance_disclosures (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                     text NOT NULL DEFAULT 'insurance',
  client_id                       uuid REFERENCES clients(id) ON DELETE SET NULL,
  disclosure_type                 text NOT NULL,                   -- insurance: 'casl_consent' | 'pipeda_privacy' | 'conflict_of_interest' | 'replacement_form' | 'general'
  disclosure_content_template_id  text,                            -- e.g. 'casl-consent' (file in documents/templates/insurance/)
  presented_at                    timestamptz,
  acknowledged_at                 timestamptz,
  acknowledgment_method           text,                            -- 'esignature' | 'verbal_recorded' | 'written'
  esignature_id                   text,                            -- Zoho Sign envelope id
  document_url                    text,                            -- R2 URL of generated disclosure
  signed_document_url             text,                            -- R2 URL after Zoho Sign returns signed PDF
  expires_at                      timestamptz,
  created_at                      timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE compliance_disclosures
    ADD CONSTRAINT cd_method_check
    CHECK (acknowledgment_method IS NULL OR acknowledgment_method IN ('esignature','verbal_recorded','written'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_disclosures_vertical    ON compliance_disclosures(vertical_id);
CREATE INDEX IF NOT EXISTS idx_disclosures_client      ON compliance_disclosures(client_id, created_at DESC) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_disclosures_pending     ON compliance_disclosures(vertical_id, created_at DESC) WHERE acknowledged_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_disclosures_esign       ON compliance_disclosures(esignature_id) WHERE esignature_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 6. regulatory_audit_log — every regulated event, append-only
-- ─────────────────────────────────────────────────────────────────
-- All FKs are soft (no REFERENCES) so log entries survive related-row
-- deletion. Regulatory audit must be tamper-evident; cascading delete
-- would be a compliance failure.
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS regulatory_audit_log (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  event_type               text NOT NULL,                          -- e.g. 'kyc_initiated' | 'kyc_verified' | 'suitability_started' | 'suitability_completed' | 'disclosure_presented' | 'disclosure_signed' | 'application_submitted' | 'compliance_review_requested' | 'compliance_decision_recorded'
  client_id                uuid,                                   -- soft FK
  advisor_id               uuid,                                   -- soft FK
  policy_application_id    uuid,                                   -- soft FK
  performed_by_user_id     uuid,                                   -- soft FK
  performed_by_role        text,                                   -- 'agent' | 'advisor' | 'compliance_officer' | 'admin' | 'mga_principal'
  event_data               jsonb DEFAULT '{}'::jsonb,
  ip_address               text,
  user_agent               text,
  occurred_at              timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_vertical     ON regulatory_audit_log(vertical_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_client       ON regulatory_audit_log(client_id, occurred_at DESC) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_advisor      ON regulatory_audit_log(advisor_id, occurred_at DESC) WHERE advisor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_event_type   ON regulatory_audit_log(vertical_id, event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_app          ON regulatory_audit_log(policy_application_id) WHERE policy_application_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 7. policy_applications — auto-completed carrier application
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS policy_applications (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                   text NOT NULL DEFAULT 'insurance',
  client_id                     uuid REFERENCES clients(id) ON DELETE SET NULL,
  advisor_id                    uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  suitability_assessment_id     uuid REFERENCES suitability_assessments(id) ON DELETE SET NULL,
  policy_recommendation_id      uuid REFERENCES policy_recommendations(id) ON DELETE SET NULL,
  carrier_name                  text,
  application_data              jsonb DEFAULT '{}'::jsonb,         -- AI-completed fields
  fields_requiring_human_input  jsonb DEFAULT '[]'::jsonb,         -- flagged fields for advisor
  advisor_review_status         text NOT NULL DEFAULT 'pending',   -- pending | reviewed | approved | rejected
  advisor_review_notes          text,
  advisor_reviewed_at           timestamptz,
  submission_status             text NOT NULL DEFAULT 'draft',     -- draft | submitted | underwriting | issued | declined
  submitted_at                  timestamptz,
  issued_at                     timestamptz,
  policy_number                 text,
  locked                        boolean DEFAULT false,             -- true while final compliance review in flight
  created_at                    timestamptz DEFAULT now(),
  updated_at                    timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE policy_applications
    ADD CONSTRAINT pa_advisor_review_check
    CHECK (advisor_review_status IN ('pending','reviewed','approved','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE policy_applications
    ADD CONSTRAINT pa_submission_check
    CHECK (submission_status IN ('draft','submitted','underwriting','issued','declined'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_policy_app_vertical    ON policy_applications(vertical_id);
CREATE INDEX IF NOT EXISTS idx_policy_app_advisor     ON policy_applications(advisor_id, created_at DESC) WHERE advisor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_policy_app_client      ON policy_applications(client_id, created_at DESC) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_policy_app_status      ON policy_applications(vertical_id, submission_status);
CREATE INDEX IF NOT EXISTS idx_policy_app_pending     ON policy_applications(vertical_id, created_at DESC) WHERE advisor_review_status IN ('pending','reviewed');

-- ─────────────────────────────────────────────────────────────────
-- 8. RLS — service_role-only on every new table (defence in depth)
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE compliance_reviews         ENABLE ROW LEVEL SECURITY;
ALTER TABLE kyc_verifications          ENABLE ROW LEVEL SECURITY;
ALTER TABLE suitability_assessments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_recommendations     ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance_disclosures     ENABLE ROW LEVEL SECURITY;
ALTER TABLE regulatory_audit_log       ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_applications        ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN CREATE POLICY cr_service  ON compliance_reviews       FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY kv_service  ON kyc_verifications        FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY sa_service  ON suitability_assessments  FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY pr_service  ON policy_recommendations   FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY cd_service  ON compliance_disclosures   FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY ral_service ON regulatory_audit_log     FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY pa_service  ON policy_applications      FOR ALL TO service_role USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 9. Verification queries (run manually after migration)
-- ─────────────────────────────────────────────────────────────────

-- SELECT tablename FROM pg_tables WHERE tablename IN ('compliance_reviews','kyc_verifications','suitability_assessments','policy_recommendations','compliance_disclosures','regulatory_audit_log','policy_applications') ORDER BY tablename;
-- SELECT column_default FROM information_schema.columns WHERE column_name = 'vertical_id' AND table_name IN ('compliance_reviews','kyc_verifications','suitability_assessments','policy_recommendations','compliance_disclosures','regulatory_audit_log','policy_applications');
-- SELECT count(*) FROM compliance_reviews;  -- 0 expected
-- SELECT count(*) FROM kyc_verifications;   -- 0 expected
-- SELECT count(*) FROM suitability_assessments;
-- SELECT count(*) FROM policy_recommendations;
-- SELECT count(*) FROM compliance_disclosures;
-- SELECT count(*) FROM regulatory_audit_log;
-- SELECT count(*) FROM policy_applications;

-- ═════════════════════════════════════════════════════════════════
-- ROLLBACK (commented — uncomment + run only to roll back)
-- ═════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS policy_applications;
-- DROP TABLE IF EXISTS regulatory_audit_log;
-- DROP TABLE IF EXISTS compliance_disclosures;
-- DROP TABLE IF EXISTS policy_recommendations;
-- DROP TABLE IF EXISTS suitability_assessments;
-- DROP TABLE IF EXISTS kyc_verifications;
-- DROP TABLE IF EXISTS compliance_reviews;
