-- ---------------------------------------------------------------------
-- client_lead_stats(p_client_id uuid) -> jsonb
--
-- WHY THIS EXISTS
--
-- The client overview counted leads by fetching every row and calling
-- .length on the result. PostgREST caps a response at max-rows (1000 on
-- this project) no matter what `limit` says, and the workflow asked for
-- limit=5000. So the cap was invisible: no error, no warning, just a
-- number that stops climbing.
--
-- Eazer has 1094 leads. The dashboard showed them 1000, and would have
-- gone on showing 1000 at ten thousand leads. Every time-windowed figure
-- underneath it -- new this week, contacted, replied, booked -- was
-- computed from the same truncated page, so those were wrong too, and
-- wrong in a way that always flatters early and lies later.
--
-- Counting is the database's job. This does it in one round trip, over
-- every row, with no cap to forget about.
--
-- SECURITY DEFINER with the client_id passed in: the caller
-- (clx-client-overview) has already resolved that id from the session
-- row, never from the request body, which is the tenant isolation
-- anchor. This function must therefore never be given a client_id from
-- anywhere else.
--
-- Idempotent.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.client_lead_stats(p_client_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'total_leads',   count(*),
    'new_7d',        count(*) FILTER (WHERE date_created     >= now() - interval '7 days'),
    'contacted_30d', count(*) FILTER (WHERE outreach_sent_at >= now() - interval '30 days'),
    'replies_30d',   count(*) FILTER (WHERE lead_status = 'Replied'
                                        AND date_created     >= now() - interval '30 days'),
    'booked_30d',    count(*) FILTER (WHERE lead_status = 'Booked'
                                        AND date_created     >= now() - interval '30 days'),
    'sent_7d',       count(*) FILTER (WHERE outreach_sent_at >= now() - interval '7 days')
  )
  FROM public.leads
  WHERE client_id = p_client_id;
$$;

REVOKE ALL ON FUNCTION public.client_lead_stats(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.client_lead_stats(uuid) TO service_role;

-- Verification — should report 1094 for Eazer, not 1000:
--   SELECT public.client_lead_stats('1583b401-0357-4935-a8c7-ba26d48222ad');
