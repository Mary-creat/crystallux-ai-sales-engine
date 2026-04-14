ALTER TABLE leads ADD COLUMN IF NOT EXISTS lead_type text DEFAULT 'b2c';
ALTER TABLE clients ADD COLUMN IF NOT EXISTS lead_type text DEFAULT 'b2c';
CREATE INDEX IF NOT EXISTS idx_leads_lead_type ON leads(lead_type);
