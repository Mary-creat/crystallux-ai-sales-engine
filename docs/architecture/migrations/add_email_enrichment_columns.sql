-- CLX Email Enrichment — Add enrichment tracking columns to leads table
-- Run this migration in Supabase SQL Editor before activating the workflow

ALTER TABLE leads ADD COLUMN IF NOT EXISTS email_enriched BOOLEAN DEFAULT false;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS email_enriched_at TIMESTAMPTZ;

-- Index for the enrichment query: google_maps leads without email
CREATE INDEX IF NOT EXISTS idx_leads_email_enrichment
  ON leads (source, email, do_not_contact)
  WHERE source = 'google_maps' AND (email IS NULL OR email = '') AND do_not_contact = false;
