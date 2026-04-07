-- EMERGENCY: Run this immediately to stop all spam
-- Blocks all test emails and adds missing safety columns

-- Step 1: Block all test leads from outreach
UPDATE leads
SET do_not_contact = true,
    unsubscribed = true,
    reply_detected = true,
    total_emails_sent = 99,
    lead_status = 'Do Not Contact',
    updated_at = now()
WHERE source = 'test'
   OR email = 'adesholaakintunde@gmail.com'
   OR email LIKE '%acmecorp%'
   OR email LIKE '%brightwave%'
   OR email LIKE '%torontoinsurance%';

-- Step 2: Add missing safety columns if not exist
ALTER TABLE leads
ADD COLUMN IF NOT EXISTS last_email_sent_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS total_emails_sent INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS unsubscribed BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS do_not_contact BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS reply_detected BOOLEAN DEFAULT false;

-- Step 3: Set defaults on any NULL safety fields
UPDATE leads
SET total_emails_sent = 0 WHERE total_emails_sent IS NULL;

UPDATE leads
SET unsubscribed = false WHERE unsubscribed IS NULL;

UPDATE leads
SET do_not_contact = false WHERE do_not_contact IS NULL;

UPDATE leads
SET reply_detected = false WHERE reply_detected IS NULL;

-- Step 4: Verify blocked leads
SELECT company, email, lead_status, do_not_contact, total_emails_sent
FROM leads
WHERE do_not_contact = true
ORDER BY updated_at DESC;
