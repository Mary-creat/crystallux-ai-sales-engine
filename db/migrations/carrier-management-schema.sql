-- ══════════════════════════════════════════════════════════════════
-- Carrier Management (Operations) — Layer 1 (universal)
-- ══════════════════════════════════════════════════════════════════
-- Operational carrier ops layer: appointment lifecycle, submission
-- pipeline, commission expectations, monthly reconciliations.
--
-- DISTINCT FROM `insurance_carriers` (Layer 2 product registry):
--   - insurance_carriers (vertical_id='insurance'): product/availability
--     metadata used by the policy-recommendation engine.
--   - carriers (this table, no vertical_id): the MGA's operational
--     relationship with each carrier — applied? approved? our agent
--     code? expected commission %?
--   Soft FK: carriers.carrier_code ↔ insurance_carriers.carrier_code.
--   When the insurance vertical wants to know "which carriers can I
--   actually place with right now?", join the two on carrier_code
--   filtered by carriers.appointment_status='active'.
--
-- All tables tenant-scoped on client_id so multiple MGA tenants can
-- track their own appointments without leakage.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- 1. carriers — operational registry per tenant
CREATE TABLE IF NOT EXISTS carriers (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  carrier_code                text NOT NULL,
  carrier_name                text NOT NULL,
  carrier_type                text NOT NULL,                  -- life | p_and_c | health | specialty | mga_wholesaler | digital_direct
  appointment_status          text NOT NULL DEFAULT 'not_applied',
  appointment_applied_at      timestamptz,
  appointment_approved_at     timestamptz,
  appointment_effective_at    timestamptz,
  appointment_terminated_at   timestamptz,
  termination_reason          text,
  agent_code                  text,
  contracted_lines            jsonb DEFAULT '[]'::jsonb,      -- ['term_life','whole_life','critical_illness',...]
  province_authorized         jsonb DEFAULT '[]'::jsonb,
  contact_name                text,
  contact_email               text,
  contact_phone               text,
  expected_commission_pct     numeric(5,2),
  notes                       text,
  active                      boolean DEFAULT true,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now(),
  UNIQUE (client_id, carrier_code)
);

