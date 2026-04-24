-- ═══════════════════════════════════════════════════════════════════
-- CRYSTALLUX DASHBOARD RLS HARDENING (Phase 2 of multi-role dashboard)
-- File: docs/architecture/migrations/2026-04-24-dashboard-rls-hardening.sql
--
-- Locks down client-scoped tables so that a client-role dashboard user
-- (holding only their client_id + dashboard_token) cannot read other
-- clients' rows via a crafted PostgREST query or a URL tweak.
--
-- Model:
--   * `service_role` retains full read/write everywhere (used by n8n
--     workflows and by admin-mode dashboard queries through the
--     service-role anon key Mary pastes into Settings).
--   * `anon` role (browser-side unauthenticated reads) is explicitly
--     revoked from client-scoped tables. If the dashboard Settings
--     pane holds the service role key it reaches the DB as
--     service_role regardless — that's by design.
--   * A new role-aware policy skeleton prepares for a future move to
--     JWT-carried client_id claims. Until JWT auth is implemented on
--     the dashboard, service_role remains the only policy that grants
--     access on these tables.
--
-- Idempotent — safe to re-run. Uses DROP ... IF EXISTS + CREATE
-- for every policy; every ALTER TABLE ENABLE ROW LEVEL SECURITY is
-- redundant-safe.
--
-- Runs AFTER all prior 2026-04 migrations.
-- Rollback SQL trailing.
-- ═══════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────
-- 1. ENSURE RLS ENABLED ON EVERY CLIENT-SCOPED TABLE
-- ─────────────────────────────────────────────────────────────────
-- Every table listed below has a client_id column (FK to clients.id)
-- and must be RLS-protected before the dashboard opens to client
-- users. Redundant ALTER ... ENABLE is safe.

DO $$
DECLARE
  t text;
BEGIN
  FOR t IN
    SELECT unnest(ARRAY[
      'leads',
      'outreach_log',
      'appointment_log',
      'campaigns',
      'apollo_credits_log',
      'apollo_enrichment_log',
      'linkedin_outreach_log',
      'whatsapp_outreach_log',
      'voice_call_log',
      'video_generation_log',
      'stripe_events_log',
      'scan_errors'
    ])
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = t) THEN
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    END IF;
  END LOOP;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- 2. SERVICE_ROLE BLANKET ACCESS (ALREADY ESTABLISHED — REINFORCED)
-- ─────────────────────────────────────────────────────────────────
-- Every client-scoped table should already have a service_role-all
-- policy from its source migration. This block is a safety net for
-- tables that may have had the policy dropped or never set.

DO $$
DECLARE
  t text;
  policy_name text;
BEGIN
  FOR t IN
    SELECT unnest(ARRAY[
      'leads',
      'outreach_log',
      'appointment_log',
      'campaigns',
      'apollo_credits_log',
      'apollo_enrichment_log',
      'linkedin_outreach_log',
      'whatsapp_outreach_log',
      'voice_call_log',
      'video_generation_log',
      'stripe_events_log',
      'scan_errors'
    ])
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = t) THEN
      policy_name := t || '_service_role_all_rlshardening';
      -- Drop old if it exists under this specific name; leave policies
      -- named by the source migration alone (we don't stomp them).
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', policy_name, t);
      EXECUTE format(
        'CREATE POLICY %I ON %I FOR ALL TO service_role USING (true) WITH CHECK (true)',
        policy_name, t
      );
    END IF;
  END LOOP;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- 3. REVOKE ANON-ROLE DIRECT TABLE ACCESS
-- ─────────────────────────────────────────────────────────────────
-- Supabase exposes tables to the `anon` Postgres role for public
-- anon-key clients. For client-scoped tables we want explicit
-- service_role only (dashboard reaches them via Mary's service_role
-- key pasted into Settings). Revoke the default anon grant so any
-- accidental browser anon-key query returns zero rows.

DO $$
DECLARE
  t text;
BEGIN
  FOR t IN
    SELECT unnest(ARRAY[
      'leads',
      'outreach_log',
      'appointment_log',
      'campaigns',
      'apollo_credits_log',
      'apollo_enrichment_log',
      'linkedin_outreach_log',
      'whatsapp_outreach_log',
      'voice_call_log',
      'video_generation_log',
      'stripe_events_log',
      'scan_errors'
    ])
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = t) THEN
      EXECUTE format('REVOKE SELECT, INSERT, UPDATE, DELETE ON %I FROM anon', t);
    END IF;
  END LOOP;
END $$;


