-- CLX Lead Scoring Migration
-- Phase 3: Add scoring columns to leads table
-- Run this in Supabase SQL Editor before activating clx-lead-scoring workflow

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS lead_score         INTEGER,
  ADD COLUMN IF NOT EXISTS priority_level     TEXT,
  ADD COLUMN IF NOT EXISTS decision_maker_probability TEXT,
  ADD COLUMN IF NOT EXISTS company_size_estimate      TEXT,
  ADD COLUMN IF NOT EXISTS scoring_reason     TEXT;

-- Optional: add check constraint to keep lead_score in valid range
ALTER TABLE leads
  ADD CONSTRAINT IF NOT EXISTS leads_lead_score_range
  CHECK (lead_score IS NULL OR (lead_score >= 0 AND lead_score <= 100));

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'lead_score',
    'priority_level',
    'decision_maker_probability',
    'company_size_estimate',
    'scoring_reason'
  )
ORDER BY column_name;
