-- Crystallux Phase 9: Booking Columns Migration
-- Run this in Supabase SQL Editor before activating clx-booking workflow

ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS reply_text              TEXT,
  ADD COLUMN IF NOT EXISTS interest_detected       BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS booking_email_sent      BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS booking_email_sent_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS calendly_link           TEXT,
  ADD COLUMN IF NOT EXISTS meeting_scheduled       BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS meeting_datetime        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS meeting_notes           TEXT;

-- Index for Phase 9 query performance
CREATE INDEX IF NOT EXISTS idx_leads_replied ON leads (lead_status) WHERE lead_status = 'Replied';
CREATE INDEX IF NOT EXISTS idx_leads_booking_sent ON leads (lead_status) WHERE lead_status = 'Booking Sent';

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN (
    'reply_text',
    'interest_detected',
    'booking_email_sent',
    'booking_email_sent_at',
    'calendly_link',
    'meeting_scheduled',
    'meeting_datetime',
    'meeting_notes'
  )
ORDER BY column_name;
