-- ══════════════════════════════════════════════════════════════════
-- Insurance White-Label Configurations (Layer 2 — Insurance MGA)
-- ══════════════════════════════════════════════════════════════════
-- Foundation for insurers to white-label the Crystallux platform.
-- Auto-deployment of custom domain + SSL is a manual-then-automated
-- pathway; this schema captures the config + state.
--
-- Every table tagged vertical_id text NOT NULL DEFAULT 'insurance'.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS insurer_whitelabel_configs (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vertical_id                text NOT NULL DEFAULT 'insurance',
  insurer_account_id         uuid NOT NULL REFERENCES insurer_accounts(id) ON DELETE CASCADE,
  branding_config            jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- { primary_color, secondary_color, logo_url, favicon_url,
  --   company_name, footer_text, email_from }
  custom_domain              text,
  ssl_certificate_status     text DEFAULT 'pending',                  -- pending | issuing | issued | failed
  feature_overrides          jsonb DEFAULT '{}'::jsonb,
  pricing_tier               text DEFAULT 'standard',                 -- standard | premium | enterprise
  contract_start_date        date,
  contract_end_date          date,
  monthly_fee_cents          bigint,
  active                     boolean DEFAULT true,
  deployed_at                timestamptz,
  created_at                 timestamptz DEFAULT now(),
  updated_at                 timestamptz DEFAULT now(),
  UNIQUE (insurer_account_id)
);

DO $$ BEGIN
  ALTER TABLE insurer_whitelabel_configs
    ADD CONSTRAINT iwc_ssl_check
    CHECK (ssl_certificate_status IN ('pending','issuing','issued','failed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE insurer_whitelabel_configs
    ADD CONSTRAINT iwc_pricing_check
    CHECK (pricing_tier IN ('standard','premium','enterprise'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_iwc_active
  ON insurer_whitelabel_configs(active, vertical_id);

CREATE INDEX IF NOT EXISTS idx_iwc_domain
  ON insurer_whitelabel_configs(custom_domain)
  WHERE custom_domain IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════
-- Rollback
-- ══════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS insurer_whitelabel_configs;
