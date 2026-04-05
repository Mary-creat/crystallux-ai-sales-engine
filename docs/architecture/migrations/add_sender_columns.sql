-- CLX Outreach Sender Migration
-- Phase 7: Add outreach sending columns to leads table
-- Run this in Supabase SQL Editor before activating clx-outreach-sender workflow

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS outreach_sent_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS followup_scheduled_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS outreach_channel        TEXT;

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'outreach_sent_at',
    'followup_scheduled_at',
    'outreach_channel'
  )
ORDER BY column_name;
