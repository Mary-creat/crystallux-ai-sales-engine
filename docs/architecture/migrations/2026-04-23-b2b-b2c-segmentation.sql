-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX B2B/B2C SEGMENTATION — SCHEMA SCAFFOLDING (Task 2)
-- File: docs/architecture/migrations/2026-04-23-b2b-b2c-segmentation.sql
--
-- Adds the schema surface the Campaign Router v2 / Lead Research v2 /
-- Outreach Generation v2 segment-aware hooks write and read. No live
-- routing changes are executed by this migration — it only provisions
-- the columns and indexes. Workflow logic is shipped in the same
-- commit but is dormant until each workflow's segment logic is
-- exercised by a real lead with a segment classification.
--
-- Idempotent — safe to re-run. All column adds use IF NOT EXISTS,
-- check constraints are guarded with DO blocks, and policies are
-- DROP ... IF EXISTS before CREATE.
--
-- Runs AFTER:
--   * 2026-04-23-apollo-schema.sql
--   * 2026-04-23-multi-channel.sql
--   * 2026-04-23-video-schema.sql
--
-- Rollback SQL at the bottom (commented).
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. NICHE OVERLAY — TARGET TYPE + DISCOVERY SOURCES
-- ─────────────────────────────────────────────────────────────────
-- lead_target_type       — 'b2b' | 'b2c' | 'mixed'. Drives whether
--                          Apollo is invoked during Lead Research and
--                          which lead_segments branch is preferred.
-- lead_discovery_sources — jsonb array of enrichment provider keys the
--                          research workflow may call for this niche.
--                          B2B niches prefer apollo_company / linkedin;
--                          B2C niches prefer google_maps / facebook_local.

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS lead_target_type       text DEFAULT 'mixed',
  ADD COLUMN IF NOT EXISTS lead_discovery_sources jsonb DEFAULT '["city_scan","google_maps"]'::jsonb;

