-- Crystallux Performance Indexes Migration
-- Run this in Supabase SQL Editor to optimize query performance

-- General status index — used by every workflow
CREATE INDEX IF NOT EXISTS idx_leads_lead_status ON leads(lead_status);

-- Product type filtering — used by campaign router and reporting
CREATE INDEX IF NOT EXISTS idx_leads_product_type ON leads(product_type);

-- Time-based queries — used by pipeline update and stale detection
CREATE INDEX IF NOT EXISTS idx_leads_updated_at ON leads(updated_at DESC);

-- Source filtering — used by analytics and dedup
CREATE INDEX IF NOT EXISTS idx_leads_source ON leads(source);

-- Follow-up scheduling — used by Phase 8
CREATE INDEX IF NOT EXISTS idx_leads_followup_scheduled
ON leads(followup_scheduled_at)
WHERE lead_status = 'Contacted';

-- Outreach prioritization — used by Phase 7
CREATE INDEX IF NOT EXISTS idx_leads_outreach_ready
ON leads(lead_status, lead_score DESC)
WHERE lead_status = 'Outreach Ready';

-- Composite for common pipeline queries
CREATE INDEX IF NOT EXISTS idx_leads_status_updated
ON leads(lead_status, updated_at DESC);

-- Verify indexes created
SELECT indexname, tablename
FROM pg_indexes
WHERE tablename = 'leads'
ORDER BY indexname;
