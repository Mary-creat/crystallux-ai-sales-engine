-- ══════════════════════════════════════════════════════════════════
-- Lead status backfill — fixes the "unknown 200" Sales Engine display
-- ══════════════════════════════════════════════════════════════════
-- Legacy leads created before lead_status was consistently set have
-- NULL / '' / 'unknown' values, which render as "unknown 200" in the
-- Sales Engine pipeline-by-stage panel.
--
-- Backfill rule: anything without a real status becomes 'New Lead'
-- (the canonical default used by city-scan, public-mga-apply, and
-- mga-insurance-lead-capture going forward).
--
-- Also normalises the inconsistency where mga-insurance-lead-capture
-- briefly set 'New' instead of 'New Lead' — update those rows too.
--
-- Idempotent. Safe to re-apply. Reports row counts.
-- ══════════════════════════════════════════════════════════════════

-- 1. Promote NULL / '' / 'unknown' → 'New Lead'
UPDATE leads
   SET lead_status = 'New Lead',
       updated_at  = COALESCE(updated_at, now())
 WHERE lead_status IS NULL
    OR lead_status = ''
    OR lower(lead_status) = 'unknown';

-- 2. Normalise 'New' → 'New Lead' (legacy mga-insurance-lead-capture value)
UPDATE leads
   SET lead_status = 'New Lead',
       updated_at  = COALESCE(updated_at, now())
 WHERE lead_status = 'New';

-- 3. Diagnostic: count by status post-backfill
SELECT lead_status, count(*) AS n
  FROM leads
 GROUP BY lead_status
 ORDER BY n DESC;
