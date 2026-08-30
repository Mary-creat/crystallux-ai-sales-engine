-- ============================================================
-- Vertical context, step 2 of 5 — MAXI -> niche_overlays edge
--
-- Adds the nullable foreign key that connects MAXI's 22-industry
-- marketing catalogue to the operable verticals. No data is written
-- here; step 3 does the mapping.
--
-- Nullable on purpose: MAXI markets more industries than the Sales
-- Engine can run, and a NULL states that plainly instead of implying
-- coverage that does not exist.
--
-- Idempotent. Uses a named dollar-quote tag ($do$) rather than $$ so
-- that tools which split naively on $$ cannot mis-parse it.
-- ============================================================

ALTER TABLE maxi_industries
  ADD COLUMN IF NOT EXISTS niche_overlay_id uuid;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'maxi_industries_niche_overlay_fk'
  ) THEN
    ALTER TABLE maxi_industries
      ADD CONSTRAINT maxi_industries_niche_overlay_fk
      FOREIGN KEY (niche_overlay_id) REFERENCES niche_overlays(id)
      ON DELETE SET NULL;
  END IF;
END
$do$;

CREATE INDEX IF NOT EXISTS maxi_industries_niche_overlay_idx
  ON maxi_industries (niche_overlay_id)
  WHERE niche_overlay_id IS NOT NULL;

COMMENT ON COLUMN maxi_industries.niche_overlay_id IS 'The operable vertical behind this marketing industry. NULL means marketed but not yet configured in the Sales Engine.';

-- ---- VERIFY: expect the column, the constraint, and the index ----
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'maxi_industries' AND column_name = 'niche_overlay_id';

SELECT conname FROM pg_constraint
 WHERE conname = 'maxi_industries_niche_overlay_fk';

SELECT indexname FROM pg_indexes
 WHERE indexname = 'maxi_industries_niche_overlay_idx';
