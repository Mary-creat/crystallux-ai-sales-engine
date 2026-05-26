-- Add date_of_birth + birthday_video_sent_year columns to leads.
-- Idempotent. Safe to re-run.
--
-- date_of_birth        — collected on application forms when relevant
--                        (insurance applications already ask for DOB).
-- birthday_video_sent_year — tracks the last year we sent a birthday
--                        video to this lead, so the daily cron doesn't
--                        re-send if it runs twice on the same day or
--                        catches up after a missed day.

BEGIN;

ALTER TABLE leads ADD COLUMN IF NOT EXISTS date_of_birth date;
ALTER TABLE leads ADD COLUMN IF NOT EXISTS birthday_video_sent_year integer;

-- Index for the daily cron's lookup: "leads with a birthday today"
-- WHERE date_part('month', date_of_birth) = today_month
--   AND date_part('day',   date_of_birth) = today_day
--   AND (birthday_video_sent_year IS NULL OR birthday_video_sent_year < current_year)
--
-- A functional index on (month, day) makes that fast even at 100K+ rows.
CREATE INDEX IF NOT EXISTS leads_dob_month_day_idx
  ON leads (
    date_part('month', date_of_birth),
    date_part('day',   date_of_birth)
  )
  WHERE date_of_birth IS NOT NULL;

COMMIT;

-- Verify
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'leads'
  AND column_name IN ('date_of_birth', 'birthday_video_sent_year');
