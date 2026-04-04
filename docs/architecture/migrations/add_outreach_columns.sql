-- CLX Outreach Generation Migration
-- Phase 6: Add outreach content columns to leads table
-- Run this in Supabase SQL Editor before activating clx-outreach-generation workflow

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS email_subject          TEXT,
  ADD COLUMN IF NOT EXISTS email_body             TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_message       TEXT,
  ADD COLUMN IF NOT EXISTS whatsapp_message       TEXT,
  ADD COLUMN IF NOT EXISTS followup_message       TEXT,
  ADD COLUMN IF NOT EXISTS outreach_angle         TEXT,
  ADD COLUMN IF NOT EXISTS personalization_score  INTEGER,
  ADD COLUMN IF NOT EXISTS outreach_generated_at  TIMESTAMPTZ;

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'email_subject',
    'email_body',
    'linkedin_message',
    'whatsapp_message',
    'followup_message',
    'outreach_angle',
    'personalization_score',
    'outreach_generated_at'
  )
ORDER BY column_name;