DO $$ BEGIN
  ALTER TABLE carriers
    ADD CONSTRAINT carriers_status_check
    CHECK (appointment_status IN ('not_applied','pending','approved','active','suspended','terminated'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE carriers
    ADD CONSTRAINT carriers_type_check
    CHECK (carrier_type IN ('life','p_and_c','health','specialty','mga_wholesaler','digital_direct'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_carriers_client_status
  ON carriers(client_id, appointment_status);

CREATE INDEX IF NOT EXISTS idx_carriers_active
  ON carriers(client_id, carrier_name)
  WHERE appointment_status = 'active';

-- 2. carrier_submissions — pipeline tracking per policy application
CREATE TABLE IF NOT EXISTS carrier_submissions (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  carrier_id                  uuid NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
  lead_id                     uuid REFERENCES leads(id) ON DELETE SET NULL,
  policy_application_id       uuid,                            -- soft FK to policy_applications (insurance vertical)
  advisor_id                  uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  product_line                text,                            -- term_life | whole_life | critical_illness | auto | home | commercial | ...
  submission_status           text NOT NULL DEFAULT 'in_progress',
  submitted_at                timestamptz,
  underwriting_decision_at    timestamptz,
  policy_issued_at            timestamptz,
  policy_number               text,
  applicant_name              text,
  face_amount_cents           bigint,
  annual_premium_cents        bigint,
  expected_commission_cents   bigint,
  decline_reason              text,
  notes                       text,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE carrier_submissions
    ADD CONSTRAINT submissions_status_check
    CHECK (submission_status IN ('in_progress','submitted','underwriting','approved','declined','issued','not_taken','withdrawn'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_submissions_carrier_status
  ON carrier_submissions(carrier_id, submission_status);

CREATE INDEX IF NOT EXISTS idx_submissions_advisor
  ON carrier_submissions(advisor_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_submissions_pipeline
  ON carrier_submissions(client_id, submission_status, created_at DESC);

-- 3. carrier_commissions — expected commission tracking per submission
CREATE TABLE IF NOT EXISTS carrier_commissions (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  carrier_id                  uuid NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
  submission_id               uuid REFERENCES carrier_submissions(id) ON DELETE SET NULL,
  commission_type             text NOT NULL DEFAULT 'first_year',
  commission_year             int DEFAULT 1,
  expected_amount_cents       bigint NOT NULL,
  expected_at                 date,
  received_amount_cents       bigint,
  received_at                 date,
  reconciliation_id           uuid,                            -- backfilled by reconciliation workflow
  status                      text NOT NULL DEFAULT 'expected',
  notes                       text,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE carrier_commissions
    ADD CONSTRAINT commissions_type_check
    CHECK (commission_type IN ('first_year','renewal','trail','bonus','clawback'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE carrier_commissions
    ADD CONSTRAINT commissions_status_check
    CHECK (status IN ('expected','received','underpaid','overpaid','disputed','written_off'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_commissions_carrier_status
  ON carrier_commissions(carrier_id, status, expected_at);

CREATE INDEX IF NOT EXISTS idx_commissions_outstanding
  ON carrier_commissions(client_id, status)
  WHERE status IN ('expected','underpaid');

CREATE INDEX IF NOT EXISTS idx_commissions_submission
  ON carrier_commissions(submission_id);

-- 4. carrier_reconciliations — monthly statement matching
CREATE TABLE IF NOT EXISTS carrier_reconciliations (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  carrier_id                  uuid NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
  reconciliation_period       text NOT NULL,                   -- e.g. '2026-05' (YYYY-MM)
  statement_received_at       timestamptz,
  statement_amount_cents      bigint NOT NULL,
  matched_commissions_cents   bigint DEFAULT 0,
  status                      text NOT NULL DEFAULT 'pending',
  statement_url               text,                            -- where the PDF lives if uploaded
  reconciled_by               uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  reconciled_at               timestamptz,
  notes                       text,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now(),
  UNIQUE (carrier_id, reconciliation_period)
);

DO $$ BEGIN
  ALTER TABLE carrier_reconciliations
    ADD CONSTRAINT recon_status_check
    CHECK (status IN ('pending','partial','matched','discrepancy','disputed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_recon_period
  ON carrier_reconciliations(client_id, reconciliation_period DESC);

CREATE INDEX IF NOT EXISTS idx_recon_outstanding
  ON carrier_reconciliations(client_id, status)
  WHERE status IN ('pending','partial','discrepancy');

-- ══════════════════════════════════════════════════════════════════
-- Seed: 20 major Canadian carriers + 3 digital targets
-- All under the Crystallux Financial Services tenant.
-- ══════════════════════════════════════════════════════════════════
-- 'not_applied' status — Mary updates to 'pending' when she submits
-- the appointment application, 'approved' when MGA agreement is
-- signed, 'active' once she has an agent code and can write business.
-- ══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_client uuid := '6edc687d-07b0-4478-bb4b-820dc4eebf5d'::uuid;  -- Crystallux Financial Services tenant
BEGIN
  -- Life carriers (10)
  INSERT INTO carriers (client_id, carrier_code, carrier_name, carrier_type, appointment_status, contracted_lines) VALUES
    (v_client, 'MANULIFE',          'Manulife',            'life',      'not_applied', '["term_life","whole_life","universal_life","critical_illness","disability"]'::jsonb),
    (v_client, 'SUNLIFE',           'Sun Life',            'life',      'not_applied', '["term_life","whole_life","universal_life","critical_illness","disability","group_benefits"]'::jsonb),
    (v_client, 'CANADALIFE',        'Canada Life',         'life',      'not_applied', '["term_life","whole_life","critical_illness","disability","group_benefits"]'::jsonb),
    (v_client, 'IA',                'iA Financial',        'life',      'not_applied', '["term_life","whole_life","critical_illness","disability"]'::jsonb),
    (v_client, 'EMPIRELIFE',        'Empire Life',         'life',      'not_applied', '["term_life","whole_life","critical_illness"]'::jsonb),
    (v_client, 'EQUITABLE',         'Equitable Life',      'life',      'not_applied', '["term_life","whole_life","critical_illness"]'::jsonb),
    (v_client, 'RBCINS',            'RBC Insurance',       'life',      'not_applied', '["term_life","whole_life","critical_illness","disability","travel"]'::jsonb),
    (v_client, 'DESJARDINS',        'Desjardins Insurance','life',      'not_applied', '["term_life","whole_life","critical_illness","auto","home"]'::jsonb),
    (v_client, 'BENEVA',            'Beneva',              'life',      'not_applied', '["term_life","whole_life","critical_illness","auto","home"]'::jsonb),
    (v_client, 'FORESTERS',         'Foresters Financial', 'life',      'not_applied', '["term_life","whole_life"]'::jsonb)
  ON CONFLICT (client_id, carrier_code) DO NOTHING;

  -- P&C carriers (7)
  INSERT INTO carriers (client_id, carrier_code, carrier_name, carrier_type, appointment_status, contracted_lines) VALUES
    (v_client, 'INTACT',            'Intact Insurance',    'p_and_c',   'not_applied', '["auto","home","commercial"]'::jsonb),
    (v_client, 'AVIVA',             'Aviva Canada',        'p_and_c',   'not_applied', '["auto","home","commercial"]'::jsonb),
    (v_client, 'WAWANESA',          'Wawanesa Mutual',     'p_and_c',   'not_applied', '["auto","home"]'::jsonb),
    (v_client, 'DEFINITY',          'Definity Insurance',  'p_and_c',   'not_applied', '["auto","home","commercial"]'::jsonb),
    (v_client, 'TRAVELERS',         'Travelers Canada',    'p_and_c',   'not_applied', '["commercial","specialty"]'::jsonb),
    (v_client, 'CAAINS',            'CAA Insurance',       'p_and_c',   'not_applied', '["auto","home"]'::jsonb),
    (v_client, 'GOREMUTUAL',        'Gore Mutual',         'p_and_c',   'not_applied', '["auto","home"]'::jsonb)
  ON CONFLICT (client_id, carrier_code) DO NOTHING;

  -- Specialty / wholesale (3)
  INSERT INTO carriers (client_id, carrier_code, carrier_name, carrier_type, appointment_status, contracted_lines) VALUES
    (v_client, 'NORTHBRIDGE',       'Northbridge Insurance','specialty','not_applied', '["commercial","fleet","specialty"]'::jsonb),
    (v_client, 'BEAZLEY',           'Beazley',             'specialty', 'not_applied', '["cyber","professional_liability","specialty"]'::jsonb),
    (v_client, 'CFC',               'CFC Underwriting',    'specialty', 'not_applied', '["cyber","professional_liability","specialty"]'::jsonb)
  ON CONFLICT (client_id, carrier_code) DO NOTHING;

  -- Digital-direct targets — already in 'pending' (Mary identified these as priority appointments)
  INSERT INTO carriers (client_id, carrier_code, carrier_name, carrier_type, appointment_status, appointment_applied_at, contracted_lines, notes) VALUES
    (v_client, 'POLICYME',          'PolicyMe',            'digital_direct', 'pending', now(), '["term_life","critical_illness"]'::jsonb, 'Target carrier — direct-to-consumer life specialist with API quoting. Priority appointment.'),
    (v_client, 'WALNUT',            'Walnut',              'digital_direct', 'pending', now(), '["term_life"]'::jsonb,                    'Target carrier — embeddable life insurance API. Priority appointment.'),
    (v_client, 'APOLLO',            'Apollo Insurance',    'digital_direct', 'pending', now(), '["commercial"]'::jsonb,                    'Target carrier — digital commercial P&C. Priority appointment.')
  ON CONFLICT (client_id, carrier_code) DO NOTHING;
END $$;

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented)
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS carrier_reconciliations;
-- DROP TABLE IF EXISTS carrier_commissions;
-- DROP TABLE IF EXISTS carrier_submissions;
-- DROP TABLE IF EXISTS carriers;
