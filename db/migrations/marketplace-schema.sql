-- Insurance Comparison Marketplace — schema migration
-- =====================================================
-- Adds two tables + extends leads to support the multi-carrier
-- premium-comparison flow described in the marketplace spec.
--
-- Flow recap:
--   1. Visitor fills /compare/<vertical>.html form
--   2. clx-mga-insurance-quote-comparison-v1 generates 4-6 estimated
--      premiums (one per seeded carrier) and writes a row per quote
--      into marketplace_quotes
--   3. Page renders comparison table with lowest highlighted
--   4. User clicks "Get this quote" -> clx-mga-insurance-quote-select-v1
--      writes marketplace_quote_selections row + flips lead to hot_lead +
--      kicks the advisor router
--
-- Idempotent: safe to re-run. ADD COLUMN IF NOT EXISTS + CREATE TABLE
-- IF NOT EXISTS guards every statement.
--
-- Applied: 2026-05-27

BEGIN;

-- Marketplace quotes — one row per estimated quote shown to a lead
CREATE TABLE IF NOT EXISTS marketplace_quotes (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id                     UUID REFERENCES leads(id) ON DELETE CASCADE,
  source_domain               TEXT,
  vertical                    TEXT NOT NULL,
  carrier_name                TEXT NOT NULL,
  carrier_id                  UUID REFERENCES insurance_carriers(id),
  estimated_premium_monthly   NUMERIC(10, 2),
  estimated_premium_annual    NUMERIC(10, 2),
  coverage_summary            JSONB,
  is_lowest                   BOOLEAN DEFAULT false,
  rank_position               INTEGER,
  estimate_disclaimer         TEXT DEFAULT 'Estimated premiums only. Final pricing subject to underwriting and insurer approval.',
  created_at                  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS marketplace_quotes_lead_idx
  ON marketplace_quotes (lead_id);

CREATE INDEX IF NOT EXISTS marketplace_quotes_vertical_created_idx
  ON marketplace_quotes (vertical, created_at DESC);

-- Quote selections — fires when user clicks "Get this quote"
CREATE TABLE IF NOT EXISTS marketplace_quote_selections (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  marketplace_quote_id     UUID REFERENCES marketplace_quotes(id) ON DELETE CASCADE,
  lead_id                  UUID REFERENCES leads(id) ON DELETE CASCADE,
  advisor_assigned_to      UUID REFERENCES auth_users(id),
  selected_at              TIMESTAMPTZ DEFAULT now(),
  call_initiated_at        TIMESTAMPTZ,
  contact_method           TEXT,
  outcome                  TEXT,
  notes                    TEXT,
  updated_at               TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS marketplace_selections_lead_idx
  ON marketplace_quote_selections (lead_id);

CREATE INDEX IF NOT EXISTS marketplace_selections_advisor_idx
  ON marketplace_quote_selections (advisor_assigned_to, selected_at DESC);

-- Leads extensions — marketplace metadata + white-label tracking
ALTER TABLE leads ADD COLUMN IF NOT EXISTS marketplace_vertical TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS marketplace_selected_carrier_name TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS marketplace_status TEXT;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS source_domain TEXT;

-- marketplace_status flow:
--   new -> quote_viewed -> quote_selected -> hot_lead ->
--   advisor_assigned -> contacted -> quoted -> closed | lost

-- RLS — match documented Crystallux pattern. Service-role only.
ALTER TABLE marketplace_quotes ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'marketplace_quotes'
      AND policyname = 'Service role full access on marketplace_quotes'
  ) THEN
    CREATE POLICY "Service role full access on marketplace_quotes"
      ON marketplace_quotes
      FOR ALL
      USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

ALTER TABLE marketplace_quote_selections ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'marketplace_quote_selections'
      AND policyname = 'Service role full access on marketplace_quote_selections'
  ) THEN
    CREATE POLICY "Service role full access on marketplace_quote_selections"
      ON marketplace_quote_selections
      FOR ALL
      USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

COMMIT;

-- Verify
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name IN ('marketplace_quotes', 'marketplace_quote_selections')
   OR (table_name = 'leads' AND column_name LIKE 'marketplace_%')
   OR (table_name = 'leads' AND column_name = 'source_domain')
ORDER BY table_name, ordinal_position;
