-- CLX Follow Up Migration
-- Phase 8: Add follow-up sequence columns to leads table
-- Run this in Supabase SQL Editor before activating clx-follow-up workflow

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS followup_count               INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS followup_sent_at             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS next_followup_scheduled_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reply_detected               BOOLEAN DEFAULT false;

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'followup_count',
    'followup_sent_at',
    'next_followup_scheduled_at',
    'reply_detected'
  )
ORDER BY column_name;
