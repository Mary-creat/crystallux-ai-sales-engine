-- ============================================================
-- Vertical context, step 1 of 5 — configuration columns
--
-- Adds two JSONB columns to niche_overlays. Nothing else.
-- No transaction wrapper: each statement commits on its own, so a
-- failure here cannot silently undo anything that already worked.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS. Re-running is a no-op.
-- Existing data untouched — both columns default to '{}'.
-- ============================================================

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS behavior_config jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE niche_overlays
  ADD COLUMN IF NOT EXISTS sales_process_config jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN niche_overlays.behavior_config IS 'Industry buyer model: signal_types, signal_weights, intent_rules, qualification_rules, objection_handling, terminology, message_length. GLOBAL industry knowledge only; per-tenant learning belongs in client_icp_profiles.';

COMMENT ON COLUMN niche_overlays.sales_process_config IS 'Stage sequence and conversion definition: sales_process, followup_cadence, channel_strategy, conversion_event, average_sales_cycle_days, cta_types.';

-- ---- VERIFY: expect 2 rows, and total_columns = 24 ----
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'niche_overlays'
   AND column_name IN ('behavior_config', 'sales_process_config')
 ORDER BY column_name;

SELECT count(*) AS total_columns
  FROM information_schema.columns
 WHERE table_name = 'niche_overlays';
