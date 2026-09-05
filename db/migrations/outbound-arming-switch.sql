-- Outbound arming switch — one owner-controlled gate in front of every path
-- that can reach a real person's inbox.
--
-- WHY THIS EXISTS
--
-- "Outbound is off" has been resting on n8n's active flag, and that flag is
-- not readable from the build machine and is demonstrably not what the repo
-- says: exactly one of 326 workflow files carries active:true, while three
-- others were observed running in production on 2026-09-01. A safety claim
-- that cannot be read is not a safety control.
--
-- Worse, the eligibility guard only ever sat on ONE of the four send paths.
-- clx-follow-up-v2 and clx-booking-v2 each hold their own Send Email node
-- posting straight to gmail.googleapis.com, consulting no entitlement, no
-- autonomy, no campaign and no ownership.
--
-- This gives the owner a single switch, in the database, that every send path
-- checks for itself. It is not a replacement for the eligibility guard — that
-- still decides WHO may be contacted. This decides WHETHER ANYONE may be.
--
-- REUSES sentinel_workflow_breakers rather than adding a table. That is the
-- platform's existing pause mechanism (current_status active|tripped|paused|
-- quarantined), already read by seven Sentinel workflows including auto-pause
-- and auto-resume. A second kill switch would be a second thing to check.
--
-- FAILS CLOSED, three ways:
--   * no row for a workflow            -> not armed
--   * current_status is not 'active'   -> not armed
--   * the function itself errors       -> the caller treats it as not armed
--
-- Applying this file DISARMS outbound. That is deliberate: the safe state is
-- the one you get by default, and arming is an act.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The send paths under the switch.
--
-- Only paths that can reach a PROSPECT. Transactional mail — magic links,
-- password resets, welcome mail, internal alerts — is deliberately NOT here:
-- disarming outbound must never lock a customer out of their own account.
-- ---------------------------------------------------------------------------

INSERT INTO sentinel_workflow_breakers
  (workflow_id, workflow_name, current_status, paused_at, paused_reason, is_essential)
VALUES
  ('clx-outreach-sender-v2',      'CLX - Outreach Sender v2',      'paused', now(), 'disarmed: owner switch', false),
  ('clx-follow-up-v2',            'CLX - Follow Up v2',            'paused', now(), 'disarmed: owner switch', false),
  ('clx-booking-v2',              'CLX - Booking v2',              'paused', now(), 'disarmed: owner switch', false),
  ('clxAgentActionExecutorV1',    'CLX - Agent Action Executor v1','paused', now(), 'disarmed: owner switch', false)
ON CONFLICT (workflow_id) DO UPDATE
  SET workflow_name = EXCLUDED.workflow_name,
      updated_at    = now();
-- NOTE the ON CONFLICT deliberately does NOT touch current_status. Re-running
-- this migration must never silently re-arm, nor disarm, a live decision.

-- ---------------------------------------------------------------------------
-- 2. The check every send path makes for itself.
--
-- One round trip, no joins, safe to call per batch. Returns false for an
-- unknown workflow_id: a send path that forgets to register is a send path
-- that cannot send.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION outbound_is_armed(p_workflow_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT b.current_status = 'active'
       FROM sentinel_workflow_breakers b
      WHERE b.workflow_id = p_workflow_id),
    false);
$$;

COMMENT ON FUNCTION outbound_is_armed(text) IS
  'True only when this send path is explicitly armed. Unknown id -> false.';

-- ---------------------------------------------------------------------------
-- 3. The button.
--
-- Flips every registered send path at once and records who did it. Returns
-- the resulting state so the dashboard renders what actually happened rather
-- than what it asked for.
--
-- Arming is logged as a privileged action because it is one: it is the moment
-- the platform becomes able to contact real people.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_outbound_armed(p_armed boolean, p_actor text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text := CASE WHEN p_armed THEN 'active' ELSE 'paused' END;
  v_rows   jsonb;
  v_count  integer;
BEGIN
  IF p_actor IS NULL OR btrim(p_actor) = '' THEN
    RAISE EXCEPTION 'an actor is required: arming is an accountable action';
  END IF;

  UPDATE sentinel_workflow_breakers
     SET current_status = v_status,
         paused_at      = CASE WHEN p_armed THEN NULL ELSE now() END,
         paused_reason  = CASE WHEN p_armed
                               THEN NULL
                               ELSE 'disarmed by ' || p_actor END,
         updated_at     = now()
   WHERE workflow_id IN ('clx-outreach-sender-v2', 'clx-follow-up-v2',
                         'clx-booking-v2', 'clxAgentActionExecutorV1');

  GET DIAGNOSTICS v_count = ROW_COUNT;

  SELECT jsonb_agg(jsonb_build_object('workflow_id', workflow_id,
                                      'workflow_name', workflow_name,
                                      'status', current_status))
    INTO v_rows
    FROM sentinel_workflow_breakers
   WHERE workflow_id IN ('clx-outreach-sender-v2', 'clx-follow-up-v2',
                         'clx-booking-v2', 'clxAgentActionExecutorV1');

  -- admin_action_log carries two overlapping schemas (the audit found every
  -- row automated and `action` NULL). Only columns that actually exist are
  -- written here, and the human-readable summary goes in result_summary so
  -- the row is legible under either reading.
  INSERT INTO admin_action_log
    (action_type, action, actor_email, target_type, target_id,
     result_summary, success, occurred_at, created_at)
  VALUES (CASE WHEN p_armed THEN 'outbound_armed' ELSE 'outbound_disarmed' END,
          CASE WHEN p_armed THEN 'Armed outbound sending'
                            ELSE 'Disarmed outbound sending' END,
          p_actor,
          'outbound_arming',
          NULL,
          v_count || ' send path(s) set to ' || v_status || ': ' ||
            COALESCE(v_rows::text, '[]'),
          true,
          now(),
          now());

  RETURN jsonb_build_object('armed', p_armed,
                            'paths', COALESCE(v_rows, '[]'::jsonb),
                            'changed', v_count,
                            'at', now());
END;
$$;

COMMENT ON FUNCTION set_outbound_armed(boolean, text) IS
  'Owner switch: arms or disarms every prospect-facing send path at once.';

-- ---------------------------------------------------------------------------
-- 4. Read model for the dashboard.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_outbound_arming AS
  SELECT workflow_id,
         workflow_name,
         current_status,
         (current_status = 'active') AS armed,
         paused_at,
         paused_reason,
         updated_at
    FROM sentinel_workflow_breakers
   WHERE workflow_id IN ('clx-outreach-sender-v2', 'clx-follow-up-v2',
                         'clx-booking-v2', 'clxAgentActionExecutorV1')
   ORDER BY workflow_name;

COMMIT;

-- Verify (expect 4 rows, all armed=false):
--   SELECT * FROM v_outbound_arming;
--   SELECT outbound_is_armed('clx-outreach-sender-v2');   -- false
--   SELECT outbound_is_armed('does-not-exist');           -- false
