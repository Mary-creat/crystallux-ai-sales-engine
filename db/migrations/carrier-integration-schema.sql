-- ══════════════════════════════════════════════════════════════════
-- Carrier Integration Foundation (Layer 2 — Insurance MGA)
-- ══════════════════════════════════════════════════════════════════
-- Replaces the hardcoded 7-product matrix in
-- clx-mga-insurance-policy-recommendation-engine-v1 with a real
-- carriers + products schema, so v2 can rank actual carrier products
-- instead of static example data.
--
-- LAYER 2 / vertical_id tagging:
--   Every table carries `vertical_id text NOT NULL DEFAULT 'insurance'`
--   so future verticals (mortgage carriers, P&C carriers, etc.) plug
--   in without schema migration pain.
--
-- Auth: writes are gated by mga_principal/admin in workflows; reads
-- are open within the tenant.
--
-- Additive only. Idempotent. Rollback at bottom.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. insurance_carriers — Canadian carriers an MGA can place with
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS insurance_carriers (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id             text NOT NULL DEFAULT 'insurance',
  carrier_name            text NOT NULL,
  carrier_code            text,                                -- internal code (eg MANULIFE, SUNLIFE)
  carrier_type            text NOT NULL,                        -- life | p_and_c | health | specialty | mga_wholesaler
  province_licensed       jsonb DEFAULT '[]'::jsonb,            -- ['ON','BC','AB',...]
  ai_compliance_ready     boolean DEFAULT false,                -- carrier accepts AI-pre-screened applications
  digital_quote_ready     boolean DEFAULT false,                -- supports digital quoting (API or portal)
  api_endpoint            text,                                 -- if integration_type='api'
  api_auth_type           text,                                 -- bearer | basic | oauth2 | mtls | null
  contact_email           text,
  contact_phone           text,
  notes                   text,
  active                  boolean DEFAULT true,
  created_at              timestamptz DEFAULT now(),
  updated_at              timestamptz DEFAULT now(),
  UNIQUE (vertical_id, carrier_name)
);

DO $$ BEGIN
  ALTER TABLE insurance_carriers
    ADD CONSTRAINT ic_type_check
    CHECK (carrier_type IN ('life','p_and_c','health','specialty','mga_wholesaler'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ic_active
  ON insurance_carriers(vertical_id, active, ai_compliance_ready);

-- ─────────────────────────────────────────────────────────────────
-- 2. carrier_products — catalog rows per carrier
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS carrier_products (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id             text NOT NULL DEFAULT 'insurance',
  carrier_id              uuid NOT NULL REFERENCES insurance_carriers(id) ON DELETE CASCADE,
  product_name            text NOT NULL,
  product_type            text NOT NULL,                        -- term_life | whole_life | universal_life | critical_illness | disability | auto | home | tenant | commercial | travel | dental | vision | super_visa
  product_code            text,
  min_coverage_cents      bigint,
  max_coverage_cents      bigint,
  base_premium_cents      bigint,
  premium_formula         jsonb,                                -- structured rules for derived premium estimates
  underwriting_min_age    integer,
  underwriting_max_age    integer,
  underwriting_notes      text,
  commission_pct          numeric(5,2),
  commission_first_year   numeric(5,2),
  commission_renewal      numeric(5,2),
  ai_compliance_ready     boolean DEFAULT false,
  features                jsonb DEFAULT '[]'::jsonb,            -- list of feature strings for comparison UI
  active                  boolean DEFAULT true,
  created_at              timestamptz DEFAULT now(),
  updated_at              timestamptz DEFAULT now(),
  UNIQUE (carrier_id, product_name)
);

CREATE INDEX IF NOT EXISTS idx_cp_lookup
  ON carrier_products(vertical_id, product_type, active)
  WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_cp_ai_ready
  ON carrier_products(vertical_id, product_type)
  WHERE ai_compliance_ready = true AND active = true;

-- ─────────────────────────────────────────────────────────────────
-- 3. carrier_integrations — per-MGA-client integration configuration
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS carrier_integrations (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id          text NOT NULL DEFAULT 'insurance',
  carrier_id           uuid NOT NULL REFERENCES insurance_carriers(id) ON DELETE CASCADE,
  client_id            uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  integration_type     text NOT NULL,                           -- manual | email | api | portal
  credentials_encrypted text,                                   -- AES-256-GCM ciphertext if api/portal
  contracting_number   text,                                    -- MGA's contracting number with carrier
  last_sync_at         timestamptz,
  sync_status          text DEFAULT 'idle',                     -- idle | syncing | error
  sync_error           text,
  active               boolean DEFAULT true,
  created_at           timestamptz DEFAULT now(),
  updated_at           timestamptz DEFAULT now(),
  UNIQUE (carrier_id, client_id)
);

DO $$ BEGIN
  ALTER TABLE carrier_integrations
    ADD CONSTRAINT ci_integration_type_check
    CHECK (integration_type IN ('manual','email','api','portal'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE carrier_integrations
    ADD CONSTRAINT ci_sync_status_check
    CHECK (sync_status IN ('idle','syncing','error'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 4. carrier_quotes — every quote received from a carrier
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS carrier_quotes (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                 text NOT NULL DEFAULT 'insurance',
  client_id                   uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  lead_id                     uuid REFERENCES leads(id) ON DELETE SET NULL,
  carrier_id                  uuid NOT NULL REFERENCES insurance_carriers(id),
  product_id                  uuid REFERENCES carrier_products(id),
  suitability_assessment_id   uuid,                              -- soft FK to suitability_assessments.id
  quote_amount_cents          bigint,                            -- coverage amount
  quote_premium_monthly_cents bigint,
  quote_premium_annual_cents  bigint,
  quote_term_years            integer,
  quote_source                text NOT NULL DEFAULT 'manual',    -- manual | api | email_parsed
  quote_data                  jsonb DEFAULT '{}'::jsonb,         -- raw quote payload from carrier
  quote_received_at           timestamptz,
  quote_expires_at            timestamptz,
  status                      text NOT NULL DEFAULT 'pending',   -- pending | received | expired | bound | declined
  decline_reason              text,
  bound_at                    timestamptz,
  created_by_user_id          uuid REFERENCES auth_users(id) ON DELETE SET NULL,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now()
);

DO $$ BEGIN
  ALTER TABLE carrier_quotes
    ADD CONSTRAINT cq_source_check
    CHECK (quote_source IN ('manual','api','email_parsed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE carrier_quotes
    ADD CONSTRAINT cq_status_check
    CHECK (status IN ('pending','received','expired','bound','declined'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_cq_lead
  ON carrier_quotes(lead_id, status);

CREATE INDEX IF NOT EXISTS idx_cq_pending
  ON carrier_quotes(client_id, status, created_at DESC)
  WHERE status = 'pending';

-- ══════════════════════════════════════════════════════════════════
-- Rollback (commented — uncomment one block to revert)
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS carrier_quotes;
-- DROP TABLE IF EXISTS carrier_integrations;
-- DROP TABLE IF EXISTS carrier_products;
-- DROP TABLE IF EXISTS insurance_carriers;
