-- CLX Business Signal Detection Migration
-- Phase 4: Add signal detection columns to leads table
-- Run this in Supabase SQL Editor before activating clx-business-signal-detection workflow

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS detected_signal          TEXT,
  ADD COLUMN IF NOT EXISTS growth_stage             TEXT,
  ADD COLUMN IF NOT EXISTS recommended_campaign_type TEXT,
  ADD COLUMN IF NOT EXISTS signal_confidence        TEXT,
  ADD COLUMN IF NOT EXISTS outreach_timing          TEXT;

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'detected_signal',
    'growth_stage',
    'recommended_campaign_type',
    'signal_confidence',
    'outreach_timing'
  )
ORDER BY column_name;
