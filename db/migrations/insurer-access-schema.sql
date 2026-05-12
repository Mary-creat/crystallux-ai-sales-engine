-- ══════════════════════════════════════════════════════════════════
-- Insurer Access Schema (Layer 2 — Insurance MGA)
-- ══════════════════════════════════════════════════════════════════
-- Carrier-facing READ-ONLY access. Insurers (Manulife, Sun Life, etc.)
-- see their production through Crystallux without write capability.
-- Every access logged for regulatory audit (insurer_access_log is
-- append-only).
--
-- Every table tagged vertical_id text NOT NULL DEFAULT 'insurance'.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS insurer_accounts (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  carrier_id               uuid NOT NULL REFERENCES insurance_carriers(id) ON DELETE CASCADE,
  company_name             text NOT NULL,
  contact_name             text,
  contact_email            text NOT NULL,
  contact_phone            text,
  account_type             text NOT NULL DEFAULT 'partner',          -- partner | prospect | demo | audit
  access_level             text NOT NULL DEFAULT 'standard',         -- limited | standard | comprehensive | full
  account_status           text NOT NULL DEFAULT 'active',           -- active | suspended | expired | pending
  agreement_signed_at      timestamptz,
  agreement_expires_at     timestamptz,
  data_sharing_consent     jsonb DEFAULT '{}'::jsonb,                -- { production_reports, advisor_performance, compliance_data, client_demographics, individual_client_data }
  custom_branding          jsonb DEFAULT '{}'::jsonb,
  api_access_enabled       boolean DEFAULT false,
  api_key_encrypted        text,
  webhook_url              text,
  created_at               timestamptz DEFAULT now(),
  created_by               uuid REFERENCES auth_users(id),
  updated_at               timestamptz DEFAULT now(),
  UNIQUE (vertical_id, carrier_id, company_name)
);

DO $$ BEGIN
  ALTER TABLE insurer_accounts
    ADD CONSTRAINT ia_account_type_check
    CHECK (account_type IN ('partner','prospect','demo','audit'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE insurer_accounts
    ADD CONSTRAINT ia_access_level_check
    CHECK (access_level IN ('limited','standard','comprehensive','full'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE insurer_accounts
    ADD CONSTRAINT ia_status_check
    CHECK (account_status IN ('active','suspended','expired','pending'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_ia_carrier        ON insurer_accounts(carrier_id);
CREATE INDEX IF NOT EXISTS idx_ia_status         ON insurer_accounts(account_status);

CREATE TABLE IF NOT EXISTS insurer_users (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  insurer_account_id       uuid NOT NULL REFERENCES insurer_accounts(id) ON DELETE CASCADE,
  user_id                  uuid NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
  role_at_insurer          text,                                    -- mga_relations | compliance | sales_operations | executive | audit
  permissions              jsonb DEFAULT '{}'::jsonb,
  last_login               timestamptz,
  is_active                boolean DEFAULT true,
  created_at               timestamptz DEFAULT now(),
  UNIQUE (insurer_account_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_iu_account  ON insurer_users(insurer_account_id);
CREATE INDEX IF NOT EXISTS idx_iu_user     ON insurer_users(user_id);

-- Append-only — every insurer action is logged for regulatory audit.
CREATE TABLE IF NOT EXISTS insurer_access_log (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id              text NOT NULL DEFAULT 'insurance',
  insurer_account_id       uuid NOT NULL,                            -- soft FK (append-only — no cascade)
  user_id                  uuid,                                     -- soft FK
  action                   text NOT NULL,                            -- login | view_report | export_data | view_compliance | view_advisor | etc.
  resource_type            text,
  resource_id              text,
  ip_address               text,
  user_agent               text,
  session_id               text,
  data_accessed_summary    text,
  created_at               timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ial_account_time
  ON insurer_access_log(insurer_account_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ial_user_time
  ON insurer_access_log(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ial_action
  ON insurer_access_log(action, created_at DESC);

-- ══════════════════════════════════════════════════════════════════
-- Rollback
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS insurer_access_log;
-- DROP TABLE IF EXISTS insurer_users;
-- DROP TABLE IF EXISTS insurer_accounts;
