-- v_outbound_arming ran with the creator's rights. It should not.
--
-- Supabase's advisor flagged this as CRITICAL, correctly, and it is mine:
-- the view was created in outbound-arming-switch.sql on 2026-09-05 without
-- security_invoker, so Postgres ran it with the OWNER's permissions. Any
-- role able to select from it would read sentinel_workflow_breakers
-- regardless of its own grants or row-level policies.
--
-- It exposes only arming state, so the blast radius here is small. The
-- habit is not: a view that quietly escalates privilege is the kind of
-- thing that is harmless until the day it is attached to something that
-- matters. The arming switch is a safety control, and a safety control
-- that bends the permission model is the wrong shape by definition.
--
-- security_invoker = on makes the view run as the CALLER, so it obeys
-- whatever that caller is actually allowed to see.
--
-- The two other SECURITY DEFINER views the advisor lists --
-- commerce_tenant_directory and delivery_board -- predate this work and
-- are deliberately left alone. They belong to the commerce layer, they may
-- be intentional, and changing someone else's privilege boundary while
-- fixing my own is how a small correction becomes an outage.

BEGIN;

ALTER VIEW public.v_outbound_arming SET (security_invoker = on);

COMMIT;

-- Verify -- expect security_invoker=true in the options column:
--   SELECT c.relname, c.reloptions
--     FROM pg_class c
--     JOIN pg_namespace n ON n.oid = c.relnamespace
--    WHERE n.nspname = 'public' AND c.relname = 'v_outbound_arming';
--
-- Then confirm the switch still reads correctly:
--   SELECT * FROM v_outbound_arming;
--   -- four rows, armed = false