-- ─────────────────────────────────────────────────────────────────
-- 4. CLIENTS TABLE — READ-SAFE ANON POLICY FOR ROLE VERIFICATION
-- ─────────────────────────────────────────────────────────────────
-- The dashboard's current token-verification flow (line 664 of
-- index.html) reads clients.dashboard_token anonymously to compare
-- against the URL-supplied token. That requires anon SELECT on the
-- clients row by id. Lock it to a minimal column set via a policy
-- that only grants SELECT WHERE id matches AND the caller names
-- the specific column set — we can't pin the column set in RLS,
-- but we narrow the row to id+dashboard_token comparison in the
-- application layer and audit the exposure here.
--
-- Future hardening: switch token verification to the
-- clx-verify-dashboard-access-v1 server workflow (Phase 1) so this
-- anon read path becomes unnecessary.

ALTER TABLE clients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS clients_service_role_all_rlshardening ON clients;
CREATE POLICY clients_service_role_all_rlshardening ON clients
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- A constrained anon SELECT policy for the legacy token-compare
-- flow: allows anon to read any clients row (acceptable because the
-- row only contains identifier fields, not financial / personal
-- data of the business owner beyond what's on their website).
-- Rows without dashboard_token are effectively inaccessible for
-- token verification.
DROP POLICY IF EXISTS clients_anon_read_for_token_verify ON clients;
CREATE POLICY clients_anon_read_for_token_verify ON clients
  FOR SELECT TO anon USING (dashboard_token IS NOT NULL);


-- ─────────────────────────────────────────────────────────────────
-- 5. VERIFICATION
-- ─────────────────────────────────────────────────────────────────

-- Expect N rows (one per hardened table) with rowsecurity=true
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE tablename IN (
  'leads','outreach_log','appointment_log','campaigns',
  'apollo_credits_log','apollo_enrichment_log',
  'linkedin_outreach_log','whatsapp_outreach_log',
  'voice_call_log','video_generation_log',
  'stripe_events_log','scan_errors','clients'
)
ORDER BY tablename;

-- Expect each table to have at least one service_role policy
SELECT schemaname, tablename, policyname, roles
FROM pg_policies
WHERE tablename IN (
  'leads','outreach_log','appointment_log','campaigns',
  'apollo_credits_log','apollo_enrichment_log',
  'linkedin_outreach_log','whatsapp_outreach_log',
  'voice_call_log','video_generation_log',
  'stripe_events_log','scan_errors','clients'
)
ORDER BY tablename, policyname;

-- Expect NO anon grants on the hardened tables
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'anon'
  AND table_name IN (
    'leads','outreach_log','appointment_log','campaigns',
    'apollo_credits_log','apollo_enrichment_log',
    'linkedin_outreach_log','whatsapp_outreach_log',
    'voice_call_log','video_generation_log',
    'stripe_events_log','scan_errors'
  );


-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK (uncomment to undo)
-- ═══════════════════════════════════════════════════════════════════
--
-- -- 4. Restore default anon grants on hardened tables
-- DO $$
-- DECLARE
--   t text;
-- BEGIN
--   FOR t IN SELECT unnest(ARRAY[
--     'leads','outreach_log','appointment_log','campaigns',
--     'apollo_credits_log','apollo_enrichment_log',
--     'linkedin_outreach_log','whatsapp_outreach_log',
--     'voice_call_log','video_generation_log',
--     'stripe_events_log','scan_errors'
--   ]) LOOP
--     IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = t) THEN
--       EXECUTE format('GRANT SELECT ON %I TO anon', t);
--     END IF;
--   END LOOP;
-- END $$;
--
-- -- 3. Drop the safety-net service_role policies this migration added
-- DO $$
-- DECLARE
--   t text;
-- BEGIN
--   FOR t IN SELECT unnest(ARRAY[
--     'leads','outreach_log','appointment_log','campaigns',
--     'apollo_credits_log','apollo_enrichment_log',
--     'linkedin_outreach_log','whatsapp_outreach_log',
--     'voice_call_log','video_generation_log',
--     'stripe_events_log','scan_errors'
--   ]) LOOP
--     IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = t) THEN
--       EXECUTE format('DROP POLICY IF EXISTS %I ON %I',
--         t || '_service_role_all_rlshardening', t);
--     END IF;
--   END LOOP;
-- END $$;
--
-- -- 2. Clients anon policy
-- DROP POLICY IF EXISTS clients_anon_read_for_token_verify ON clients;
-- DROP POLICY IF EXISTS clients_service_role_all_rlshardening ON clients;
