-- Reset test leads to prevent accidental outreach
-- Run this in Supabase SQL Editor

UPDATE leads
SET do_not_contact = true,
    unsubscribed = true,
    reply_detected = true,
    total_emails_sent = 99,
    updated_at = now()
WHERE email = 'adesholaakintunde@gmail.com'
   OR source = 'test';

-- Verify
SELECT company, email, do_not_contact, unsubscribed, total_emails_sent
FROM leads
WHERE email = 'adesholaakintunde@gmail.com'
   OR source = 'test';