-- Check constraint is guarded — if it already exists from an earlier
-- partial run, skip re-adding.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'niche_overlays_lead_target_type_check'
  ) THEN
    ALTER TABLE niche_overlays
      ADD CONSTRAINT niche_overlays_lead_target_type_check
      CHECK (lead_target_type IN ('b2b','b2c','mixed'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_niche_overlays_target_type
  ON niche_overlays(lead_target_type);


-- ─────────────────────────────────────────────────────────────────
-- 2. CLIENTS — FOCUS SEGMENTS ALLOWLIST
-- ─────────────────────────────────────────────────────────────────
-- Per-client allowlist. An insurance broker client who only wants
-- commercial leads keeps focus_segments = '["commercial"]' and the
-- router suppresses any residential-classified lead for that client,
-- even when the niche overlay is 'mixed'.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS focus_segments jsonb
    DEFAULT '["residential","commercial"]'::jsonb;


-- ─────────────────────────────────────────────────────────────────
-- 3. LEADS — CLASSIFIED SEGMENT
-- ─────────────────────────────────────────────────────────────────
-- Written by the Campaign Router's new Decide Segment node. Static
-- heuristics (company_size > 1, personal-email domains, LinkedIn +
-- Apollo org presence) assign one of three values. 'unknown' is the
-- safe default — the router logs SEGMENT_CLASSIFICATION_UNKNOWN to
-- scan_errors when it can't classify, and skips the segment-aware
-- channel preference in that case.

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS lead_segment text DEFAULT 'unknown';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'leads_lead_segment_check'
  ) THEN
    ALTER TABLE leads
      ADD CONSTRAINT leads_lead_segment_check
      CHECK (lead_segment IN ('residential','commercial','unknown'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_leads_segment ON leads(lead_segment);


-- ─────────────────────────────────────────────────────────────────
-- 4. UPDATE insurance_broker OVERLAY
-- ─────────────────────────────────────────────────────────────────
-- The live schema uses niche_name as the overlay key. The queued
-- vertical-seeding spec references `vertical`. We update by whichever
-- column exists — the WHERE clause tolerates either being absent.
-- Guarded UPDATE: only applies when the columns are still at their
-- defaults, so Mary's hand-edits aren't clobbered on a re-run.

UPDATE niche_overlays
SET
  lead_target_type = 'mixed',
  lead_discovery_sources = '["city_scan","apollo_company","google_maps","linkedin","industry_directories"]'::jsonb,
  offer_mapping = jsonb_set(
    COALESCE(offer_mapping, '{}'::jsonb),
    '{lead_segments}',
    '{
      "residential": {
        "target": "Homeowners shopping auto/home insurance at renewal",
        "pain_angles": [
          "renewal shock",
          "rate shopping fatigue",
          "claims denial fears",
          "coverage gaps"
        ],
        "channels": ["sms","email","voice"]
      },
      "commercial": {
        "target": "Business owners needing commercial policy renewal",
        "pain_angles": [
          "rising premiums",
          "claims history concerns",
          "coverage audits",
          "compliance requirements"
        ],
        "channels": ["email","linkedin","voice"]
      }
    }'::jsonb,
    true
  )
WHERE niche_name = 'insurance_broker'
  AND (lead_target_type IS NULL OR lead_target_type = 'mixed')
  AND (offer_mapping IS NULL OR NOT (offer_mapping ? 'lead_segments'));


-- ─────────────────────────────────────────────────────────────────
-- 5. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 2
SELECT 'niche_overlays segmentation columns' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'niche_overlays'
  AND column_name IN ('lead_target_type','lead_discovery_sources');

-- Expect 1
SELECT 'clients.focus_segments' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'clients' AND column_name = 'focus_segments';

-- Expect 1
SELECT 'leads.lead_segment' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'leads' AND column_name = 'lead_segment';

-- Expect 2 (both check constraints present)
SELECT 'segmentation check constraints' AS check_name,
       COUNT(*) AS present
FROM pg_constraint
WHERE conname IN (
  'niche_overlays_lead_target_type_check',
  'leads_lead_segment_check'
);

-- Expect 2 (both indexes present)
SELECT 'segmentation indexes' AS check_name,
       COUNT(*) AS present
FROM pg_indexes
WHERE indexname IN ('idx_niche_overlays_target_type','idx_leads_segment');

-- Expect 1 row with lead_target_type='mixed' and lead_segments keys
SELECT niche_name,
       lead_target_type,
       jsonb_array_length(lead_discovery_sources) AS sources_count,
       offer_mapping->'lead_segments' ? 'residential' AS has_residential,
       offer_mapping->'lead_segments' ? 'commercial'  AS has_commercial
FROM niche_overlays
WHERE niche_name = 'insurance_broker';


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo — test on staging first)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 4. Revert insurance_broker overlay
-- UPDATE niche_overlays
-- SET offer_mapping      = offer_mapping - 'lead_segments',
--     lead_target_type   = NULL,
--     lead_discovery_sources = '["city_scan","google_maps"]'::jsonb
-- WHERE niche_name = 'insurance_broker';
--
-- -- 3. Leads segment
-- DROP INDEX IF EXISTS idx_leads_segment;
-- ALTER TABLE leads DROP CONSTRAINT IF EXISTS leads_lead_segment_check;
-- ALTER TABLE leads DROP COLUMN IF EXISTS lead_segment;
--
-- -- 2. Clients focus segments
-- ALTER TABLE clients DROP COLUMN IF EXISTS focus_segments;
--
-- -- 1. Niche overlay segmentation columns
-- DROP INDEX IF EXISTS idx_niche_overlays_target_type;
-- ALTER TABLE niche_overlays
--   DROP CONSTRAINT IF EXISTS niche_overlays_lead_target_type_check;
-- ALTER TABLE niche_overlays
--   DROP COLUMN IF EXISTS lead_target_type,
--   DROP COLUMN IF EXISTS lead_discovery_sources;
