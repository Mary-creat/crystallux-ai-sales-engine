-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX SCALE SPRINT v1 — SCHEMA CHANGES
-- File: docs/architecture/migrations/2026-04-22-scale-sprint-v1.sql
--
-- Single idempotent migration covering Part B of the 5-day scale sprint.
-- Preps the platform for 10+ concurrent clients on shared infrastructure.
--
-- Idempotent — safe to re-run. All column adds use IF NOT EXISTS.
-- All tables use CREATE TABLE IF NOT EXISTS.
-- RLS policies use DROP ... IF EXISTS / CREATE.
--
-- Rollback SQL at the bottom of this file (commented).
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. PER-CLIENT GMAIL CREDENTIALS
-- ─────────────────────────────────────────────────────────────────
-- Lets each client resolve a distinct n8n credential name at send time.
-- Default 'Gmail' preserves current single-credential behavior.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS gmail_credential_name text DEFAULT 'Gmail';


-- ─────────────────────────────────────────────────────────────────
-- 2. PER-CLIENT RATE LIMIT RPC
-- ─────────────────────────────────────────────────────────────────
-- Replaces the zero-arg get_daily_send_count() with a client-scoped
-- variant. Global-cap variant is preserved as a separate RPC for
-- workflow-level pre-fetch gating.

