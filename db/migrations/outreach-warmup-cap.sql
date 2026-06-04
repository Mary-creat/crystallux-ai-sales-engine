-- Outreach warmup cap.
-- The Outreach Sender reads its daily limit from get_daily_send_count(), which
-- had a HARD-CODED limit of 450/day. A fresh Gmail blasting 450 cold emails on
-- day one gets banned. This lowers the global daily cap to a safe warmup number.
--
-- RAMP PLAN (raise v_cap as the account warms, ~over 2-3 weeks):
--   week 1: 25  ->  week 2: 75  ->  week 3: 150  ->  steady: 300-450
-- To raise it later, just re-run this with a bigger number in v_cap.

CREATE OR REPLACE FUNCTION get_daily_send_count()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
  v_cap   integer := 25;   -- <<< warmup cap. Raise as the Gmail warms up.
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM leads
  WHERE last_email_sent_at >= CURRENT_DATE
    AND last_email_sent_at <  CURRENT_DATE + interval '1 day';

  RETURN jsonb_build_object(
    'count',     v_count,
    'limit',     v_cap,
    'remaining', GREATEST(v_cap - v_count, 0)
  );
END;
$$;

-- Fix the broken booking link on the outreach tenant so interested leads book a
-- real calendar (was https://crystallux.org/Crystallux-info, not a Calendly URL).
UPDATE clients
   SET calendly_link = 'https://calendly.com/crystallux-info/30min'
 WHERE id = 'd7d4569f-a870-42dd-ba15-efb793227f03';

-- Verify:
-- SELECT get_daily_send_count();
-- SELECT id, client_name, calendly_link FROM clients WHERE id = 'd7d4569f-a870-42dd-ba15-efb793227f03';
