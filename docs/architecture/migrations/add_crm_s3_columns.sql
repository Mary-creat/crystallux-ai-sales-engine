-- Crystallux Clients Table — CRM and S3 Integration Columns
-- Adds CRM sync and S3 storage configuration to the existing clients table.
-- Safe to run on production: every column is added with IF NOT EXISTS.
--
-- Run order: after add_clients_table.sql
-- Date: 2026-04-10

-- ─────────────────────────────────────────────
-- CRM integration columns
-- ─────────────────────────────────────────────
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS crm_type        TEXT,
  ADD COLUMN IF NOT EXISTS crm_api_key     TEXT,
  ADD COLUMN IF NOT EXISTS crm_account_id  TEXT,
  ADD COLUMN IF NOT EXISTS crm_pipeline_id TEXT,
  ADD COLUMN IF NOT EXISTS crm_sync_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS crm_last_sync   TIMESTAMPTZ;

-- Enforce allowed CRM types
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'clients_crm_type_check'
      AND table_name = 'clients'
  ) THEN
    ALTER TABLE clients
      ADD CONSTRAINT clients_crm_type_check
      CHECK (crm_type IS NULL OR crm_type IN (
        'hubspot',
        'pipedrive',
        'salesforce',
        'smart_moving',
        'zoho',
        'none'
      ));
  END IF;
END $$;

-- ─────────────────────────────────────────────
-- S3 / object storage integration columns
-- ─────────────────────────────────────────────
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS s3_bucket       TEXT,
  ADD COLUMN IF NOT EXISTS s3_folder       TEXT,
  ADD COLUMN IF NOT EXISTS s3_sync_enabled BOOLEAN DEFAULT false;

-- ─────────────────────────────────────────────
-- Helpful indexes for sync workers
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_clients_crm_sync_enabled
  ON clients (crm_sync_enabled)
  WHERE crm_sync_enabled = true;

CREATE INDEX IF NOT EXISTS idx_clients_s3_sync_enabled
  ON clients (s3_sync_enabled)
  WHERE s3_sync_enabled = true;