CREATE OR REPLACE FUNCTION get_daily_send_count_per_client(p_client_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
  v_cap   integer;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM leads
  WHERE client_id = p_client_id
    AND last_email_sent_at >= CURRENT_DATE
    AND last_email_sent_at <  CURRENT_DATE + interval '1 day';

  SELECT COALESCE(daily_send_cap, 450) INTO v_cap
  FROM clients
  WHERE id = p_client_id;

  IF v_cap IS NULL THEN v_cap := 450; END IF;

  RETURN jsonb_build_object(
    'client_id', p_client_id,
    'count',     v_count,
    'limit',     v_cap,
    'remaining', GREATEST(v_cap - v_count, 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_send_count_per_client(uuid) TO service_role;

-- Per-client cap column (falls back to 450 global default when null).
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS daily_send_cap integer DEFAULT 450;


-- ─────────────────────────────────────────────────────────────────
-- 3. PER-CLIENT UNSUBSCRIBES
-- ─────────────────────────────────────────────────────────────────
-- Prevents one client's unsubscribe from blocking another client's
-- legitimate future outreach. Keyed on (lead_id, client_id).

CREATE TABLE IF NOT EXISTS unsubscribes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id           uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  client_id         uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  unsubscribed_at   timestamptz NOT NULL DEFAULT now(),
  reason            text,
  source            text DEFAULT 'link_click',
  created_at        timestamptz DEFAULT now(),
  UNIQUE (lead_id, client_id)
);

CREATE INDEX IF NOT EXISTS idx_unsubscribes_lead ON unsubscribes(lead_id);
CREATE INDEX IF NOT EXISTS idx_unsubscribes_client ON unsubscribes(client_id);

ALTER TABLE unsubscribes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS unsubscribes_service_role_all ON unsubscribes;
CREATE POLICY unsubscribes_service_role_all ON unsubscribes
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Backfill from existing leads.unsubscribed=true into the per-client table.
-- Only runs if the target row doesn't already exist (idempotent).
INSERT INTO unsubscribes (lead_id, client_id, unsubscribed_at, reason, source)
SELECT l.id,
       l.client_id,
       COALESCE(l.updated_at, now()),
       'migrated from leads.unsubscribed flag',
       'migration'
FROM leads l
WHERE l.unsubscribed = true
  AND l.client_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM unsubscribes u
    WHERE u.lead_id = l.id AND u.client_id = l.client_id
  );

-- Convenience RPC — cheap single-lead lookup.
CREATE OR REPLACE FUNCTION is_unsubscribed(p_lead_id uuid, p_client_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM unsubscribes
    WHERE lead_id = p_lead_id AND client_id = p_client_id
  );
$$;

GRANT EXECUTE ON FUNCTION is_unsubscribed(uuid, uuid) TO service_role;


-- ─────────────────────────────────────────────────────────────────
-- 4. PER-CLIENT SENDER IDENTITY
-- ─────────────────────────────────────────────────────────────────
-- Lets Build Gmail Raw Message nodes look up client-specific From
-- header and signature. Null = use platform default (Mary Akintunde).

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS sender_display_name text,
  ADD COLUMN IF NOT EXISTS sender_email        text,
  ADD COLUMN IF NOT EXISTS email_signature     text;


-- ─────────────────────────────────────────────────────────────────
-- 5. PER-CLIENT OFFER OVERRIDE
-- ─────────────────────────────────────────────────────────────────
-- Custom pricing/offer terms per client. Falls back to niche_overlays
-- when null. Structure mirrors niche_overlays.offer_mapping.

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS offer_override jsonb;


-- ─────────────────────────────────────────────────────────────────
-- 6. CLIENT-FACING DASHBOARD TOKEN + PUBLIC SLUG
-- ─────────────────────────────────────────────────────────────────
-- dashboard_token: client-facing read-only access via shareable URL.
-- client_slug: used for public intake form URL (crystallux.org/intake/{slug}).

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS dashboard_token uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS client_slug     text;

CREATE UNIQUE INDEX IF NOT EXISTS idx_clients_slug
  ON clients(client_slug) WHERE client_slug IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_clients_dashboard_token
  ON clients(dashboard_token) WHERE dashboard_token IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────
-- 7. MONITORING ALERT THRESHOLDS
-- ─────────────────────────────────────────────────────────────────
-- Configurable per-error-code thresholds for Error Monitor v1.

CREATE TABLE IF NOT EXISTS monitoring_thresholds (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  error_code      text UNIQUE NOT NULL,
  window_minutes  integer NOT NULL DEFAULT 10,
  count_threshold integer NOT NULL DEFAULT 5,
  severity        text DEFAULT 'warning',
  is_active       boolean DEFAULT true,
  created_at      timestamptz DEFAULT now()
);

ALTER TABLE monitoring_thresholds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS monitoring_thresholds_service_role_all ON monitoring_thresholds;
CREATE POLICY monitoring_thresholds_service_role_all ON monitoring_thresholds
  FOR ALL TO service_role USING (true) WITH CHECK (true);

INSERT INTO monitoring_thresholds (error_code, window_minutes, count_threshold, severity)
VALUES
  ('GMAIL_SEND_FAILED',           10, 3,  'critical'),
  ('UPDATE_FAILED_AFTER_SEND',    10, 3,  'critical'),
  ('signal_parse_fallback',       60, 10, 'warning'),
  ('SKIPPED',                     60, 50, 'info'),
  ('APOLLO_ENRICHMENT_FAILED',    10, 5,  'warning')
ON CONFLICT (error_code) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────
-- 8. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect 1 row each
SELECT 'clients.gmail_credential_name' AS check_name,
       COUNT(*) AS present
FROM information_schema.columns
WHERE table_name = 'clients' AND column_name = 'gmail_credential_name';

SELECT 'unsubscribes table' AS check_name,
       COUNT(*) AS present
FROM information_schema.tables
WHERE table_name = 'unsubscribes';

SELECT 'get_daily_send_count_per_client' AS check_name,
       COUNT(*) AS present
FROM information_schema.routines
WHERE routine_name = 'get_daily_send_count_per_client';

SELECT 'monitoring_thresholds seed' AS check_name,
       COUNT(*) AS rows_seeded
FROM monitoring_thresholds;


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment sections to undo — test on staging first)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 7. Monitoring thresholds
-- DROP TABLE IF EXISTS monitoring_thresholds CASCADE;
--
-- -- 6. Dashboard token + slug
-- DROP INDEX IF EXISTS idx_clients_dashboard_token;
-- DROP INDEX IF EXISTS idx_clients_slug;
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS dashboard_token,
--   DROP COLUMN IF EXISTS client_slug;
--
-- -- 5. Offer override
-- ALTER TABLE clients DROP COLUMN IF EXISTS offer_override;
--
-- -- 4. Sender identity
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS sender_display_name,
--   DROP COLUMN IF EXISTS sender_email,
--   DROP COLUMN IF EXISTS email_signature;
--
-- -- 3. Unsubscribes
-- DROP FUNCTION IF EXISTS is_unsubscribed(uuid, uuid);
-- DROP TABLE IF EXISTS unsubscribes CASCADE;
--
-- -- 2. Rate limits
-- DROP FUNCTION IF EXISTS get_daily_send_count_per_client(uuid);
-- ALTER TABLE clients DROP COLUMN IF EXISTS daily_send_cap;
--
-- -- 1. Gmail credential
-- ALTER TABLE clients DROP COLUMN IF EXISTS gmail_credential_name;
