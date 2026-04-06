-- Crystallux Phase 10: Pipeline Stats Migration
-- Run this in Supabase SQL Editor before activating clx-pipeline-update workflow

-- Add stale tracking columns to leads table
ALTER TABLE leads
  ADD COLUMN IF NOT EXISTS is_stale            BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS stale_reason        TEXT,
  ADD COLUMN IF NOT EXISTS stale_detected_at   TIMESTAMPTZ;

-- Index for stale lead queries
CREATE INDEX IF NOT EXISTS idx_leads_stale ON leads (is_stale) WHERE is_stale = true;

-- Create pipeline_stats table for daily snapshots
CREATE TABLE IF NOT EXISTS pipeline_stats (
  id                        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  snapshot_date             DATE DEFAULT CURRENT_DATE,
  total_leads               INTEGER,
  new_lead_count            INTEGER,
  researched_count          INTEGER,
  scored_count              INTEGER,
  signal_detected_count     INTEGER,
  campaign_assigned_count   INTEGER,
  outreach_ready_count      INTEGER,
  contacted_count           INTEGER,
  replied_count             INTEGER,
  booking_sent_count        INTEGER,
  booked_count              INTEGER,
  closed_lost_count         INTEGER,
  not_interested_count      INTEGER,
  import_to_research_rate   DECIMAL,
  research_to_score_rate    DECIMAL,
  score_to_outreach_rate    DECIMAL,
  outreach_to_reply_rate    DECIMAL,
  reply_to_booking_rate     DECIMAL,
  conversion_rate_overall   DECIMAL,
  created_at                TIMESTAMPTZ DEFAULT now()
);

-- Index for querying stats by date
CREATE INDEX IF NOT EXISTS idx_pipeline_stats_date ON pipeline_stats (snapshot_date DESC);

-- Verify leads columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN ('is_stale', 'stale_reason', 'stale_detected_at')
ORDER BY column_name;

-- Verify pipeline_stats table exists
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'pipeline_stats'
ORDER BY ordinal_position;
