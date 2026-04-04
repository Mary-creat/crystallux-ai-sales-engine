-- CLX Campaign Router Migration
-- Phase 5: Add campaign assignment columns to leads table
-- Run this in Supabase SQL Editor before activating clx-campaign-router workflow

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS campaign_name              TEXT,
  ADD COLUMN IF NOT EXISTS campaign_type              TEXT,
  ADD COLUMN IF NOT EXISTS campaign_value_proposition TEXT,
  ADD COLUMN IF NOT EXISTS campaign_pain_point        TEXT,
  ADD COLUMN IF NOT EXISTS campaign_call_to_action    TEXT,
  ADD COLUMN IF NOT EXISTS campaign_tone              TEXT;

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'campaign_name',
    'campaign_type',
    'campaign_value_proposition',
    'campaign_pain_point',
    'campaign_call_to_action',
    'campaign_tone'
  )
ORDER BY column_name;
