-- ══════════════════════════════════════════════════════════════════
-- CRYSTALLUX CLIENT ONBOARDING TEMPLATE
-- File: docs/mga/client-onboarding-template.sql
--
-- Copy this file per new client, fill placeholders, run in Supabase.
-- Idempotent: re-running updates the same client row by client_slug.
-- ══════════════════════════════════════════════════════════════════


-- ══ FILL THESE IN BEFORE RUNNING ══
-- Replace every :placeholder with the real value (keep quoting).

-- Client identity
\set client_name           '\'Summit Insurance Advisors\''
\set client_slug           '\'summit-insurance\''
\set vertical              '\'insurance_broker\''

-- Operational
\set calendly_link         '\'https://calendly.com/summit-insurance/discovery\''
\set notification_email    '\'bookings@summitinsurance.ca\''
\set daily_send_cap        100

-- Sender identity (leave sender_email NULL to use platform default info@crystallux.org)
\set sender_display_name   '\'Mary Akintunde (Crystallux)\''
\set sender_email          NULL
\set gmail_credential_name '\'Gmail\''

-- Offer override — leave as '{}'::jsonb to use niche_overlays default pricing
\set offer_override_json   '\'{}\'::jsonb'


-- ══ INSERT ══

INSERT INTO clients (
  client_name,
  client_slug,
  vertical,
  calendly_link,
  notification_email,
  daily_send_cap,
  sender_display_name,
  sender_email,
  gmail_credential_name,
  offer_override,
  active
) VALUES (
  :client_name,
  :client_slug,
  :vertical,
  :calendly_link,
  :notification_email,
  :daily_send_cap,
  :sender_display_name,
  :sender_email,
  :gmail_credential_name,
  :offer_override_json,
  true
)
ON CONFLICT (client_slug) DO UPDATE SET
  client_name           = EXCLUDED.client_name,
  vertical              = EXCLUDED.vertical,
  calendly_link         = EXCLUDED.calendly_link,
  notification_email    = EXCLUDED.notification_email,
  daily_send_cap        = EXCLUDED.daily_send_cap,
  sender_display_name   = EXCLUDED.sender_display_name,
  sender_email          = EXCLUDED.sender_email,
  gmail_credential_name = EXCLUDED.gmail_credential_name,
  offer_override        = EXCLUDED.offer_override,
  active                = EXCLUDED.active
RETURNING id, client_slug, dashboard_token, client_name;


-- ══ POST-INSERT VERIFICATION ══
-- Run these three queries after the INSERT. All should return 1 row.

-- 1. Client row present
SELECT id, client_name, client_slug, vertical, active, dashboard_token
FROM clients
WHERE client_slug = :client_slug;

-- 2. Vertical has a niche_overlays row (otherwise Outreach Generation falls back to generic)
SELECT niche_name, display_name, is_active
FROM niche_overlays
WHERE niche_name = :vertical;

-- 3. Handoff URLs to give the client
SELECT
  'https://dashboard.crystallux.org/?client_id=' || id || '&token=' || dashboard_token AS dashboard_url,
  'https://crystallux.org/intake/' || client_slug AS public_intake_url,
  notification_email AS booking_alerts_go_to
FROM clients
WHERE client_slug = :client_slug;
