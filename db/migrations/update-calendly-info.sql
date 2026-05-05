-- Update Calendly link + notification email for Crystallux Insurance Network
--
-- Brand consolidation: move from a personal Gmail/Calendly link to the
-- shared Crystallux team identity. Crystallux is a multi-vertical
-- platform (insurance is one of many service-industry verticals), so
-- the booking link should reflect the platform brand rather than a
-- single tenant's industry.
--
-- Old:
--   notification_email = 'adesholaakintunde@gmail.com'
--   calendly_link      = (whatever was previously stored)
-- New:
--   notification_email = 'info@crystallux.org'
--   calendly_link      = 'https://calendly.com/crystallux-info/30min'
--
-- Idempotent: safe to run twice. Second run is a no-op because the
-- target row already matches.

UPDATE clients
SET
  calendly_link      = 'https://calendly.com/crystallux-info/30min',
  notification_email = 'info@crystallux.org',
  updated_at         = NOW()
WHERE id = '6edc687d-07b0-4478-bb4b-820dc4eebf5d'
  AND (
    calendly_link      IS DISTINCT FROM 'https://calendly.com/crystallux-info/30min'
    OR notification_email IS DISTINCT FROM 'info@crystallux.org'
  );

-- Verify
SELECT
  id,
  client_name,
  calendly_link,
  notification_email,
  updated_at
FROM clients
WHERE id = '6edc687d-07b0-4478-bb4b-820dc4eebf5d';
