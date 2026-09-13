-- ---------------------------------------------------------------------
-- clients: the two notification preferences the Settings page has always
-- read and written, and that have never existed.
--
-- WHY THIS EXISTS
--
-- client-dashboard/pages/settings.html binds two toggles to
-- daily_digest_opt_in and booking_alerts_opt_in. clx-client-settings
-- selects both on read and PATCHes both on write. Neither column is in
-- the table, so PostgREST answered 400 to both paths: the toggles never
-- loaded a value and never saved one. The page reported "Request failed."
-- and there was nothing behind it to fix, because the failure was the
-- schema, not the code.
--
-- Found 2026-09-12, alongside clients.vertical -- also selected in five
-- workflows, also never a column. Same family: a name the code agreed on
-- with itself and never with the database.
--
-- DEFAULTS
--
-- Both default FALSE. These flags gate outbound email to the customer,
-- and nothing should start sending because a column appeared. The
-- customer turns them on in Settings, which is the whole point of the
-- toggles. If you want existing clients opted in, that is a deliberate
-- product decision and belongs in its own migration with its own reason.
--
-- Idempotent: safe to run more than once.
-- ---------------------------------------------------------------------

ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS daily_digest_opt_in   boolean NOT NULL DEFAULT false;

ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS booking_alerts_opt_in boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.clients.daily_digest_opt_in IS
  'Customer-controlled. Daily pipeline digest email. Set from the client Settings page. Default false: nothing sends until the customer asks.';

COMMENT ON COLUMN public.clients.booking_alerts_opt_in IS
  'Customer-controlled. Email on each new booking. Set from the client Settings page. Default false: nothing sends until the customer asks.';

-- Verification (expects two rows):
--   SELECT column_name, data_type, column_default
--   FROM information_schema.columns
--   WHERE table_name = 'clients'
--     AND column_name IN ('daily_digest_opt_in','booking_alerts_opt_in');
